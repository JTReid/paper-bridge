# frozen_string_literal: true

module Agentic
  class NullProgressTracker
    def start_with(steps:)
    end

    def step_started(step_name)
    end

    def step_completed(step_name)
    end
  end
end
