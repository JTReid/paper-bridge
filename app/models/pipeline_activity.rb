# frozen_string_literal: true

class PipelineActivity < ApplicationRecord
  belongs_to :pipeline_run
end
