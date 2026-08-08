# frozen_string_literal: true

class AiAssistantQuery < ApplicationRecord
  STATES = {
    queued: "queued",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }.freeze

  belongs_to :account
  belongs_to :dependent
  belongs_to :user

  has_many :pipeline_runs, as: :subject, dependent: :destroy

  enum :state, STATES

  validates :question, presence: true, length: { maximum: 5_000 }
  validate :dependent_belongs_to_account
  validate :user_belongs_to_account

  before_validation :normalize_question
  after_update_commit :broadcast_result, if: :result_changed?

  def answer_payload
    answer.deep_symbolize_keys
  end

  def source_documents_by_id
    document_ids = Array(answer_payload[:citations]).filter_map { |citation| citation[:document_id] }
    dependent.documents.where(id: document_ids).index_by(&:id)
  end

  def active?
    queued? || processing?
  end

  private

    def normalize_question
      self.question = question.to_s.strip
    end

    def dependent_belongs_to_account
      return if account.blank? || dependent.blank? || dependent.account_id == account_id

      errors.add(:dependent, "must belong to the account")
    end

    def user_belongs_to_account
      return if account.blank? || user.blank? || user.account_memberships.exists?(account_id: account_id)

      errors.add(:user, "must belong to the account")
    end

    def result_changed?
      saved_change_to_state? || saved_change_to_draft_answer? || saved_change_to_answer? || saved_change_to_error_message?
    end

    def broadcast_result
      broadcast_replace_to(
        user,
        dependent,
        :ai_assistant,
        target: self,
        partial: "ai_assistant/query_result",
        locals: { ai_assistant_query: self }
      )
    rescue StandardError => e
      Rails.logger.warn(
        "ai_assistant_broadcast_failed query_id=#{id} error_class=#{e.class.name}"
      )
    end
end
