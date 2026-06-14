# frozen_string_literal: true

class Llm < ApplicationRecord
  validates :name, :provider_class, presence: true

  def provider_klass
    provider_class.constantize
  end
end
