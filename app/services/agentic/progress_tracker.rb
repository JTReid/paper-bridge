# frozen_string_literal: true

module Agentic
  class ProgressTracker
    def initialize(user_id, stream_name: "agentic_jobs")
      @user_id = user_id
      @stream_name = stream_name
      @current_step = 0
    end

    def start_with(steps:)
      @total_steps = steps
      broadcast(action: "started", current_step: @current_step, total_steps: @total_steps)
    end

    def step_started(step_name)
      broadcast(action: "step_started", step_name: step_name, current_step: @current_step, total_steps: @total_steps)
    end

    def step_completed(step_name)
      @current_step += 1
      broadcast(action: "step_completed", step_name: step_name, current_step: @current_step, total_steps: @total_steps)
    end

    private

    def broadcast(payload)
      return if @user_id.blank?

      ActionCable.server.broadcast("#{@stream_name}_#{@user_id}", payload)
    end
  end
end
