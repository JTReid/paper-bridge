class Appointment < ApplicationRecord
  belongs_to :dependent

  has_one :account, through: :dependent

  validates :scheduled_at, :description, presence: true
end
