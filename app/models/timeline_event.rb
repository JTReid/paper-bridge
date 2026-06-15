require "digest"

class TimelineEvent < ApplicationRecord
  EVENT_TYPES = %w[
    birth
    developmental_milestone
    concern_observed
    evaluation
    diagnosis
    recommendation
    service
    iep
    therapy
    assessment_score
    accommodation
    observation
  ].freeze

  DATE_PRECISIONS = %w[
    exact
    approximate
    range
    age_derived
    unknown
  ].freeze

  DATE_SOURCES = %w[
    explicit
    age_derived
    inferred
    undated
  ].freeze

  belongs_to :document_chunk

  has_one :account, through: :document_chunk
  has_one :document, through: :document_chunk
  has_one :document_page, through: :document_chunk

  validates :event_type, :title, :description, :date_precision, :date_source, :source_quote, :content_hash, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :date_precision, inclusion: { in: DATE_PRECISIONS }
  validates :date_source, inclusion: { in: DATE_SOURCES }
  validates :content_hash, uniqueness: { scope: :document_chunk_id }
  validate :date_range_is_ordered

  scope :chronological, -> {
    order(Arel.sql("COALESCE(occurred_on, started_on, ended_on) ASC NULLS LAST, created_at ASC"))
  }

  def self.content_hash_for(event_type:, title:, description:, occurred_on:, started_on:, ended_on:)
    Digest::SHA256.hexdigest(
      [
        event_type,
        title,
        description,
        occurred_on,
        started_on,
        ended_on
      ].map { |value| value.to_s.unicode_normalize(:nfkc).downcase.squish }.join("|")
    )
  end

  def dated?
    occurred_on.present? || started_on.present? || ended_on.present?
  end

  def sort_date
    occurred_on || started_on || ended_on
  end

  def date_range?
    started_on.present? && ended_on.present?
  end

  private

    def date_range_is_ordered
      return if started_on.blank? || ended_on.blank? || started_on <= ended_on

      errors.add(:ended_on, "must be on or after the start date")
    end
end
