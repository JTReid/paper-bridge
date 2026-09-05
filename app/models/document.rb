class Document < ApplicationRecord
  STATUSES = {
    uploaded: "uploaded",
    queued: "queued",
    processing: "processing",
    processed: "processed",
    failed: "failed"
  }.freeze

  CATEGORIES = {
    educational: "educational",
    medical: "medical",
    prescriptions: "prescriptions",
    therapy: "therapy",
    insurance: "insurance",
    general: "general"
  }.freeze

  belongs_to :account
  belongs_to :dependent
  belongs_to :user
  has_many :document_pages, -> { order(:page_number) }, dependent: :destroy
  has_many :document_chunks, -> { order(:chunk_index) }, dependent: :destroy
  has_many :document_embeddings, through: :document_chunks
  has_many :timeline_events, through: :document_chunks
  has_many :pipeline_runs, as: :subject, dependent: :destroy
  has_many :shared_documents, dependent: :destroy
  has_many :share_events, through: :shared_documents

  has_one_attached :file

  enum :status, STATUSES
  enum :category, CATEGORIES
  enum :preparation_status, {
    unprepared: "unprepared",
    preparing: "preparing",
    prepared: "prepared",
    preparation_failed: "failed"
  }

  scope :search_by_filename, ->(query) {
    filename = sanitize_sql_like(query.to_s.strip)
    where("documents.original_filename ILIKE ?", "%#{filename}%")
  }

  before_validation :default_title_from_file
  before_validation :cache_file_metadata
  after_create_commit :enqueue_processing_pipeline, if: :file_attached?
  after_update_commit :broadcast_processing_update_for_change, if: :processing_broadcastable_change?

  validates :title, :status, :preparation_status, :category, presence: true
  validate :file_is_attached
  validate :account_matches_user
  validate :account_matches_dependent
  validate :initial_metadata_finished_before_edit, on: :update

  def complete_initial_metadata!(category:, description:)
    with_lock do
      next false unless initial_metadata_pending?

      raise ArgumentError, "Document classification must use a supported category" unless self.class.categories.key?(category)
      raise ArgumentError, "Document description was not generated" unless description.is_a?(String) && description.squish.present?

      update!(category: category, description: description.squish, initial_metadata_pending: false)
      self.class.current_transaction.after_commit { broadcast_editable_metadata }
      true
    end
  end

  def broadcast_processing_update
    broadcast_processing_status_update
    broadcast_processing_stats_update
    broadcast_summary_update
    broadcast_file_details_update
    broadcast_description_update
  end

  def broadcast_processing_stats_update
    broadcast_replace_to(
      self,
      target: processing_target(:processing_stats),
      partial: "documents/processing_stats",
      locals: { document: self }
    )
  end

  private

    def initial_metadata_finished_before_edit
      return unless initial_metadata_pending? && (will_save_change_to_category? || will_save_change_to_description?)

      errors.add(:base, "Category and description can be edited after initial document processing finishes.")
    end

    def broadcast_editable_metadata
      document = self.class.find(id)
      broadcast_replace_to(
        document,
        target: processing_target(:editable_metadata),
        partial: "documents/editable_metadata",
        locals: { document: document }
      )
    end

    def broadcast_description_update
      broadcast_replace_to(
        self,
        target: processing_target(:description),
        partial: "documents/description",
        locals: { document: self }
      )
    end

    def broadcast_processing_status_update
      broadcast_replace_to(
        self,
        target: processing_target(:processing_status),
        partial: "documents/processing_status",
        locals: { document: self }
      )
    end

    def broadcast_file_details_update
      broadcast_replace_to(
        self,
        target: processing_target(:file_details),
        partial: "documents/file_details",
        locals: { document: self }
      )
    end

    def broadcast_summary_update
      broadcast_replace_to(
        self,
        target: processing_target(:summary),
        partial: "documents/summary",
        locals: { document: self }
      )
    end

    def processing_target(prefix)
      ActionView::RecordIdentifier.dom_id(self, prefix)
    end

    def broadcast_processing_update_for_change
      self.class.find(id).broadcast_processing_update
    end

    def processing_broadcastable_change?
      previous_changes.key?("status") ||
        previous_changes.key?("preparation_status") ||
        previous_changes.key?("preparation_error") ||
        previous_changes.key?("summary") ||
        previous_changes.key?("summarized_at") ||
        previous_changes.key?("initial_metadata_pending") ||
        previous_changes.key?("description")
    end

    def default_title_from_file
      return unless new_record?
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
      processing_job_class.perform_later(self)
    end

    def processing_job_class
      return ProcessImageDocumentJob if file.blob.content_type.to_s.start_with?("image/")

      ProcessDocumentJob
    end

    def account_matches_user
      return if account.blank? || user.blank? || user.account_memberships.exists?(account_id: account_id)

      errors.add(:account, "must be manageable by the uploading user")
    end

    def account_matches_dependent
      return if account.blank? || dependent.blank? || account_id == dependent.account_id

      errors.add(:account, "must match the dependent")
    end
end
