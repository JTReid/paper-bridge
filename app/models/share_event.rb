class ShareEvent < ApplicationRecord
  STATUSES = {
    pending: "pending",
    sent: "sent",
    failed: "failed"
  }.freeze

  belongs_to :account
  belongs_to :sender, class_name: "User"

  has_many :shared_documents, dependent: :destroy
  has_many :documents, through: :shared_documents

  enum :status, STATUSES

  validates :recipient_email, :status, presence: true
  validate :sender_belongs_to_account

  def mark_sent!
    update!(status: :sent, sent_at: Time.current, error_message: nil)
  end

  def mark_failed!(error)
    update!(status: :failed, error_message: error.message)
  end

  private

    def sender_belongs_to_account
      return if account.blank? || sender.blank? || sender.account_memberships.exists?(account_id: account_id)

      errors.add(:sender, "must belong to the account")
    end
end
