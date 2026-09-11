class MeetingPrep < ApplicationRecord
  belongs_to :account
  belongs_to :dependent
  belongs_to :user

  has_many :meeting_prep_answers, -> { order(:position, :id) }, dependent: :destroy
  has_many :saved_answers, through: :meeting_prep_answers

  normalizes :name, with: ->(value) { value.strip }

  validates :name, presence: true
  validate :ownership_matches
  validate :ownership_is_unchanged, on: :update

  def add_answer!(saved_answer)
    add_answers!([ saved_answer ]).first
  end

  def add_answers!(saved_answers)
    answers = saved_answers.uniq(&:id)
    if answers.empty?
      errors.add(:base, "Choose at least one saved answer.")
      raise ActiveRecord::RecordInvalid, self
    end

    with_lock do
      position = meeting_prep_answers.maximum(:position).to_i
      answers.map do |saved_answer|
        meeting_prep_answers.find_or_create_by!(saved_answer: saved_answer) do |entry|
          position += 1
          entry.position = position
        end
      end
    end
  end

  private

    def ownership_matches
      if account && dependent && dependent.account_id != account_id
        errors.add(:dependent, "must belong to the account")
      end
      if account && user && !user.account_memberships.exists?(account_id: account_id)
        errors.add(:user, "must belong to the account")
      end
    end

    def ownership_is_unchanged
      %w[account_id dependent_id user_id].each do |attribute|
        errors.add(attribute, "cannot be changed after creating the meeting") if will_save_change_to_attribute?(attribute)
      end
    end
end
