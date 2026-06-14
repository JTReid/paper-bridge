# frozen_string_literal: true

class PipelineLog < ApplicationRecord
  belongs_to :pipeline_run
end
