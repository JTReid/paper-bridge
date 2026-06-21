class CareTeamMembership < ApplicationRecord
  DOCUMENT_CATEGORY_PERMISSIONS = %w[
    educational
    medical
    therapy
    insurance
    general
  ].freeze

  ROLES = {
    teacher: "teacher",
    therapist: "therapist",
    doctor: "doctor",
    family_member: "family_member",
    advocate: "advocate",
    other: "other"
  }.freeze

  STATUSES = {
    invited: "invited",
    active: "active",
    revoked: "revoked"
  }.freeze

  belongs_to :account
  belongs_to :dependent
  belongs_to :user
  belongs_to :invited_by, class_name: "User"

  enum :role, ROLES
  enum :status, STATUSES

  before_validation :copy_user_identity
  before_validation :default_invited_at, on: :create
  before_validation :normalize_permissions

  validates :name, :email, :role, :status, presence: true
  validates :user_id, uniqueness: { scope: :dependent_id }
  validate :account_matches_dependent
  validate :inviter_can_manage_account

  def allowed_document_categories
    permissions.select { |_category, allowed| allowed }.keys
  end

  private

    def copy_user_identity
      self.email = user.email if email.blank? && user.present?
      self.name = user.name.presence || user.email if name.blank? && user.present?
    end

    def default_invited_at
      self.invited_at ||= Time.current
    end

    def normalize_permissions
      boolean = ActiveModel::Type::Boolean.new
      source = permissions || {}
      normalized = DOCUMENT_CATEGORY_PERMISSIONS.index_with do |category|
        value = if source.key?(category)
          source[category]
        elsif source.key?(category.to_sym)
          source[category.to_sym]
        end

        boolean.cast(value) || false
      end
      self.permissions = normalized
    end

    def account_matches_dependent
      return if account.blank? || dependent.blank? || account_id == dependent.account_id

      errors.add(:account, "must match the dependent")
    end

    def inviter_can_manage_account
      return if invited_by.blank? || account.blank? || invited_by.can_manage_account?(account)

      errors.add(:invited_by, "must be able to manage the account")
    end
end
