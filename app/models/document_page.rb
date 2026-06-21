class DocumentPage < ApplicationRecord
  STATUSES = {
    pending: "pending",
    processing: "processing",
    processed: "processed",
    failed: "failed"
  }.freeze

  belongs_to :account
  belongs_to :document

  has_many :document_chunks, -> { order(:chunk_index) }, dependent: :destroy
  has_many :timeline_events, through: :document_chunks

  has_one_attached :image

  enum :status, STATUSES

  after_create_commit :broadcast_document_processing_stats
  after_destroy_commit :broadcast_document_processing_stats

  validates :page_number, :status, presence: true
  validates :page_number, uniqueness: { scope: :document_id }
  validate :account_matches_document

  private

    def broadcast_document_processing_stats
      document&.broadcast_processing_stats_update
    end

    def account_matches_document
      return if account.blank? || document.blank? || account_id == document.account_id

      errors.add(:account, "must match the document")
    end
end
