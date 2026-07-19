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
      "prescriptions" => %w[medical general],
      "therapy" => %w[therapy behavior medical general],
      "insurance" => %w[financial general],
      "general" => %w[general]
    }.freeze

    ROLE_CATEGORIES = {
      "account_owner" => Document.categories.keys,
      "admin" => Document.categories.keys,
      "member" => Document.categories.keys,
      "owner" => Document.categories.keys,
      "doctor" => %w[medical prescriptions therapy general],
      "physician" => %w[medical prescriptions therapy general],
      "clinician" => %w[medical prescriptions therapy general],
      "therapist" => %w[medical prescriptions therapy general],
      "teacher" => %w[educational general],
      "school_admin" => %w[educational general],
      "educator" => %w[educational general],
      "legal_advocate" => %w[educational general]
    }.freeze

    attr_reader :role, :allowed_chunk_labels, :allowed_document_categories

    def self.for(actor, account: nil, dependent: nil)
      if account && actor&.can_manage_account?(account)
        return new(role: "admin")
      end

      membership = if dependent
        actor&.care_team_memberships&.active&.find_by(dependent: dependent)
      end

      if membership
        categories = membership.allowed_document_categories
        labels = categories.flat_map { |category| CATEGORY_LABELS.fetch(category, []) }.uniq
        return new(role: membership.role, allowed_chunk_labels: labels, allowed_document_categories: categories)
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

    def initialize(role:, allowed_chunk_labels: nil, allowed_document_categories: nil)
      @role = role.to_s
      @allowed_chunk_labels = normalize_labels(allowed_chunk_labels || ROLE_LABELS.fetch(@role, %w[general]))
      @allowed_document_categories = normalize_categories(
        allowed_document_categories || ROLE_CATEGORIES.fetch(@role, %w[general])
      )
    end

    def allows_label?(label)
      allowed_chunk_labels.include?(label.to_s)
    end

    def allows_category?(category)
      allowed_document_categories.include?(category.to_s)
    end

    def to_h
      {
        role: role,
        allowed_chunk_labels: allowed_chunk_labels,
        allowed_document_categories: allowed_document_categories
      }
    end

    private

      def normalize_labels(labels)
        Array(labels).map(&:to_s) & DocumentChunk::LABELS
      end

      def normalize_categories(categories)
        Array(categories).map(&:to_s) & Document.categories.keys
      end
  end
end
