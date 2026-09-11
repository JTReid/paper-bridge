class MeetingPrepAnswer < ApplicationRecord
  belongs_to :meeting_prep
  belongs_to :saved_answer

  validates :saved_answer_id, uniqueness: { scope: :meeting_prep_id }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validate :ownership_matches

  def move!(direction)
    unless direction.to_s.in?(%w[up down])
      errors.add(:base, "Direction must be up or down")
      raise ActiveRecord::RecordInvalid, self
    end

    meeting_prep.with_lock do
      reload
      entries = meeting_prep.meeting_prep_answers.reload.to_a
      current_index = entries.index { |entry| entry.id == id }
      next_index = current_index + (direction.to_s == "up" ? -1 : 1)
      next if next_index.negative? || next_index >= entries.length

      adjacent_entry = entries.fetch(next_index)
      previous_position = position
      update!(position: adjacent_entry.position)
      adjacent_entry.update!(position: previous_position)
    end

    self
  end

  private

    def ownership_matches
      return unless meeting_prep && saved_answer
      return if [ meeting_prep.account_id, meeting_prep.dependent_id, meeting_prep.user_id ] ==
        [ saved_answer.account_id, saved_answer.dependent_id, saved_answer.user_id ]

      errors.add(:saved_answer, "must belong to the same account, profile, and user as the meeting")
    end
end
