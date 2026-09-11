require "test_helper"

class SavedAnswersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dependent = dependents(:emma)
    @user = users(:family_admin)
    sign_in @user
  end

  test "requires authentication and subscription" do
    sign_out @user
    get dependent_saved_answers_path(@dependent)
    assert_redirected_to new_user_session_path

    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in @user
    get dependent_saved_answers_path(@dependent)
    assert_redirected_to billing_path
  end

  test "saving snapshots the owned completed query without starting more work and is idempotent" do
    query = create_query
    assert_difference "SavedAnswer.count", 1 do
      assert_no_difference [ "AiAssistantQuery.count", "PipelineRun.count" ] do
        assert_no_enqueued_jobs do
          post dependent_saved_answers_path(@dependent), params: {
            ai_assistant_query_id: query.id,
            saved_answer: { answer: { answer: "Forged answer" }, user_id: users(:other_user).id }
          }
        end
      end
    end
    saved = SavedAnswer.last
    assert_redirected_to dependent_saved_answer_path(@dependent, saved)
    assert_equal query.answer, saved.answer
    assert_equal @user, saved.user
    assert_no_difference "SavedAnswer.count" do
      post dependent_saved_answers_path(@dependent), params: { ai_assistant_query_id: query.id }
    end
    assert_redirected_to dependent_saved_answer_path(@dependent, saved)
  end

  test "queued draft and failed queries cannot be saved" do
    %i[queued processing failed].each do |state|
      query = create_query(state: state, draft_answer: "Still a draft")
      assert_no_difference "SavedAnswer.count" do
        post dependent_saved_answers_path(@dependent), params: { ai_assistant_query_id: query.id }
      end
      assert_redirected_to dependent_ai_assistant_path(@dependent)
      assert_match "Only completed answers", flash[:alert]
    end
  end

  test "save cannot cross user profile or account boundaries" do
    queries = [
      create_query(user: users(:account_member)),
      create_query(dependent: dependents(:noah)),
      create_query(account: accounts(:other), dependent: dependents(:other_dependent), user: users(:other_user))
    ]
    queries.each do |query|
      sign_in @user
      assert_no_difference "SavedAnswer.count" do
        post dependent_saved_answers_path(@dependent), params: { ai_assistant_query_id: query.id }
      end
      assert_response :not_found
    end
  end

  test "search matches saved content and source names while respecting ownership and meeting filters" do
    saved = SavedAnswer.save_from_query!(create_query)
    saved.update!(title: "School support", notes: "Ask about transport 50%_complete")
    other = SavedAnswer.save_from_query!(create_query(question: "Unrelated question", answer: { answer: "Unrelated answer" }))
    private_answer = SavedAnswer.save_from_query!(create_query(user: users(:account_member), question: "School support private"))
    meeting = create_meeting
    meeting.add_answer!(saved)

    [ "SCHOOL", "recommended", "visual", "transport", "Evaluation", "50%_complete" ].each do |term|
      get dependent_saved_answers_path(@dependent), params: { q: term, meeting_prep_id: meeting.id }
      assert_response :success
      assert_select "a[href='#{dependent_saved_answer_path(@dependent, saved)}']"
      assert_select "a[href='#{dependent_saved_answer_path(@dependent, other)}']", count: 0
      assert_select "a[href='#{dependent_saved_answer_path(@dependent, private_answer)}']", count: 0
    end
    get dependent_saved_answers_path(@dependent), params: { q: "50X_complete" }
    assert_select "a[href='#{dependent_saved_answer_path(@dependent, saved)}']", count: 0
  end

  test "only title and personal notes can be edited" do
    saved = SavedAnswer.save_from_query!(create_query)
    original = saved.attributes.slice(*SavedAnswer::SNAPSHOT_ATTRIBUTES)
    patch dependent_saved_answer_path(@dependent, saved), params: { saved_answer: {
      title: "  Meeting talking point  ", notes: "  My question for the team  ",
      question: "Changed", answer: { answer: "Changed" }, dependent_id: dependents(:noah).id,
      user_id: users(:account_member).id, ai_assistant_query_id: nil, generated_at: 1.day.ago
    } }
    assert_redirected_to dependent_saved_answer_path(@dependent, saved)
    saved.reload
    assert_equal "Meeting talking point", saved.title
    assert_equal "My question for the team", saved.notes
    assert_equal original, saved.attributes.slice(*SavedAnswer::SNAPSHOT_ATTRIBUTES)
    get edit_dependent_saved_answer_path(@dependent, saved)
    assert_response :success
  end

  test "saved answer source links survive provenance deletion and unavailable sources remain readable" do
    query = create_query
    saved = SavedAnswer.save_from_query!(query)
    get dependent_saved_answer_path(@dependent, saved)
    assert_response :success
    assert_select "a[href='#{document_path(documents(:advance_directive))}']"

    query.destroy!
    documents(:advance_directive).destroy!
    get dependent_saved_answer_path(@dependent, saved)
    assert_response :success
    assert_includes response.body, "visual supports"
    assert_includes response.body, "Teacher observations"
    assert_includes response.body, "Original document is no longer available."
    assert_select "a[href='#{document_path(documents(:advance_directive))}']", count: 0
  end

  test "saved views and mutations are private even within an account" do
    saved = SavedAnswer.save_from_query!(create_query(user: users(:account_member)))
    [ :get, :patch, :delete ].each do |verb|
      sign_in @user
      public_send(verb, dependent_saved_answer_path(@dependent, saved), params: { saved_answer: { title: "Changed" } })
      assert_response :not_found
    end
    assert SavedAnswer.exists?(saved.id)
    assert_nil saved.reload.title
  end

  test "saved answer cannot be read using another profile URL" do
    saved = SavedAnswer.save_from_query!(create_query)
    get dependent_saved_answer_path(dependents(:noah), saved)
    assert_response :not_found
  end

  test "adds an answer to an owned meeting and rejects another user's meeting" do
    saved = SavedAnswer.save_from_query!(create_query)
    meeting = create_meeting
    post add_to_meeting_dependent_saved_answer_path(@dependent, saved), params: { meeting_prep_id: meeting.id }
    assert_redirected_to dependent_meeting_prep_path(@dependent, meeting)
    assert_equal [ saved.id ], meeting.saved_answer_ids

    private_meeting = create_meeting(user: users(:account_member))
    assert_no_difference "MeetingPrepAnswer.count" do
      post add_to_meeting_dependent_saved_answer_path(@dependent, saved), params: { meeting_prep_id: private_meeting.id }
    end
    assert_response :not_found
  end

  test "deleting a saved answer removes its meeting entries but keeps meetings and the original query" do
    query = create_query
    saved = SavedAnswer.save_from_query!(query)
    meeting = create_meeting
    meeting.add_answer!(saved)
    assert_difference [ "SavedAnswer.count", "MeetingPrepAnswer.count" ], -1 do
      assert_no_difference [ "MeetingPrep.count", "AiAssistantQuery.count" ] do
        delete dependent_saved_answer_path(@dependent, saved)
      end
    end
    assert_redirected_to dependent_saved_answers_path(@dependent)
  end

  private

    def create_query(attributes = {})
      AiAssistantQuery.create!({
        account: accounts(:greenfield), dependent: @dependent, user: @user,
        question: "What support was recommended?", state: :completed, completed_at: Time.current,
        answer: { answer: "Use visual supports [1].", limitations: [ "Limited to the uploaded records." ], citations: [
          { source_number: 1, document_id: documents(:advance_directive).id,
            document_title: "Evaluation report", page_number: 2, quote: "Teacher observations" }
        ] }
      }.merge(attributes))
    end

    def create_meeting(attributes = {})
      MeetingPrep.create!({ account: accounts(:greenfield), dependent: @dependent, user: @user, name: "School meeting" }.merge(attributes))
    end
end
