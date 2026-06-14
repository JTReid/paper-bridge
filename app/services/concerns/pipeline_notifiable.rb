# frozen_string_literal: true

module PipelineNotifiable
  def step_complete
    raise NotImplementedError, "#{self.class.name} must implement #step_complete"
  end

  def step_started
    raise NotImplementedError, "#{self.class.name} must implement #step_started"
  end

  def pass_through_pipeline_response?
    false
  end
end
