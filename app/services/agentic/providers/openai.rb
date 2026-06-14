# frozen_string_literal: true

module Agentic
  module Providers
    class Openai
      include Errors
      include LlmCallTelemetry

      ENDPOINTS = {
        chat: "https://api.openai.com/v1/chat/completions",
        embeddings: "https://api.openai.com/v1/embeddings"
      }.freeze

      attr_reader :operation_type, :requirements, :base_attributes, :connection

      def initialize(connection:, operation_type:, requirements:)
        @connection = connection
        @operation_type = operation_type
        @requirements = requirements
        @base_attributes = attributes
      end

      def self.default_operation_type
        :chat
      end

      def self.api_key
        ENV["OPENAI_API_KEY"].presence ||
          Rails.application.credentials.dig(:openai, :api_key).presence ||
          Rails.application.credentials.dig(:open_ai, :api_key).presence ||
          Rails.application.credentials.dig(:app, :api_key).presence ||
          Rails.application.credentials[:api_key].presence
      end

      def self.api_key_present?
        api_key.present?
      end

      def call
        request_timeout = requirements[:timeout] || 90
        request_payload = payload.to_json

        @http_response = measure_api_call do
          connection::Request.execute(
            method: :post,
            url: endpoint_path,
            payload: request_payload,
            headers: headers,
            timeout: request_timeout,
            read_timeout: request_timeout
          )
        end
        @raw_response = JSON.parse(@http_response)
      end

      def parse_response(raw_response)
        return raw_response["data"] if operation_type == :embeddings

        raw_response["choices"][0]["message"]["content"]
      end

      private

      def provider_name
        "openai"
      end

      def endpoint_path
        ENDPOINTS.fetch(operation_type) do
          raise ConfigurationError, "#{self.class.name} does not support :#{operation_type}"
        end
      end

      def attributes
        return embedding_attributes if operation_type == :embeddings

        {
          model: requirements[:model],
          messages: [
            {
              role: "developer",
              content: requirements[:system]
            },
            {
              role: "user",
              content: requirements[:prompt]
            }
          ]
        }
      end

      def embedding_attributes
        {
          model: requirements[:model],
          input: requirements[:input],
          encoding_format: requirements[:encoding_format] || "float"
        }.tap do |attributes|
          attributes[:dimensions] = requirements[:dimensions] if requirements[:dimensions]
        end
      end

      def headers
        {
          "Content-Type": "application/json",
          Authorization: "Bearer #{self.class.api_key}"
        }
      end

      def payload
        attributes = base_attributes.deep_dup
        return attributes if operation_type == :embeddings

        attributes.merge!(policy_schema) if requirements[:response_format] == "structured_json"
        attributes.merge!(max_tokens) if requirements[:max_tokens]

        attributes
      end

      def policy_schema
        return runtime_schema if requirements.key?(:schema)

        raise ConfigurationError, "requirements[:schema_name] is required for structured JSON" if requirements[:schema_name].blank?

        JsonSchema.find_by!(name: "openai_#{requirements[:schema_name]}").schema
      end

      def runtime_schema
        schema = requirements[:schema]
        raise ConfigurationError, "requirements[:schema] is required when provided" if schema.blank?

        schema
      end

      def max_tokens
        { max_completion_tokens: requirements[:max_tokens] }
      end

      def token_usage
        {
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          cached_input_tokens: cached_input_tokens,
          total_tokens: usage["total_tokens"] || token_total(input_tokens, output_tokens)
        }
      end

      def raw_usage
        raw_response&.fetch("usage", {}) || {}
      end

      def input_tokens
        usage["prompt_tokens"]
      end

      def output_tokens
        usage["completion_tokens"]
      end

      def cached_input_tokens
        usage.dig("prompt_tokens_details", "cached_tokens")
      end

      def usage
        raw_usage
      end
    end
  end
end
