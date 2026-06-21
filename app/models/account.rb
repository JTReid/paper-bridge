class Account < ApplicationRecord
  has_many :account_memberships, dependent: :destroy
  has_many :users, through: :account_memberships
  has_many :documents, dependent: :destroy
  has_many :document_pages, dependent: :destroy
  has_many :document_chunks, dependent: :destroy
  has_many :dependents, dependent: :destroy
  has_many :care_team_memberships, dependent: :destroy
  has_many :timeline_events, through: :document_chunks

  validates :name, presence: true
end
