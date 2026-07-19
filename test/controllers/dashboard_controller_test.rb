require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "renders the signed in account dashboard" do
    dependent = dependents(:emma)
    dependent.avatar.attach(
      io: Rails.root.join("public/icon.png").open,
      filename: "icon.png",
      content_type: "image/png"
    )
    sign_in users(:family_admin)

    get dashboard_path

    assert_response :success
    assert_includes response.body, "Your Family Hub"
    assert_includes response.body, "Family Calendar"
    assert_includes response.body, "No upcoming events"
    assert_includes response.body, "Profiles"
    assert_includes response.body, dependent.name
    assert_select "img[data-testid='dependent-avatar-dashboard-#{dependent.id}'][src='#{avatar_dependent_path(dependent)}']"
    assert_not_includes response.body, "Ask PaperBridge"
    assert_not_includes response.body, "All Profiles"
    assert_not_includes response.body, "AI Workspace"
    assert_not_includes response.body, "Recent Documents"
    assert_not_includes response.body, "Evidence chunks"
    assert_not_includes response.body, documents(:advance_directive).title
  end

  test "redirects signed in inactive accounts to billing" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in users(:family_admin)

    get dashboard_path

    assert_redirected_to billing_path
    assert_equal "A subscription is required to continue.", flash[:alert]
  end
end
