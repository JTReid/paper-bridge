require "test_helper"

class MeetingPrepAnswerTest < ActiveSupport::TestCase
  setup do
    @meeting = MeetingPrep.create!(
      account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin), name: "IEP meeting"
    )
    @entries = 3.times.map do |index|
      query = AiAssistantQuery.create!(
        account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
        question: "Question #{index}", state: :completed, completed_at: Time.current,
        answer: { answer: "Answer #{index}.", citations: [], limitations: [] }
      )
      @meeting.add_answer!(SavedAnswer.save_from_query!(query))
    end
  end

  test "moves entries up and down while preserving their answers" do
    payloads = @entries.map { |entry| entry.saved_answer.answer }

    assert_no_enqueued_jobs do
      @entries.last.move!(:up)
      assert_equal [ @entries.first.id, @entries.last.id, @entries.second.id ], ordered_ids
      @entries.first.move!(:down)
    end

    assert_equal [ @entries.last.id, @entries.first.id, @entries.second.id ], ordered_ids
    assert_equal payloads, @entries.map { |entry| entry.saved_answer.reload.answer }
  end

  test "moving beyond either end leaves the order unchanged" do
    @entries.first.move!(:up)
    @entries.last.move!(:down)

    assert_equal @entries.map(&:id), ordered_ids
  end

  test "moves across gaps left by removed entries" do
    @entries.second.destroy!
    @entries.last.move!(:up)

    assert_equal [ @entries.last.id, @entries.first.id ], ordered_ids
  end

  test "rejects unknown move directions without changing the order" do
    assert_raises(ActiveRecord::RecordInvalid) { @entries.first.move!("sideways") }

    assert_equal @entries.map(&:id), ordered_ids
  end

  test "requires positive integer positions and unique meeting answer pairs" do
    entry = @entries.first.dup
    entry.position = 0

    assert_not entry.valid?
    assert_includes entry.errors[:saved_answer_id], "has already been taken"
    assert_includes entry.errors[:position], "must be greater than 0"
  end

  private

    def ordered_ids
      @meeting.meeting_prep_answers.reload.map(&:id)
    end
end
