require "test_helper"

class DependentsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependents_path

    assert_redirected_to new_user_session_path
  end

  test "renders account dependents" do
    sign_in users(:family_admin)

    get dependents_path

    assert_response :success
    assert_includes response.body, "Dependents"
    assert_includes response.body, dependents(:emma).name
    assert_not_includes response.body, dependents(:other_dependent).name
  end

  test "renders selected dependent workspace navigation" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "Overview"
    assert_includes response.body, "Documents"
    assert_includes response.body, "AI Assistant"
    assert_includes response.body, "Care Team"
  end
end
