class Dependent < ApplicationRecord
  AVATAR_CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  AVATAR_MAX_SIZE = 5.megabytes

  belongs_to :account

  has_one_attached :avatar do |attachable|
    attachable.variant :display, resize_to_fill: [ 256, 256 ]
  end
  has_many :documents, dependent: :restrict_with_error
  has_many :care_team_memberships, dependent: :destroy
  has_many :care_team_users, through: :care_team_memberships, source: :user

  validates :name, presence: true
  validate :acceptable_avatar

  private

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
