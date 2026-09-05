require "test_helper"

class DependentTest < ActiveSupport::TestCase
  test "normalizes separate names and displays multiword last names" do
    dependent = Dependent.create!(
      account: accounts(:greenfield),
      first_name: "  Ana  ",
      last_name: "  de la Cruz  "
    )

    dependent.reload

    assert_equal "Ana", dependent.first_name
    assert_equal "de la Cruz", dependent.last_name
    assert_equal "Ana de la Cruz", dependent.name
  end

  test "accepts a profile with only a first name" do
    dependent = Dependent.new(account: accounts(:greenfield), first_name: "River", last_name: "  ")

    assert dependent.valid?
    assert_equal "River", dependent.name
  end

  test "requires a nonblank first name even when a last name is supplied" do
    dependent = Dependent.new(account: accounts(:greenfield), first_name: "  ", last_name: "Greenfield")

    assert_not dependent.valid?
    assert_includes dependent.errors[:first_name], "can't be blank"
  end

  test "accepts a supported profile avatar" do
    dependent = Dependent.new(account: accounts(:greenfield), first_name: "Avatar", last_name: "Profile")
    attach_avatar(dependent)

    assert dependent.valid?
    assert dependent.avatar.attached?
    assert dependent.avatar.variable?
  end

  test "defines a square display avatar variant" do
    variant = Dependent.attachment_reflections.fetch("avatar").named_variants.fetch(:display)

    assert_equal({ resize_to_fill: [ 256, 256 ] }, variant.transformations)
  end

  test "rejects unsupported profile avatar content types" do
    dependent = Dependent.new(account: accounts(:greenfield), first_name: "Avatar", last_name: "Profile")
    dependent.avatar.attach(
      io: StringIO.new("plain text"),
      filename: "avatar.txt",
      content_type: "text/plain"
    )

    assert_not dependent.valid?
    assert_includes dependent.errors[:avatar], "must be a JPEG, PNG, or WebP image"
  end

  test "rejects profile avatars larger than five megabytes" do
    dependent = Dependent.new(account: accounts(:greenfield), first_name: "Avatar", last_name: "Profile")
    dependent.avatar.attach(
      io: StringIO.new("a" * (Dependent::AVATAR_MAX_SIZE + 1)),
      filename: "large-avatar.png",
      content_type: "image/png"
    )

    assert_not dependent.valid?
    assert_includes dependent.errors[:avatar], "must be smaller than 5 MB"
  end

  test "allows purchased extra profiles and rejects creation once the allowance is full" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(profile_limit: 6)
    fill_profile_allowance(account)

    dependent = account.dependents.new(first_name: "Seventh")

    assert_not dependent.valid?
    assert_no_difference "Dependent.count" do
      assert_not dependent.save
    end
    assert_includes dependent.errors[:base], "Your managed profile allowance is full. Increase it in Billing before adding another profile."
    assert_equal 6, account.dependents.count
  end

  test "checks the profile allowance even when save skips validations" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(profile_limit: 5)
    fill_profile_allowance(account)
    dependent = account.dependents.new(first_name: "Sixth")

    assert_no_difference "Dependent.count" do
      assert_not dependent.save(validate: false)
    end
    assert dependent.errors[:base].any?
  end

  test "rechecks the allowance under the account lock instead of trusting a cached subscription" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(profile_limit: 6)
    3.times { |index| account.dependents.create!(first_name: "Profile #{index}") }
    assert_equal 6, account.profile_limit
    BillingSubscription.find(account.billing_subscription.id).update!(profile_limit: 5)
    dependent = account.dependents.new(first_name: "Sixth")

    assert dependent.valid?, "The cached subscription still has room before the locked recheck"
    assert_no_difference "Dependent.count" do
      assert_not dependent.save
    end
    assert dependent.errors[:base].any?
  end

  test "retains and allows editing existing profiles and documents after a reduction" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(profile_limit: 6)
    fill_profile_allowance(account)
    profile_ids = account.dependents.ids
    document_ids = account.documents.ids

    account.billing_subscription.update!(profile_limit: 5)

    assert dependents(:emma).update(first_name: "Emilia")
    assert_equal profile_ids.sort, account.dependents.ids.sort
    assert_equal document_ids.sort, account.documents.ids.sort
    assert_not account.dependents.new(first_name: "Another").save
    assert dependents(:noah).destroy
    assert account.profile_limit_reached?, "Five remaining profiles still fill a five-profile allowance"
    account.dependents.find_by!(first_name: "Profile 2").destroy!
    assert account.dependents.create!(first_name: "Replacement").persisted?
  end

  test "preserves unlimited profile creation for legacy subscriptions" do
    account = accounts(:greenfield)

    5.times { |index| account.dependents.create!(first_name: "Legacy #{index}") }

    assert_equal 7, account.dependents.count
    assert_nil account.profile_limit
  end

  private

    def fill_profile_allowance(account)
      while account.dependents.count < account.profile_limit
        account.dependents.create!(first_name: "Profile #{account.dependents.count}")
      end
    end

    def attach_avatar(dependent)
      dependent.avatar.attach(
        io: Rails.root.join("public/icon.png").open,
        filename: "icon.png",
        content_type: "image/png"
      )
    end
end
