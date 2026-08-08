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

  test "keeps a completed answer when Turbo delivery fails" do
    query = build_query
    query.save!
    query.define_singleton_method(:broadcast_replace_to) do |*, **|
      raise "Cable is unavailable"
    end

    query.update!(
      state: :completed,
      answer: { answer: "A paid final answer.", citations: [], limitations: [] },
      completed_at: Time.current
    )

    assert_predicate query.reload, :completed?
    assert_equal "A paid final answer.", query.answer_payload[:answer]
  end

  test "enqueues the answer job only once" do
    query = build_query
    query.save!

    assert_enqueued_with(job: AnswerAiAssistantQueryJob, args: [ query ], queue: "ai_assistant") do
      assert query.enqueue_answer!
    end

    assert_not_nil query.reload.enqueued_at
    assert_no_enqueued_jobs do
      assert_not query.enqueue_answer!
    end
  end

  test "allows a start retry when Active Job rejects the enqueue" do
    query = build_query
    query.save!

    with_stubbed_singleton_method(AnswerAiAssistantQueryJob, :perform_later, false) do
      assert_raises(ActiveJob::EnqueueError) { query.enqueue_answer! }
    end

    assert_nil query.reload.enqueued_at
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
