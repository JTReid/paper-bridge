# frozen_string_literal: true

class Prompt < ApplicationRecord
  belongs_to :agent_type

  scope :active, -> { where(is_active: true) }

  validates :system_directive, presence: true
end
