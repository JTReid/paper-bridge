require "test_helper"

class MeetingPrepAnswersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dependent = dependents(:emma)
    @user = users(:family_admin)
    @meeting = MeetingPrep.create!(account: accounts(:greenfield), dependent: @dependent, user: @user, name: "IEP meeting")
    sign_in @user
  end

  test "adds once and appends in selected order" do
    first = create_saved_answer
    second = create_saved_answer
    assert_difference "MeetingPrepAnswer.count", 2 do
      [ first, second, first ].each do |saved|
        post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting), params: { saved_answer_id: saved.id }
        assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
      end
    end
    assert_equal [ first.id, second.id ], @meeting.saved_answer_ids
  end

  test "reorders and removes an entry without changing another meeting or its saved answer" do
    first = create_saved_answer
    second = create_saved_answer
    first_entry = @meeting.add_answer!(first)
    second_entry = @meeting.add_answer!(second)
    other_meeting = MeetingPrep.create!(account: accounts(:greenfield), dependent: @dependent, user: @user, name: "Follow up")
    other_meeting.add_answer!(first)
    other_meeting.add_answer!(second)

    patch dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, second_entry), params: { direction: "up" }
    assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
    assert_equal [ second.id, first.id ], @meeting.reload.saved_answer_ids
    assert_equal [ first.id, second.id ], other_meeting.saved_answer_ids

    assert_no_difference "SavedAnswer.count" do
      delete dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, first_entry)
    end
    assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
    assert_equal [ second.id ], @meeting.reload.saved_answer_ids
    assert_equal [ first.id, second.id ], other_meeting.reload.saved_answer_ids
  end

  test "batch add preserves submitted order is idempotent and does not start AI work" do
    existing = create_saved_answer(question: "Already prepared")
    first = create_saved_answer(question: "First selection")
    second = create_saved_answer(question: "Second selection")
    @meeting.add_answer!(existing)
    request = { saved_answer_ids: [ "", second.id, first.id, second.id, existing.id ] }

    assert_difference "MeetingPrepAnswer.count", 2 do
      assert_no_difference [ "AiAssistantQuery.count", "PipelineRun.count", "SavedAnswer.count" ] do
        assert_no_enqueued_jobs do
          post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting), params: request
        end
      end
    end
    assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
    assert_equal [ existing.id, second.id, first.id ], @meeting.reload.saved_answer_ids

    assert_no_difference "MeetingPrepAnswer.count" do
      post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting), params: request
    end
    assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
    assert_equal [ existing.id, second.id, first.id ], @meeting.reload.saved_answer_ids
  end

  test "mixed batches reject inaccessible or missing answers without adding the allowed selection" do
    allowed = create_saved_answer
    inaccessible_ids = [
      create_saved_answer(user: users(:account_member)).id,
      create_saved_answer(dependent: dependents(:noah)).id,
      create_saved_answer(account: accounts(:other), dependent: dependents(:other_dependent), user: users(:other_user)).id,
      SavedAnswer.maximum(:id) + 1
    ]

    inaccessible_ids.each do |inaccessible_id|
      sign_in @user
      assert_no_difference "MeetingPrepAnswer.count" do
        post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting),
          params: { saved_answer_ids: [ allowed.id, inaccessible_id ] }, headers: turbo_stream_headers
      end
      assert_response :not_found
      assert_empty @meeting.reload.saved_answer_ids
    end
  end

  test "an empty batch redirects HTML with a useful alert" do
    assert_no_difference "MeetingPrepAnswer.count" do
      post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting), params: { saved_answer_ids: [ "" ] }
    end
    assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
    assert_equal "Choose at least one saved answer.", flash[:alert]
  end

  test "batch add updates only the workspace and renders the loaded answers and source links" do
    first = create_saved_answer(question: "Visual support", answer: { answer: "Use visual supports [1].", citations: [
      { source_number: 1, document_id: documents(:advance_directive).id, document_title: "Evaluation report", quote: "Teacher observations" }
    ] })
    second = create_saved_answer(question: "Transport support")

    post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting),
      params: { saved_answer_ids: [ first.id, second.id ] }, headers: turbo_stream_headers

    assert_workspace_update
    assert_includes response.body, "2 answers added to meeting."
    assert_includes response.body, "Visual support"
    assert_includes response.body, "Transport support"
    assert_select "a[href='#{document_path(documents(:advance_directive))}']"
  end

  test "movement and removal update the workspace without redirects or AI work" do
    first = create_saved_answer(question: "First support")
    second = create_saved_answer(question: "Second support")
    first_entry, second_entry = @meeting.add_answers!([ first, second ])

    assert_no_difference [ "AiAssistantQuery.count", "PipelineRun.count", "SavedAnswer.count" ] do
      assert_no_enqueued_jobs do
        patch dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, second_entry),
          params: { direction: "up" }, headers: turbo_stream_headers
        assert_workspace_update
        assert_includes response.body, "Answer moved."
        assert_equal [ second.id, first.id ], @meeting.reload.saved_answer_ids

        delete dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, first_entry), headers: turbo_stream_headers
        assert_workspace_update
        assert_includes response.body, "Answer removed from meeting."
        assert_equal [ second.id ], @meeting.reload.saved_answer_ids
      end
    end
  end

  test "empty batches and invalid movements render validation alerts in a 422 workspace update" do
    entry = @meeting.add_answer!(create_saved_answer)
    assert_no_difference "MeetingPrepAnswer.count" do
      post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting),
        params: { saved_answer_ids: [ "" ] }, headers: turbo_stream_headers
    end
    assert_workspace_update(status: :unprocessable_entity)
    assert_includes response.body, "Choose at least one saved answer."

    patch dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, entry),
      params: { direction: "sideways" }, headers: turbo_stream_headers
    assert_workspace_update(status: :unprocessable_entity)
    assert_includes response.body, "Direction must be up or down"
    assert_equal 1, entry.reload.position
  end

  test "invalid movement does not change ordering" do
    entry = @meeting.add_answer!(create_saved_answer)
    patch dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, entry), params: { direction: "sideways" }
    assert_redirected_to dependent_meeting_prep_path(@dependent, @meeting)
    assert_match "Direction must be up or down", flash[:alert]
    assert_equal 1, entry.reload.position
  end

  test "cannot attach another user's or another profile's saved research" do
    [ create_saved_answer(user: users(:account_member)), create_saved_answer(dependent: dependents(:noah)) ].each do |saved|
      sign_in @user
      assert_no_difference "MeetingPrepAnswer.count" do
        post dependent_meeting_prep_meeting_prep_answers_path(@dependent, @meeting), params: { saved_answer_id: saved.id }
      end
      assert_response :not_found
    end
  end

  test "cannot mutate another user's meeting" do
    other_meeting = MeetingPrep.create!(account: accounts(:greenfield), dependent: @dependent, user: users(:account_member), name: "Private")
    entry = other_meeting.add_answer!(create_saved_answer(user: users(:account_member)))
    patch dependent_meeting_prep_meeting_prep_answer_path(@dependent, other_meeting, entry), params: { direction: "up" }
    assert_response :not_found
    sign_in @user
    delete dependent_meeting_prep_meeting_prep_answer_path(@dependent, other_meeting, entry)
    assert_response :not_found
    assert MeetingPrepAnswer.exists?(entry.id)
  end

  test "cannot remove an entry through a different owned meeting" do
    second = MeetingPrep.create!(account: accounts(:greenfield), dependent: @dependent, user: @user, name: "Second")
    entry = second.add_answer!(create_saved_answer)
    assert_no_difference "MeetingPrepAnswer.count" do
      delete dependent_meeting_prep_meeting_prep_answer_path(@dependent, @meeting, entry)
    end
    assert_response :not_found
  end

  private

    def turbo_stream_headers
      { "Accept" => "text/vnd.turbo-stream.html" }
    end

    def assert_workspace_update(status: :success)
      assert_response status
      assert_equal "text/vnd.turbo-stream.html", response.media_type
      assert_nil response.headers["Location"]
      assert_select "turbo-stream", count: 1
      assert_select "turbo-stream[action='update'][target='workspace_meeting_prep_#{@meeting.id}']", count: 1
    end

    def create_saved_answer(attributes = {})
      query = AiAssistantQuery.create!({ account: accounts(:greenfield), dependent: @dependent, user: @user,
        question: "What support helps?", state: :completed, answer: { answer: "Use visual supports." }
      }.merge(attributes))
      SavedAnswer.save_from_query!(query)
    end
end
