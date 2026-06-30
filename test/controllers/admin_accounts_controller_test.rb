require "test_helper"

class AdminAccountsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get admin_accounts_path

    assert_redirected_to new_user_session_path
  end

  test "rejects non super admins" do
    sign_in users(:family_admin)

    get admin_accounts_path

    assert_redirected_to dashboard_path
    assert_equal "You do not have access to that page.", flash[:alert]
  end

  test "renders account billing overview for super admins" do
    accounts(:greenfield).billing_subscription.update!(
      stripe_customer_id: "cus_test_123",
      stripe_subscription_id: "sub_test_123",
      status: :active
    )
    sign_in users(:super_admin)

    get admin_accounts_path

    assert_response :success
    assert_includes response.body, "Accounts"
    assert_includes response.body, accounts(:greenfield).name
    assert_includes response.body, "cus_test_123"
    assert_includes response.body, "sub_test_123"
  end
end
