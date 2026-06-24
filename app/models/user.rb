class User < ApplicationRecord
  has_many :account_memberships, dependent: :destroy
  has_many :accounts, through: :account_memberships
  has_many :care_team_memberships, dependent: :destroy
  has_many :documents, dependent: :restrict_with_error
  has_many :share_events, foreign_key: :sender_id, inverse_of: :sender, dependent: :restrict_with_error

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  after_create :create_registration_account_membership, if: :registration_account_requested?

  def account_name=(value)
    @account_name = value
    @registration_account_requested = true
  end

  def account
    accounts.order("account_memberships.created_at ASC").first
  end

  def can_manage_family_unit?
    account_memberships.admin.exists?
  end

  def can_manage_account?(account)
    account_memberships.admin.exists?(account: account)
  end

  def account_name
    @account_name.presence || name.presence || email.to_s.split("@").first.presence || "New Account"
  end

  private

    def account_name_requested?
      @registration_account_requested
    end

    def registration_account_requested?
      @registration_account_requested
    end

    def create_registration_account_membership
      return if account_memberships.exists?

      account = Account.create!(name: account_name)
      account_memberships.create!(account: account, role: :admin)
    end
end
