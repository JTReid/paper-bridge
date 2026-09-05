class BillingSubscription < ApplicationRecord
  INCLUDED_PROFILES = 5
  CHECKOUT_PENDING_KEY = "checkout_pending"
  CHECKOUT_ATTEMPT_KEY = "checkout_attempt"
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
  validates :profile_limit, numericality: { only_integer: true, greater_than_or_equal_to: INCLUDED_PROFILES }, allow_nil: true

  def active_for_access?
    ACCESS_STATUSES.include?(status)
  end

  def can_start_checkout?
    !active_for_access? && (stripe_subscription_id.blank? || canceled? || incomplete_expired?)
  end

  def can_resume_checkout?
    incomplete? && checkout_attempt.present?
  end

  def stripe_linked?
    stripe_customer_id.present? || stripe_subscription_id.present?
  end

  def checkout_pending?
    metadata[CHECKOUT_PENDING_KEY] == true
  end

  def mark_checkout_pending
    self.metadata = metadata.merge(CHECKOUT_PENDING_KEY => true)
  end

  def clear_checkout_pending
    self.metadata = metadata.except(CHECKOUT_PENDING_KEY)
  end

  def checkout_attempt
    metadata[CHECKOUT_ATTEMPT_KEY]
  end

  def start_checkout_attempt(price_id:, quantity:)
    self.metadata = metadata.merge(CHECKOUT_ATTEMPT_KEY => {
      "token" => SecureRandom.uuid, "price_id" => price_id, "quantity" => quantity
    })
  end

  def record_checkout_session(session_id)
    self.metadata = metadata.merge(CHECKOUT_ATTEMPT_KEY => checkout_attempt.merge("session_id" => session_id))
  end

  def clear_checkout_attempt
    self.metadata = metadata.except(CHECKOUT_ATTEMPT_KEY)
  end
end
