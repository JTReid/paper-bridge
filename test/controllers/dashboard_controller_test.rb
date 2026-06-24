require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "renders the signed in account dashboard" do
    sign_in users(:family_admin)

    get dashboard_path

    assert_response :success
    assert_includes response.body, "Your Family Hub"
    assert_includes response.body, "Family Calendar"
    assert_includes response.body, "No upcoming events"
    assert_includes response.body, "Users"
    assert_includes response.body, dependents(:emma).name
    assert_not_includes response.body, "AI Assistant"
    assert_not_includes response.body, "All Profiles"
    assert_not_includes response.body, "AI Workspace"
    assert_not_includes response.body, "Recent Documents"
    assert_not_includes response.body, "Evidence chunks"
    assert_not_includes response.body, documents(:advance_directive).title
  end
end
