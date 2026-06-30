class BillingSubscription < ApplicationRecord
  ACCESS_STATUSES = %w[active trialing].freeze
  STATUSES = {
    incomplete: "incomplete",
    incomplete_expired: "incomplete_expired",
    trialing: "trialing",
    active: "active",
    past_due: "past_due",
    canceled: "canceled",
    unpaid: "unpaid",
    paused: "paused"
  }.freeze

  belongs_to :account

  enum :status, STATUSES

  validates :status, presence: true
  validates :account_id, uniqueness: true
  validates :stripe_customer_id, uniqueness: true, allow_blank: true
  validates :stripe_subscription_id, uniqueness: true, allow_blank: true

  def active_for_access?
    ACCESS_STATUSES.include?(status)
  end

  def stripe_linked?
    stripe_customer_id.present? || stripe_subscription_id.present?
  end
end
