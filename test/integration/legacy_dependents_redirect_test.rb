require "test_helper"

class LegacyDependentsRedirectTest < ActionDispatch::IntegrationTest
  test "profiles routes generate /profiles URLs" do
    dependent = dependents(:emma)

    assert_equal "/profiles", dependents_path
    assert_equal "/profiles/new", new_dependent_path
    assert_equal "/profiles/#{dependent.id}", dependent_path(dependent)
    assert_equal "/profiles/#{dependent.id}/avatar", avatar_dependent_path(dependent)
    assert_equal "/profiles/#{dependent.id}/documents", dependent_documents_path(dependent)
    assert_equal "/profiles/#{dependent.id}/documents/new", new_dependent_document_path(dependent)
    assert_equal "/profiles/#{dependent.id}/ai-assistant", dependent_ai_assistant_path(dependent)
    assert_equal "/profiles/#{dependent.id}/care-team", dependent_care_team_memberships_path(dependent)
  end

  test "bare /dependents redirects to /profiles" do
    get "/dependents"

    assert_redirected_to "/profiles"
    assert_response :moved_permanently
  end

  test "nested legacy dependents URLs redirect to profiles" do
    get "/dependents/new"
    assert_redirected_to "/profiles/new"

    get "/dependents/42"
    assert_redirected_to "/profiles/42"

    get "/dependents/42/documents/new"
    assert_redirected_to "/profiles/42/documents/new"

    get "/dependents/42/ai-assistant"
    assert_redirected_to "/profiles/42/ai-assistant"

    get "/dependents/42/care-team"
    assert_redirected_to "/profiles/42/care-team"
  end

  test "legacy redirect preserves the query string" do
    get "/dependents/42/documents?category=insurance&q=ADVANCE-DIRECTIVE"

    assert_redirected_to "/profiles/42/documents?category=insurance&q=ADVANCE-DIRECTIVE"
  end
end
