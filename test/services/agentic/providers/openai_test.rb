# frozen_string_literal: true

require "test_helper"

class Agentic::Providers::OpenaiTest < ActiveSupport::TestCase
  class FakeConnection
    class << self
      attr_accessor :last_request
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.last_request = kwargs
        {
          choices: [
            {
              message: {
                content: "{\"status\":\"OK\"}"
              }
            }
          ],
          usage: {
            prompt_tokens: 10,
            completion_tokens: 4,
            total_tokens: 14,
            prompt_tokens_details: {
              cached_tokens: 3
            }
          }
        }.to_json
      end
    end
  end

  test "builds structured JSON chat requests and parses responses" do
    provider = Agentic::Providers::Openai.new(
      connection: FakeConnection,
      operation_type: :chat,
      requirements: {
        model: "gpt-5.4-nano",
        system: "System",
        prompt: "Prompt",
        max_tokens: 20,
        response_format: "structured_json",
        schema: {
          response_format: {
            type: "json_schema",
            json_schema: {
              name: "smoke",
              schema: {
                type: "object"
              }
            }
          }
        }
      }
    )

    raw_response = provider.call
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))

    assert_equal "https://api.openai.com/v1/chat/completions", FakeConnection.last_request.fetch(:url)
    assert_equal "gpt-5.4-nano", payload.fetch("model")
    assert_equal "json_schema", payload.dig("response_format", "type")
    assert_equal 20, payload.fetch("max_completion_tokens")
    assert_equal "{\"status\":\"OK\"}", provider.parse_response(raw_response)
    assert_equal 10, provider.llm_metadata.fetch(:input_tokens)
    assert_equal 3, provider.llm_metadata.fetch(:cached_input_tokens)
    assert_equal 4, provider.llm_metadata.fetch(:output_tokens)
  end
end
