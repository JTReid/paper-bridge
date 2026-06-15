# frozen_string_literal: true

module Documents
  class SearchAccessProfile
    ROLE_LABELS = {
      "account_owner" => DocumentChunk::LABELS,
      "family_admin" => DocumentChunk::LABELS,
      "owner" => DocumentChunk::LABELS,
      "profile_user" => DocumentChunk::LABELS,
      "doctor" => %w[medical therapy behavior general],
      "physician" => %w[medical therapy behavior general],
      "clinician" => %w[medical therapy behavior general],
      "therapist" => %w[therapy behavior medical general],
      "teacher" => %w[education behavior general],
      "school_admin" => %w[education behavior general],
      "educator" => %w[education behavior general],
      "legal_advocate" => %w[legal education general]
    }.freeze

    attr_reader :role, :allowed_chunk_labels

    def self.for(actor)
      new(role: actor&.role)
    end

    def initialize(role:, allowed_chunk_labels: nil)
      @role = role.to_s
      @allowed_chunk_labels = normalize_labels(allowed_chunk_labels || ROLE_LABELS.fetch(@role, %w[general]))
    end

    def allows_label?(label)
      allowed_chunk_labels.include?(label.to_s)
    end

    def to_h
      {
        role: role,
        allowed_chunk_labels: allowed_chunk_labels
      }
    end

    private

      def normalize_labels(labels)
        Array(labels).map(&:to_s) & DocumentChunk::LABELS
      end
  end
end
