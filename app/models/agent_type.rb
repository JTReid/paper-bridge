# frozen_string_literal: true

class AgentType < ApplicationRecord
  belongs_to :llm
  has_many :prompts, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true
end
