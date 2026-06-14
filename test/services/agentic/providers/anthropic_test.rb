# frozen_string_literal: true

require "test_helper"

class Agentic::Providers::AnthropicTest < ActiveSupport::TestCase
  class FakeConnection
    class << self
      attr_accessor :last_request
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.last_request = kwargs
        {
          content: [
            {
              type: "tool_use",
              input: {
                status: "OK"
              }
            }
          ],
          usage: {
            input_tokens: 8,
            output_tokens: 3,
            cache_read_input_tokens: 2
          }
        }.to_json
      end
    end
  end

  test "builds structured tool requests and parses tool responses" do
    provider = Agentic::Providers::Anthropic.new(
      connection: FakeConnection,
      operation_type: :chat,
      requirements: {
        model: "claude-example",
        system: "System",
        prompt: "Prompt",
        max_tokens: 20,
        response_format: "structured_json",
        schema: {
          tools: [
            {
              name: "smoke",
              input_schema: {
                type: "object"
              }
            }
          ],
          tool_choice: {
            type: "tool",
            name: "smoke"
          }
        }
      }
    )

    raw_response = provider.call
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))

    assert_equal "https://api.anthropic.com/v1/messages", FakeConnection.last_request.fetch(:url)
    assert_equal "claude-example", payload.fetch("model")
    assert_equal "smoke", payload.fetch("tools").first.fetch("name")
    assert_equal "{\"status\":\"OK\"}", provider.parse_response(raw_response)
    assert_equal 8, provider.llm_metadata.fetch(:input_tokens)
    assert_equal 2, provider.llm_metadata.fetch(:cached_input_tokens)
    assert_equal 3, provider.llm_metadata.fetch(:output_tokens)
  end
end
