class SavedAnswer < ApplicationRecord
  SNAPSHOT_ATTRIBUTES = %w[account_id dependent_id user_id ai_assistant_query_id question answer generated_at].freeze

  belongs_to :account
  belongs_to :dependent
  belongs_to :user
  belongs_to :ai_assistant_query, optional: true

  has_many :meeting_prep_answers, dependent: :destroy
  has_many :meeting_preps, through: :meeting_prep_answers

  normalizes :title, :notes, with: ->(value) { value.strip.presence }

  validates :question, :generated_at, presence: true
  validates :ai_assistant_query_id, uniqueness: true, allow_nil: true
  validate :answer_text_present
  validate :ownership_matches
  validate :snapshot_is_unchanged, on: :update

  scope :search, ->(query) {
    text = query.to_s.strip
    if text.blank?
      all
    else
      pattern = "%#{sanitize_sql_like(text)}%"
      where(<<~SQL.squish, pattern: pattern)
        (
          saved_answers.title ILIKE :pattern
          OR saved_answers.question ILIKE :pattern
          OR saved_answers.answer->>'answer' ILIKE :pattern
          OR saved_answers.notes ILIKE :pattern
          OR EXISTS (
            SELECT 1
            FROM jsonb_array_elements(
              COALESCE(NULLIF(saved_answers.answer->'citations', 'null'::jsonb), '[]'::jsonb)
            ) AS citation
            WHERE citation->>'document_title' ILIKE :pattern
          )
        )
      SQL
    end
  }

  def self.save_from_query!(query)
    query.with_lock do
      unless query.persisted? && query.completed? && query.answer_payload[:answer].is_a?(String) && query.answer_payload[:answer].present?
        query.errors.add(:base, "Only completed answers can be saved")
        raise ActiveRecord::RecordInvalid, query
      end

      find_or_create_by!(user: query.user, ai_assistant_query: query) do |saved_answer|
        saved_answer.account = query.account
        saved_answer.dependent = query.dependent
        saved_answer.question = query.question
        saved_answer.answer = query.answer.deep_dup
        saved_answer.generated_at = query.completed_at || query.updated_at
      end
    end
  end

  def display_title
    title.presence || question
  end

  def answer_payload
    answer.deep_symbolize_keys
  end

  def source_documents_by_id
    document_ids = Array(answer_payload[:citations]).filter_map { |citation| citation[:document_id] }
    dependent.documents.where(id: document_ids).includes(file_attachment: :blob).index_by(&:id)
  end

  def search_text
    source_titles = Array(answer_payload[:citations]).map { |citation| citation[:document_title] }
    [ title, question, answer_payload[:answer], notes, *source_titles ].compact.join(" ").downcase
  end

  private

    def answer_text_present
      return if answer.is_a?(Hash) && answer_payload[:answer].is_a?(String) && answer_payload[:answer].present?

      errors.add(:answer, "must contain a completed answer")
    end

    def ownership_matches
      if account && dependent && dependent.account_id != account_id
        errors.add(:dependent, "must belong to the account")
      end
      if account && user && !user.account_memberships.exists?(account_id: account_id)
        errors.add(:user, "must belong to the account")
      end
      return unless ai_assistant_query
      return if [ account_id, dependent_id, user_id ] ==
        [ ai_assistant_query.account_id, ai_assistant_query.dependent_id, ai_assistant_query.user_id ]

      errors.add(:ai_assistant_query, "must belong to the same account, profile, and user")
    end

    def snapshot_is_unchanged
      SNAPSHOT_ATTRIBUTES.each do |attribute|
        errors.add(attribute, "cannot be changed after saving") if will_save_change_to_attribute?(attribute)
      end
    end
end
