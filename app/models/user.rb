class User < ApplicationRecord
  attr_writer :account_name

  belongs_to :account
  has_many :documents, dependent: :restrict_with_error

  enum :role, {
    family_admin: "family_admin",
    profile_user: "profile_user",
    platform_admin: "platform_admin"
  }

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  before_validation :build_account_for_registration, on: :create

  def can_manage_family_unit?
    family_admin? || platform_admin?
  end

  def account_name
    @account_name.presence || name.presence || email.to_s.split("@").first.presence || "New Account"
  end

  private

    def build_account_for_registration
      self.account ||= Account.new(name: account_name)
    end
end
