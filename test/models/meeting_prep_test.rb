require "test_helper"

class MeetingPrepTest < ActiveSupport::TestCase
  test "requires a name and matching ownership" do
    meeting = build_meeting(name: " ", account: accounts(:other))

    assert_not meeting.valid?
    assert_includes meeting.errors[:name], "can't be blank"
    assert_includes meeting.errors[:dependent], "must belong to the account"
    assert_includes meeting.errors[:user], "must belong to the account"
  end

  test "can rename a meeting without changing its ownership" do
    meeting = build_meeting
    meeting.save!

    assert meeting.update(name: "  Fall IEP meeting  ")
    assert_equal "Fall IEP meeting", meeting.reload.name
    assert_not meeting.update(dependent: dependents(:noah))
    assert_includes meeting.errors[:dependent_id], "cannot be changed after creating the meeting"
  end

  test "adds answers in order without duplicates" do
    meeting = build_meeting
    meeting.save!
    first = create_saved_answer(question: "First question")
    second = create_saved_answer(question: "Second question")

    assert_no_enqueued_jobs do
      entry = meeting.add_answer!(first)
      meeting.add_answer!(second)
      assert_no_difference -> { MeetingPrepAnswer.count } do
        assert_equal entry, meeting.add_answer!(first)
      end
    end

    assert_equal [ first, second ], meeting.saved_answers.to_a
    assert_equal [ 1, 2 ], meeting.meeting_prep_answers.pluck(:position)
  end

  test "cannot add another account profile or user answer" do
    meeting = build_meeting
    meeting.save!
    [
      { account: accounts(:other), dependent: dependents(:other_dependent), user: users(:other_user) },
      { dependent: dependents(:noah) },
      { user: users(:account_member) }
    ].each do |attributes|
      answer = create_saved_answer(**attributes)

      assert_no_difference -> { MeetingPrepAnswer.count } do
        assert_raises(ActiveRecord::RecordInvalid) { meeting.add_answer!(answer) }
      end
    end
  end

  test "batch add appends new answers in submitted order and returns each membership once" do
    meeting = build_meeting
    meeting.save!
    existing = create_saved_answer(question: "Already prepared")
    first = create_saved_answer(question: "First selection")
    second = create_saved_answer(question: "Second selection")
    existing_entry = meeting.add_answer!(existing)

    entries = nil
    assert_difference -> { MeetingPrepAnswer.count }, 2 do
      assert_no_enqueued_jobs do
        entries = meeting.add_answers!([ second, existing, first, second ])
      end
    end

    assert_equal [ second.id, existing.id, first.id ], entries.map(&:saved_answer_id)
    assert_equal existing_entry.id, entries.second.id
    assert_equal [ existing.id, second.id, first.id ], meeting.saved_answer_ids
    assert_equal [ 1, 2, 3 ], meeting.meeting_prep_answers.pluck(:position)

    assert_no_difference -> { MeetingPrepAnswer.count } do
      assert_equal entries.map(&:id), meeting.add_answers!([ second, existing, first ]).map(&:id)
    end
    assert_equal [ existing.id, second.id, first.id ], meeting.reload.saved_answer_ids
  end

  test "batch add rolls back every new membership when any answer has different ownership" do
    meeting = build_meeting
    meeting.save!
    existing = create_saved_answer(question: "Already prepared")
    first = create_saved_answer(question: "Allowed selection")
    other = create_saved_answer(user: users(:account_member))
    meeting.add_answer!(existing)

    assert_no_difference -> { MeetingPrepAnswer.count } do
      assert_raises(ActiveRecord::RecordInvalid) { meeting.add_answers!([ first, other ]) }
    end
    assert_equal [ existing.id ], meeting.reload.saved_answer_ids
    assert_equal 2, meeting.add_answer!(first).position
  end

  test "an empty batch has a useful validation error" do
    meeting = build_meeting
    meeting.save!

    assert_no_difference -> { MeetingPrepAnswer.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) { meeting.add_answers!([]) }
      assert_includes error.record.errors[:base], "Choose at least one saved answer."
    end
  end

  test "removing an entry or meeting preserves the library answer" do
    meeting = build_meeting
    meeting.save!
    answer = create_saved_answer
    entry = meeting.add_answer!(answer)

    assert_no_difference -> { SavedAnswer.count } do
      entry.destroy!
      meeting.add_answer!(answer)
      meeting.destroy!
    end

    assert SavedAnswer.exists?(answer.id)
    assert_empty MeetingPrepAnswer.where(meeting_prep_id: meeting.id)
  end

  test "deleting a library answer removes it from every meeting" do
    answer = create_saved_answer
    meetings = 2.times.map do |index|
      build_meeting(name: "Meeting #{index}").tap do |meeting|
        meeting.save!
        meeting.add_answer!(answer)
      end
    end

    assert_difference -> { MeetingPrepAnswer.count }, -2 do
      answer.destroy!
    end

    meetings.each { |meeting| assert MeetingPrep.exists?(meeting.id) }
  end

  test "deleting a profile removes its meetings saved answers and entries" do
    dependent = Dependent.create!(account: accounts(:greenfield), first_name: "Meeting profile")
    answer = create_saved_answer(dependent: dependent)
    meeting = build_meeting(dependent: dependent)
    meeting.save!
    entry = meeting.add_answer!(answer)

    dependent.destroy!

    assert_not SavedAnswer.exists?(answer.id)
    assert_not MeetingPrep.exists?(meeting.id)
    assert_not MeetingPrepAnswer.exists?(entry.id)
  end

  test "deleting an account removes its meetings saved answers and entries" do
    account = Account.create!(name: "Meeting account")
    user = users(:family_admin)
    user.account_memberships.create!(account: account, role: :admin)
    dependent = Dependent.create!(account: account, first_name: "Meeting profile")
    answer = create_saved_answer(account: account, dependent: dependent, user: user)
    meeting = build_meeting(account: account, dependent: dependent, user: user)
    meeting.save!
    entry = meeting.add_answer!(answer)

    account.destroy!

    assert_not SavedAnswer.exists?(answer.id)
    assert_not MeetingPrep.exists?(meeting.id)
    assert_not MeetingPrepAnswer.exists?(entry.id)
  end

  private

    def build_meeting(**attributes)
      MeetingPrep.new({
        account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin), name: "IEP meeting"
      }.merge(attributes))
    end

    def create_saved_answer(**attributes)
      query = AiAssistantQuery.create!({
        account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
        question: "What supports help?", state: :completed, completed_at: Time.current,
        answer: { answer: "Classroom accommodations help.", citations: [], limitations: [] }
      }.merge(attributes))
      SavedAnswer.save_from_query!(query)
    end
end
