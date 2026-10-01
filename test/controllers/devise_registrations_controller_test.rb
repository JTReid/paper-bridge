require "test_helper"

class DeviseRegistrationsControllerTest < ActionDispatch::IntegrationTest
  SIGNUP_ENV_KEYS = %w[NEW_ACCOUNTS_NON_BILLABLE MAX_ACCOUNTS].freeze

  setup do
    @signup_environment = ENV.to_h.slice(*SIGNUP_ENV_KEYS)
    SIGNUP_ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    SIGNUP_ENV_KEYS.each { |key| ENV.delete(key) }
    ENV.update(@signup_environment)
  end

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

  test "signups create non-billable accounts while NEW_ACCOUNTS_NON_BILLABLE is true" do
    ENV["NEW_ACCOUNTS_NON_BILLABLE"] = "true"

    post user_registration_path, params: {
      user: {
        account_name: "Meadow Family",
        name: "Riley Meadow",
        email: "riley-meadow@example.test",
        password: "password",
        password_confirmation: "password"
      }
    }

    account = User.find_by!(email: "riley-meadow@example.test").account
    assert_redirected_to dashboard_path
    assert_equal "Meadow Family", account.name
    assert account.non_billable?
    assert account.product_access?
    assert_nil account.billing_subscription
  end

  test "signup is closed with a contact message once MAX_ACCOUNTS is reached" do
    ENV["MAX_ACCOUNTS"] = Account.count.to_s

    get new_user_registration_path

    assert_response :success
    assert_select "[data-testid='registration-limit-reached']", text: /#{Regexp.escape(Account::SIGNUP_LIMIT_REACHED_MESSAGE)}/
    assert_select "[data-testid='registration-form']", count: 0

    assert_no_difference [ "User.count", "Account.count" ] do
      post user_registration_path, params: { user: signup_params(email: "capped@example.test") }
    end
    assert_response :unprocessable_content
    assert_includes response.body, Account::SIGNUP_LIMIT_REACHED_MESSAGE
  end

  test "signup stays open below MAX_ACCOUNTS and closes once the last account is created" do
    ENV["MAX_ACCOUNTS"] = (Account.count + 1).to_s

    get new_user_registration_path
    assert_select "[data-testid='registration-form']"

    assert_difference "Account.count", 1 do
      post user_registration_path, params: { user: signup_params(email: "last-spot@example.test") }
    end
    assert_redirected_to billing_path

    delete destroy_user_session_path
    get new_user_registration_path
    assert_select "[data-testid='registration-limit-reached']"
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

  private

    def signup_params(email:)
      {
        account_name: "Capped Family",
        name: "Casey Capped",
        email: email,
        password: "password",
        password_confirmation: "password"
      }
    end
end
