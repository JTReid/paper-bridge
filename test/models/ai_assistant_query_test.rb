require "test_helper"

class AiAssistantQueryTest < ActiveSupport::TestCase
  test "normalizes and validates a question in the selected account" do
    query = build_query(question: "  What changed?  ")

    assert_predicate query, :valid?
    assert_equal "What changed?", query.question
  end

  test "rejects a dependent from another account" do
    query = build_query(dependent: dependents(:other_dependent))

    assert_not query.valid?
    assert_includes query.errors[:dependent], "must belong to the account"
  end

  test "rejects questions longer than five thousand characters" do
    query = build_query(question: "a" * 5_001)

    assert_not query.valid?
    assert_includes query.errors[:question], "is too long (maximum is 5000 characters)"
  end

  test "rejects a user from another account" do
    query = build_query(user: users(:other_user))

    assert_not query.valid?
    assert_includes query.errors[:user], "must belong to the account"
  end

  test "only resolves cited documents from the selected dependent" do
    outside_document = documents(:outside_account)
    query = build_query(
      answer: {
        answer: "An answer [1].",
        citations: [ { source_number: 1, document_id: outside_document.id } ],
        limitations: []
      }
    )

    query.save!

    assert_empty query.source_documents_by_id
  end

  private

    def build_query(attributes = {})
      AiAssistantQuery.new({
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        question: "What changed?"
      }.merge(attributes))
    end
end
