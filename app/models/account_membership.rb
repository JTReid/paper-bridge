class AccountMembership < ApplicationRecord
  ROLES = {
    admin: "admin",
    member: "member"
  }.freeze

  belongs_to :account
  belongs_to :user

  enum :role, ROLES

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :account_id }
end
