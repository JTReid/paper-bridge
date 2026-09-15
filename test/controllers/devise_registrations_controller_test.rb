require "test_helper"

class DeviseRegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "shows styled create account form" do
    get new_user_registration_path

    assert_response :success
    assert_select "h1", "Create account"
    assert_not_includes response.body, "AI-Powered Care Advocacy"
    assert_select "form[action='#{user_registration_path}']" do
      assert_select "input[name='user[account_name]']"
      assert_select "input[name='user[name]']"
      assert_select "input[name='user[email]']"
      assert_select "input[name='user[password]']"
      assert_select "input[name='user[password_confirmation]']"
      assert_select "input[type='submit'][value='Create account']"
    end
    assert_not_includes response.body, 'value="New Account"'
    assert_select "a[href='#{new_user_session_path}']", "Sign in"
  end

  test "creates a billable account with the submitted workspace name and ignores exemption parameters" do
    assert_difference -> { User.count }, 1 do
      assert_difference -> { Account.count }, 1 do
        assert_difference -> { AccountMembership.count }, 1 do
          post user_registration_path, params: {
            user: {
              account_name: "Harbor Family",
              name: "Taylor Harbor",
              email: "taylor-harbor@example.test",
              password: "password",
              password_confirmation: "password",
              non_billable: true,
              account_attributes: { non_billable: true }
            }
          }
        end
      end
    end

    user = User.find_by!(email: "taylor-harbor@example.test")
    assert_redirected_to billing_path
    assert_equal "Taylor Harbor", user.name
    assert_equal "Harbor Family", user.account.name
    assert user.can_manage_account?(user.account)
    assert_not user.account.non_billable?
    assert_not user.account.product_access?
    assert_not user.account.subscription_active?
  end

  test "account settings cannot change the non billable flag" do
    user = users(:family_admin)
    account = user.account
    sign_in user

    [ false, true ].each do |non_billable|
      account.update!(non_billable: non_billable)
      updated_name = "Updated Admin #{non_billable}"

      patch user_registration_path, params: {
        user: {
          name: updated_name,
          current_password: "password",
          non_billable: !non_billable,
          account_attributes: { non_billable: !non_billable }
        }
      }

      assert_response :redirect
      assert_equal updated_name, user.reload.name
      assert_equal non_billable, account.reload.non_billable?
    end
  end
end
