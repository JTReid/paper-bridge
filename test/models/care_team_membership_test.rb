require "test_helper"

class CareTeamMembershipTest < ActiveSupport::TestCase
  test "saves normalized contact details without a login or phone number" do
    membership = build_contact(name: "  New Therapist  ", email: "  NEW-THERAPIST@example.test  ", phone_number: " ")

    assert_no_difference [ -> { User.count }, -> { AccountMembership.count } ] do
      assert membership.save
    end

    assert_equal "New Therapist", membership.reload.name
    assert_equal "new-therapist@example.test", membership.email
    assert_nil membership.phone_number
  end

  test "preserves phone formatting and extensions" do
    membership = build_contact(phone_number: " +1 (850) 555-0101 ext. 23 ")

    assert membership.save
    assert_equal "+1 (850) 555-0101 ext. 23", membership.reload.phone_number
  end

  test "requires name email and role" do
    membership = build_contact(name: " ", email: " ", role: nil)

    assert_not membership.valid?
    %i[name email role].each { |attribute| assert_includes membership.errors[attribute], "can't be blank" }
  end

  test "rejects malformed email addresses" do
    membership = build_contact(email: "not-an-email")

    assert_not membership.valid?
    assert_includes membership.errors[:email], "is invalid"
  end

  test "prevents duplicate emails within a profile regardless of case" do
    membership = build_contact(email: " THERAPIST@example.test ")

    assert_not membership.valid?
    assert_includes membership.errors[:email], "has already been taken"
  end

  test "allows the same contact email on different profiles" do
    membership = build_contact(dependent: dependents(:noah), email: "therapist@example.test")

    assert membership.save
  end

  test "requires account to match dependent" do
    membership = build_contact(account: accounts(:other), invited_by: users(:other_user))

    assert_not membership.valid?
    assert_includes membership.errors[:account], "must match the dependent"
  end

  test "requires creator to manage the account" do
    membership = build_contact(invited_by: users(:account_member))

    assert_not membership.valid?
    assert_includes membership.errors[:invited_by], "must be able to manage the account"
  end

  private

    def build_contact(**attributes)
      CareTeamMembership.new({
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        invited_by: users(:family_admin),
        name: "New Therapist",
        email: "new-therapist@example.test",
        role: :therapist
      }.merge(attributes))
    end
end
