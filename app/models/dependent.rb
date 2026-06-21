class Dependent < ApplicationRecord
  belongs_to :account

  has_many :documents, dependent: :restrict_with_error
  has_many :care_team_memberships, dependent: :destroy
  has_many :care_team_users, through: :care_team_memberships, source: :user

  validates :name, presence: true
end
