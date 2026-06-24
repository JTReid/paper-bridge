class SharedDocument < ApplicationRecord
  belongs_to :share_event
  belongs_to :document

  validates :document_id, uniqueness: { scope: :share_event_id }
  validate :document_belongs_to_share_account

  private

    def document_belongs_to_share_account
      return if share_event.blank? || document.blank? || document.account_id == share_event.account_id

      errors.add(:document, "must belong to the share account")
    end
end
