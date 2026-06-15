class Document < ApplicationRecord
  STATUSES = {
    uploaded: "uploaded",
    queued: "queued",
    processing: "processing",
    processed: "processed",
    failed: "failed"
  }.freeze

  belongs_to :account
  belongs_to :user
  has_many :document_pages, -> { order(:page_number) }, dependent: :destroy
  has_many :document_chunks, -> { order(:chunk_index) }, dependent: :destroy
  has_many :document_embeddings, through: :document_chunks
  has_many :timeline_events, through: :document_chunks
  has_many :pipeline_runs, as: :subject, dependent: :destroy

  has_one_attached :file

  enum :status, STATUSES
  enum :preparation_status, {
    unprepared: "unprepared",
    preparing: "preparing",
    prepared: "prepared",
    preparation_failed: "failed"
  }

  before_validation :default_title_from_file
  before_validation :cache_file_metadata
  after_create_commit :enqueue_processing_pipeline, if: :file_attached?

  validates :title, :status, :preparation_status, presence: true
  validate :file_is_attached
  validate :account_matches_user

  private

    def default_title_from_file
      return if title.present? || !file.attached?

      self.title = file.blob.filename.base
    end

    def cache_file_metadata
      return unless file.attached?

      self.original_filename = file.blob.filename.to_s
      self.content_type = file.blob.content_type
      self.byte_size = file.blob.byte_size
    end

    def file_is_attached
      errors.add(:file, "must be attached") unless file.attached?
    end

    def file_attached?
      file.attached?
    end

    def enqueue_processing_pipeline
      queued!
      ProcessDocumentJob.perform_later(self)
    end

    def account_matches_user
      return if account.blank? || user.blank? || account_id == user.account_id

      errors.add(:account, "must match the uploading user")
    end
end
