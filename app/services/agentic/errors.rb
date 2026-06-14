# frozen_string_literal: true

module Agentic
  module Errors
    class Error < StandardError; end
    class ConfigurationError < Error; end
    class ExecutionError < Error; end
  end
end
