require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "shows public entry actions" do
    get root_path

    assert_response :success
    assert_includes response.body, "PaperBridge"
    assert_includes response.body, "Sign In"
    assert_includes response.body, "Get Started"
    assert_includes response.body, "Turn overwhelming paperwork into"
    assert_select "[data-controller='reveal']"
  end

  test "shows workspace actions for signed in users" do
    sign_in users(:family_admin)

    get root_path

    assert_response :success
    assert_includes response.body, "Open dashboard"
    assert_includes response.body, "Dashboard"
    assert_includes response.body, "Spend less time searching through documents"
  end
end
