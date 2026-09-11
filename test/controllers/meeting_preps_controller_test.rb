require "test_helper"

class MeetingPrepsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dependent = dependents(:emma)
    @user = users(:family_admin)
    sign_in @user
  end

  test "requires authentication" do
    sign_out @user
    get dependent_meeting_preps_path(@dependent)
    assert_redirected_to new_user_session_path
  end

  test "creates and renames an owned meeting with server derived ownership" do
    get new_dependent_meeting_prep_path(@dependent)
    assert_response :success
    assert_difference "MeetingPrep.count", 1 do
      post dependent_meeting_preps_path(@dependent), params: { meeting_prep: {
        name: "  IEP meeting  ", account_id: accounts(:other).id,
        dependent_id: dependents(:noah).id, user_id: users(:account_member).id
      } }
    end
    meeting = MeetingPrep.last
    assert_redirected_to dependent_meeting_prep_path(@dependent, meeting)
    assert_equal [ accounts(:greenfield).id, @dependent.id, @user.id ], [ meeting.account_id, meeting.dependent_id, meeting.user_id ]
    assert_equal "IEP meeting", meeting.name
    get edit_dependent_meeting_prep_path(@dependent, meeting)
    assert_response :success
    patch dependent_meeting_prep_path(@dependent, meeting), params: { meeting_prep: { name: "October IEP", user_id: users(:account_member).id } }
    assert_redirected_to dependent_meeting_prep_path(@dependent, meeting)
    assert_equal "October IEP", meeting.reload.name
    assert_equal @user, meeting.user
  end

  test "invalid meeting names render errors" do
    assert_no_difference "MeetingPrep.count" do
      post dependent_meeting_preps_path(@dependent), params: { meeting_prep: { name: "  " } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Name can&#39;t be blank"
    meeting = create_meeting
    patch dependent_meeting_prep_path(@dependent, meeting), params: { meeting_prep: { name: "" } }
    assert_response :unprocessable_entity
    assert_equal "IEP meeting", meeting.reload.name
  end

  test "index shows only this user's meetings in this profile" do
    owned = create_meeting
    other_meetings = [ create_meeting(user: users(:account_member)), create_meeting(dependent: dependents(:noah)) ]
    get dependent_meeting_preps_path(@dependent)
    assert_response :success
    assert_select "a[href='#{dependent_meeting_prep_path(@dependent, owned)}']"
    other_meetings.each do |meeting|
      assert_select "a[href='#{dependent_meeting_prep_path(@dependent, meeting)}']", count: 0
    end
  end

  test "meeting loads all selected answers without starting AI work" do
    meeting = create_meeting
    30.times do |index|
      query = AiAssistantQuery.create!(account: accounts(:greenfield), dependent: @dependent, user: @user,
        question: "Question #{index}", state: :completed, completed_at: Time.current,
        answer: { answer: "Prepared response number #{index}." })
      meeting.add_answer!(SavedAnswer.save_from_query!(query))
    end
    assert_no_difference [ "AiAssistantQuery.count", "PipelineRun.count" ] do
      assert_no_enqueued_jobs do
        get dependent_meeting_prep_path(@dependent, meeting)
      end
    end
    assert_response :success
    30.times { |index| assert_includes response.body, "Prepared response number #{index}." }
  end

  test "private meetings cannot be read edited or deleted by another account member" do
    meeting = create_meeting(user: users(:account_member))
    [ :get, :patch, :delete ].each do |verb|
      sign_in @user
      public_send(verb, dependent_meeting_prep_path(@dependent, meeting), params: { meeting_prep: { name: "Changed" } })
      assert_response :not_found
    end
    assert_equal "IEP meeting", meeting.reload.name
  end

  test "another account's profile cannot be used for research" do
    get dependent_meeting_preps_path(dependents(:other_dependent))
    assert_response :not_found
  end

  test "deleting a meeting keeps saved research and its use in other meetings" do
    meeting = create_meeting
    second = create_meeting(name: "Next meeting")
    query = AiAssistantQuery.create!(account: accounts(:greenfield), dependent: @dependent, user: @user,
      question: "What helps?", state: :completed, answer: { answer: "Visual supports." })
    saved = SavedAnswer.save_from_query!(query)
    meeting.add_answer!(saved)
    second.add_answer!(saved)
    assert_difference [ "MeetingPrep.count", "MeetingPrepAnswer.count" ], -1 do
      assert_no_difference "SavedAnswer.count" do
        delete dependent_meeting_prep_path(@dependent, meeting)
      end
    end
    assert_redirected_to dependent_meeting_preps_path(@dependent)
    assert_equal [ saved.id ], second.saved_answer_ids
  end

  private

    def create_meeting(attributes = {})
      MeetingPrep.create!({ account: accounts(:greenfield), dependent: @dependent, user: @user, name: "IEP meeting" }.merge(attributes))
    end
end
