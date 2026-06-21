require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "family admins can manage the family unit" do
    assert users(:family_admin).can_manage_family_unit?
  end

  test "account members cannot manage the family unit" do
    assert_not users(:account_member).can_manage_family_unit?
  end

  test "creates an account during registration when one is not assigned" do
    user = User.new(
      email: "new-user@example.test",
      password: "password",
      password_confirmation: "password",
      account_name: "New Family Account"
    )

    assert_difference -> { Account.count } do
      assert_difference -> { AccountMembership.count } do
        assert user.save
      end
    end

    assert_equal "New Family Account", user.account.name
    assert user.can_manage_account?(user.account)
  end

  test "does not create a family account without a registration account request" do
    user = User.new(
      name: "Invited Therapist",
      email: "invited-therapist@example.test",
      password: "password",
      password_confirmation: "password"
    )

    assert_no_difference -> { Account.count } do
      assert user.save
    end

    assert_nil user.account
  end
end
