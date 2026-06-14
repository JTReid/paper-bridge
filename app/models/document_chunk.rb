require "digest"

class DocumentChunk < ApplicationRecord
  LABELS = %w[
    medical
    education
    therapy
    behavior
    legal
    financial
    general
  ].freeze

  belongs_to :account
  belongs_to :document
  belongs_to :document_page

  has_many :document_embeddings, dependent: :destroy

  validates :content, :content_hash, :label, :chunk_index, presence: true
  validates :label, inclusion: { in: LABELS }
  validates :chunk_index, uniqueness: { scope: :document_id }
  validates :content_hash, uniqueness: { scope: :document_id }
  validate :account_matches_document
  validate :document_page_matches_document

  def self.content_hash_for(content)
    Digest::SHA256.hexdigest(normalized_hash_content(content))
  end

  def self.normalize_content(content)
    content.to_s
           .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
           .gsub(/\r\n?/, "\n")
           .split("\n")
           .map(&:rstrip)
           .join("\n")
           .gsub(/\n{3,}/, "\n\n")
           .strip
  end

  def self.normalized_hash_content(content)
    normalize_content(content)
      .unicode_normalize(:nfkc)
      .downcase
      .gsub(/\s+/, " ")
      .strip
  end

  private

    def account_matches_document
      return if account.blank? || document.blank? || account_id == document.account_id

      errors.add(:account, "must match the document")
    end

    def document_page_matches_document
      return if document.blank? || document_page.blank? || document_page.document_id == document_id

      errors.add(:document_page, "must belong to the document")
    end
end
