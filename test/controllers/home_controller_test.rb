require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "shows public entry actions" do
    get root_path

    assert_response :success
    assert_includes response.body, "PaperBridge"
    assert_includes response.body, "Sign in"
    assert_includes response.body, "Create account"
  end

  test "shows workspace actions for signed in users" do
    sign_in users(:family_admin)

    get root_path

    assert_response :success
    assert_includes response.body, "Open documents"
    assert_includes response.body, "Search indexed document chunks"
    assert_includes response.body, users(:family_admin).account.name
  end
end
