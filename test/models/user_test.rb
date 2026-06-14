require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "family admins can manage the family unit" do
    assert users(:family_admin).can_manage_family_unit?
  end

  test "profile users cannot manage the family unit" do
    assert_not users(:profile_user).can_manage_family_unit?
  end

  test "creates an account during registration when one is not assigned" do
    user = User.new(
      email: "new-user@example.test",
      password: "password",
      password_confirmation: "password",
      account_name: "New Family Account"
    )

    assert_difference -> { Account.count } do
      assert user.save
    end

    assert_equal "New Family Account", user.account.name
  end
end
