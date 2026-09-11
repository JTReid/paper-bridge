class CareTeamMembership < ApplicationRecord
  # Retain historical invitation data in storage without using it for contacts.
  self.ignored_columns += %w[user_id status permissions invited_at accepted_at revoked_at]

  ROLES = {
    teacher: "teacher",
    therapist: "therapist",
    doctor: "doctor",
    family_member: "family_member",
    advocate: "advocate",
    other: "other"
  }.freeze

  belongs_to :account
  belongs_to :dependent
  belongs_to :invited_by, class_name: "User"

  enum :role, ROLES

  normalizes :name, with: ->(value) { value.strip }
  normalizes :email, with: ->(value) { value.strip.downcase }
  normalizes :phone_number, with: ->(value) { value.strip.presence }

  validates :name, :email, :role, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :email, uniqueness: { scope: :dependent_id, case_sensitive: false }
  validate :account_matches_dependent
  validate :inviter_can_manage_account

  private

    def account_matches_dependent
      return if account.blank? || dependent.blank? || account_id == dependent.account_id

      errors.add(:account, "must match the dependent")
    end

    def inviter_can_manage_account
      return if invited_by.blank? || account.blank? || invited_by.can_manage_account?(account)

      errors.add(:invited_by, "must be able to manage the account")
    end
end
