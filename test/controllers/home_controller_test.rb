require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "shows public entry actions" do
    get root_path

    assert_response :success
    assert_includes response.body, "PaperBridge"
    assert_includes response.body, "Sign In"
    assert_includes response.body, "Get Started"
    assert_includes response.body, "Your child's"
    assert_includes response.body, "All in one place"
    assert_includes response.body, "advocacy platform that securely organizes"
    assert_includes response.body, "Organize. Empower. Advocate."
    assert_not_includes response.body, "AI-Powered Care Advocacy"
    assert_select "[data-testid='home-nav-secondary']", count: 1
    assert_select "[data-controller='reveal']"
  end

  test "shows workspace actions for signed in users" do
    sign_in users(:family_admin)

    get root_path

    assert_response :success
    assert_includes response.body, "Open dashboard"
    assert_includes response.body, "Dashboard"
    assert_includes response.body, "preserves the complete narrative"
    assert_select "[data-testid='home-nav-secondary']", count: 0
    assert_select "[data-testid='home-mobile-secondary']", count: 0
  end
end
