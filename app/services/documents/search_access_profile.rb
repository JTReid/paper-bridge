# frozen_string_literal: true

module Documents
  class SearchAccessProfile
    ROLE_LABELS = {
      "account_owner" => DocumentChunk::LABELS,
      "admin" => DocumentChunk::LABELS,
      "member" => DocumentChunk::LABELS,
      "owner" => DocumentChunk::LABELS,
      "doctor" => %w[medical therapy behavior general],
      "physician" => %w[medical therapy behavior general],
      "clinician" => %w[medical therapy behavior general],
      "therapist" => %w[therapy behavior medical general],
      "teacher" => %w[education behavior general],
      "school_admin" => %w[education behavior general],
      "educator" => %w[education behavior general],
      "legal_advocate" => %w[legal education general]
    }.freeze

    CATEGORY_LABELS = {
      "educational" => %w[education behavior general],
      "medical" => %w[medical general],
      "therapy" => %w[therapy behavior medical general],
      "insurance" => %w[financial general],
      "general" => %w[general]
    }.freeze

    attr_reader :role, :allowed_chunk_labels

    def self.for(actor, account: nil, dependent: nil)
      if account && actor&.can_manage_account?(account)
        return new(role: "admin")
      end

      membership = if dependent
        actor&.care_team_memberships&.active&.find_by(dependent: dependent)
      end

      if membership
        labels = membership.allowed_document_categories.flat_map { |category| CATEGORY_LABELS.fetch(category, []) }.uniq
        return new(role: membership.role, allowed_chunk_labels: labels)
      end

      role = if actor&.account_memberships&.admin&.exists?
        "admin"
      elsif actor&.account_memberships&.member&.exists?
        "member"
      else
        actor&.care_team_memberships&.active&.first&.role
      end

      new(role: role)
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
