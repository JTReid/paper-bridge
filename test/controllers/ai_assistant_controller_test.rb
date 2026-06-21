require "test_helper"

class AiAssistantControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependent_ai_assistant_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "renders empty assistant without creating a pipeline run" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { PipelineRun.count } do
      get dependent_ai_assistant_path(dependent)
    end

    assert_response :success
    assert_includes response.body, "AI Assistant"
    assert_includes response.body, "Suggested questions"
    assert_includes response.body, "No guessing"
    assert_no_match(/<button[^>]+disabled/, response.body)
  end

  test "renders assistant inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { PipelineRun.count } do
      get dependent_ai_assistant_path(dependent)
    end

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "AI Assistant"
    assert_includes response.body, "Care Team"
  end
end
