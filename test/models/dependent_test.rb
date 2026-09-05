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

  private

    def attach_avatar(dependent)
      dependent.avatar.attach(
        io: Rails.root.join("public/icon.png").open,
        filename: "icon.png",
        content_type: "image/png"
      )
    end
end
