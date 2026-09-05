class Dependent < ApplicationRecord
  AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  AVATAR_MAX_SIZE = 5.megabytes

  belongs_to :account

  has_one_attached :avatar do |attachable|
    attachable.variant :display, resize_to_fill: [ 256, 256 ]
  end
  has_many :documents, dependent: :restrict_with_error
  has_many :ai_assistant_queries, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :care_team_memberships, dependent: :destroy
  has_many :care_team_users, through: :care_team_memberships, source: :user

  normalizes :first_name, :last_name, with: ->(value) { value.strip }

  validates :first_name, presence: true
  validate :acceptable_avatar
  validate :profile_allowance_available, on: :create

  before_create :enforce_profile_allowance

  def name
    return legacy_name.to_s if first_name.nil?

    [ first_name, last_name ].compact_blank.join(" ")
  end

  private

    def profile_allowance_available(account_to_check = account)
      return true unless account_to_check&.profile_limit_reached?

      errors.add(:base, "Your managed profile allowance is full. Increase it in Billing before adding another profile.")
      false
    end

    def enforce_profile_allowance
      return unless account_id

      # Save's transaction holds this account lock through the profile INSERT.
      # The fresh account and uncached reads also see allowance changes made by
      # webhooks or profile creations that completed while this save waited.
      Account.uncached do
        locked_account = Account.lock.find(account_id)
        throw :abort unless profile_allowance_available(locked_account)
      end
    end

    def acceptable_avatar
      return unless avatar.attached?

      unless avatar.content_type.in?(AVATAR_CONTENT_TYPES)
        errors.add(:avatar, "must be a JPEG, PNG, or WebP image")
      end

      if avatar.byte_size > AVATAR_MAX_SIZE
        errors.add(:avatar, "must be smaller than 5 MB")
      end
    end
end
