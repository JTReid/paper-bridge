# frozen_string_literal: true

class JsonSchema < ApplicationRecord
  validates :name, :schema, presence: true
end
