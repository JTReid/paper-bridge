class Account < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :documents, dependent: :destroy

  validates :name, presence: true
end
