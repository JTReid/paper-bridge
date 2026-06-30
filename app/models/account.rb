class Account < ApplicationRecord
  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :documents, dependent: :destroy
  has_many :document_pages, dependent: :destroy
  has_many :document_chunks, dependent: :destroy
  has_many :dependents, dependent: :destroy
  has_many :care_team_memberships, dependent: :destroy
  has_many :share_events, dependent: :destroy
  has_many :timeline_events, through: :document_chunks
  has_one :billing_subscription, dependent: :destroy

  validates :name, presence: true

  def subscription_active?
    billing_subscription&.active_for_access? || false
  end

  def stripe_customer_id
    billing_subscription&.stripe_customer_id
  end
end
