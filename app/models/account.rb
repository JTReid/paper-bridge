class Account < ApplicationRecord
  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :documents, dependent: :destroy
  has_many :document_pages, dependent: :destroy
  has_many :document_chunks, dependent: :destroy
  has_many :dependents, dependent: :destroy
  has_many :appointments, through: :dependents
  has_many :care_team_memberships, dependent: :destroy
  has_many :ai_assistant_queries, dependent: :destroy
  has_many :meeting_preps, dependent: :destroy
  has_many :saved_answers, dependent: :destroy
  has_many :share_events, dependent: :destroy
  has_many :timeline_events, through: :document_chunks
  has_one :billing_subscription, dependent: :destroy

  SIGNUP_LIMIT_REACHED_MESSAGE = "Maximum accounts reached. Contact an admin for instructions.".freeze

  validates :name, presence: true

  # NEW_ACCOUNTS_NON_BILLABLE=true makes accounts created at signup non-billable.
  # Only an explicit true value enables it, and it never changes existing accounts.
  def self.new_accounts_non_billable?
    ENV["NEW_ACCOUNTS_NON_BILLABLE"].to_s.casecmp?("true")
  end

  # MAX_ACCOUNTS caps the total number of accounts signup may create. Unset or
  # not a whole number means no cap; accounts created in the console are not
  # blocked.
  def self.signup_limit
    limit = Integer(ENV["MAX_ACCOUNTS"].to_s, exception: false)
    limit if limit && limit >= 0
  end

  def self.signup_limit_reached?
    limit = signup_limit
    limit.present? && count >= limit
  end

  def product_access?
    non_billable? || subscription_active?
  end

  def subscription_active?
    billing_subscription&.active_for_access? || false
  end

  def stripe_customer_id
    billing_subscription&.stripe_customer_id
  end

  def profile_limit
    return if non_billable?

    billing_subscription&.profile_limit
  end

  def profile_limit_reached?
    limit = profile_limit
    limit.present? && dependents.count >= limit
  end
end
