require "test_helper"
require "active_record/testing/query_assertions"

class SavedAnswerTest < ActiveSupport::TestCase
  include ActiveRecord::Assertions::QueryAssertions

  test "snapshots a completed answer without changing or running its query" do
    query = create_query
    original = query.attributes
    saved_answer = nil

    assert_no_enqueued_jobs do
      assert_no_difference -> { PipelineRun.count } do
        saved_answer = SavedAnswer.save_from_query!(query)
      end
    end

    assert_equal original, query.reload.attributes
    assert_equal query.user, saved_answer.user
    assert_equal query.account, saved_answer.account
    assert_equal query.dependent, saved_answer.dependent
    assert_equal query.question, saved_answer.question
    assert_equal query.answer, saved_answer.answer
    assert_equal query.completed_at, saved_answer.generated_at
    assert_operator saved_answer.created_at, :>, saved_answer.generated_at
    assert_equal query.question, saved_answer.display_title
  end

  test "saving the same completed query returns its original snapshot" do
    query = create_query
    saved_answer = SavedAnswer.save_from_query!(query)
    original_answer = saved_answer.answer.deep_dup
    query.update!(answer: { answer: "A different later answer.", citations: [], limitations: [] })

    assert_no_difference -> { SavedAnswer.count } do
      assert_equal saved_answer, SavedAnswer.save_from_query!(query)
    end

    assert_equal original_answer, saved_answer.reload.answer
  end

  test "a query can have only one snapshot even when another user is supplied" do
    saved_answer = SavedAnswer.save_from_query!(create_query)
    duplicate = saved_answer.dup
    duplicate.user = users(:account_member)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:ai_assistant_query_id], "has already been taken"

    assert_raises ActiveRecord::RecordNotUnique do
      SavedAnswer.transaction(requires_new: true) { duplicate.save!(validate: false) }
    end
    assert_equal 1, SavedAnswer.where(ai_assistant_query_id: saved_answer.ai_assistant_query_id).count
  end

  test "rejects queued processing failed and empty answers" do
    %w[queued processing failed].each do |state|
      query = create_query(state: state)

      assert_no_difference -> { SavedAnswer.count } do
        assert_raises(ActiveRecord::RecordInvalid) { SavedAnswer.save_from_query!(query) }
      end
    end

    [ "", "  ", nil ].each do |answer|
      query = create_query(answer: { answer: answer })
      assert_raises(ActiveRecord::RecordInvalid) { SavedAnswer.save_from_query!(query) }
    end
  end

  test "only the saved title and notes can change" do
    saved_answer = SavedAnswer.save_from_query!(create_query)

    assert saved_answer.update(title: "  Speech milestones  ", notes: "  Ask about practice.\nKeep the examples.  ")
    assert_equal "Speech milestones", saved_answer.reload.display_title
    assert_equal "Ask about practice.\nKeep the examples.", saved_answer.notes

    {
      account_id: accounts(:other).id,
      dependent_id: dependents(:noah).id,
      user_id: users(:account_member).id,
      ai_assistant_query_id: nil,
      question: "Changed question",
      answer: { answer: "Changed answer" },
      generated_at: 2.days.ago
    }.each do |attribute, value|
      saved_answer.reload
      assert_not saved_answer.update(attribute => value), attribute.to_s
      assert_includes saved_answer.errors[attribute], "cannot be changed after saving"
    end
  end

  test "query deletion leaves the snapshot and its source link intact" do
    query = create_query
    saved_answer = SavedAnswer.save_from_query!(query)
    payload = saved_answer.answer.deep_dup

    query.destroy!

    assert_nil saved_answer.reload.ai_assistant_query_id
    assert_equal payload, saved_answer.answer
    assert_equal [ documents(:advance_directive).id ], saved_answer.source_documents_by_id.keys
    assert saved_answer.update(notes: "Still useful for our meeting.")
  end

  test "database query deletion nullifies the origin without deleting the snapshot" do
    queries = 2.times.map { create_query }
    saved_answers = queries.map { |query| SavedAnswer.save_from_query!(query) }

    assert_no_difference -> { SavedAnswer.count } do
      AiAssistantQuery.where(id: queries.map(&:id)).delete_all
    end

    saved_answers.each do |saved_answer|
      assert_nil saved_answer.reload.ai_assistant_query_id
      assert_equal "Vocabulary increased 25% with AAC_support.", saved_answer.answer_payload[:answer]
      assert saved_answer.update(notes: "Still useful after the query is removed.")
    end
  end

  test "loaded sources render PDF links without additional database queries" do
    citations = 2.times.map do |index|
      document = Document.create!(
        account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
        title: "Source #{index + 1}",
        file: { io: StringIO.new("%PDF-1.4\n% fake test pdf"), filename: "source-#{index + 1}.pdf", content_type: "application/pdf" }
      )
      { source_number: index + 1, document_id: document.id, document_title: document.title, page_number: index + 2 }
    end
    saved_answer = SavedAnswer.save_from_query!(create_query(answer: { answer: "Use visual supports [1, 2].", citations: citations }))
    documents_by_id = saved_answer.source_documents_by_id
    controller = ApplicationController.new
    controller.set_request!(ActionDispatch::TestRequest.create)
    view = controller.view_context
    html = nil

    ActiveRecord::Base.uncached do
      assert_no_queries do
        html = view.ai_answer_with_source_links(
          saved_answer.answer_payload[:answer], citations: citations, documents_by_id: documents_by_id
        )
      end
    end

    links = Nokogiri::HTML.fragment(html).css("a")
    assert_equal 2, links.size
    citations.zip(links).each do |citation, link|
      assert_equal view.original_document_path(citation[:document_id], page: citation[:page_number]), link["href"]
    end
  end

  test "deleting a source retains the answer and citation excerpt" do
    saved_answer = SavedAnswer.save_from_query!(create_query)
    payload = saved_answer.answer.deep_dup

    documents(:advance_directive).destroy!

    assert_equal payload, saved_answer.reload.answer
    assert_equal "IEP Progress Summary", saved_answer.answer_payload[:citations].first[:document_title]
    assert_empty saved_answer.source_documents_by_id
  end

  test "source lookup excludes other profiles within and outside the account" do
    own_document = documents(:advance_directive)
    sibling_document = Document.create!(
      account: accounts(:greenfield), dependent: dependents(:noah), user: users(:family_admin),
      file: { io: StringIO.new("Noah's school report."), filename: "noah-report.txt", content_type: "text/plain" }
    )
    citations = [ own_document, sibling_document, documents(:outside_account) ].map do |document|
      { document_id: document.id, document_title: document.title }
    end
    query = create_query
    query.update!(answer: query.answer.merge("citations" => citations))
    saved_answer = SavedAnswer.save_from_query!(query)

    assert_equal({ own_document.id => own_document }, saved_answer.source_documents_by_id)
  end

  test "search matches visible fields literally and case insensitively within its existing scope" do
    saved_answer = SavedAnswer.save_from_query!(create_query)
    saved_answer.update!(title: "Speech milestones", notes: "Ask Dr Rivera next time.")
    other_answer = SavedAnswer.save_from_query!(create_query(
      account: accounts(:other), dependent: dependents(:other_dependent), user: users(:other_user)
    ))
    scope = users(:family_admin).saved_answers.where(dependent: dependents(:emma))

    [ "SPEECH", "changed since", "VOCABULARY", "rivera", "iep progress", "%", "_" ].each do |query|
      assert_equal [ saved_answer ], scope.search(query).to_a, query
    end

    assert_empty scope.search("absent phrase")
    assert_equal [ saved_answer ], scope.search(" ").to_a
    assert_not_includes scope.search("vocabulary"), other_answer
    assert_includes saved_answer.search_text, "iep progress summary"
    assert_includes saved_answer.search_text, "ask dr rivera next time."
  end

  test "search does not interpret percent and underscore as wildcards" do
    saved_answer = SavedAnswer.save_from_query!(create_query(answer: { answer: "Ordinary answer.", citations: [] }))

    assert_empty SavedAnswer.where(id: saved_answer.id).search("%")
    assert_empty SavedAnswer.where(id: saved_answer.id).search("_")
  end

  test "requires snapshot account profile and query ownership to match" do
    query = create_query
    saved_answer = SavedAnswer.new(
      account: accounts(:other), dependent: query.dependent, user: query.user,
      ai_assistant_query: query, question: query.question, answer: query.answer, generated_at: query.completed_at
    )

    assert_not saved_answer.valid?
    assert_includes saved_answer.errors[:dependent], "must belong to the account"
    assert_includes saved_answer.errors[:user], "must belong to the account"
    assert_includes saved_answer.errors[:ai_assistant_query], "must belong to the same account, profile, and user"
  end

  test "saved answers prevent deletion of their user after the origin is removed" do
    user = User.create!(name: "Saved answer owner", email: "saved-owner@example.test", password: "password")
    user.account_memberships.create!(account: accounts(:greenfield), role: :member)
    query = create_query(user: user)
    saved_answer = SavedAnswer.save_from_query!(query)
    query.destroy!

    assert_not user.destroy
    assert SavedAnswer.exists?(saved_answer.id)
  end

  private

    def create_query(**attributes)
      AiAssistantQuery.create!({
        account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
        question: "What changed since spring?", state: :completed, completed_at: 1.hour.ago,
        answer: {
          answer: "Vocabulary increased 25% with AAC_support.",
          citations: [ {
            source_number: 1, document_id: documents(:advance_directive).id,
            document_title: "IEP Progress Summary", page_number: 1, quote: "Vocabulary increased."
          } ],
          limitations: [ "Only the spring report is available." ]
        }
      }.merge(attributes))
    end
end
