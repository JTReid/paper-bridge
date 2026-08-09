# frozen_string_literal: true

module Agentic
  module Errors
    class Error < StandardError; end
    class ConfigurationError < Error; end

    class ExecutionError < Error
      def retryable?
        true
      end
    end

    class NonRetryableExecutionError < ExecutionError
      def retryable?
        false
      end
    end
  end
end
