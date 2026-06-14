# frozen_string_literal: true

module Agentic
  module Providers
    class Anthropic
      include Errors
      include LlmCallTelemetry

      ENDPOINTS = {
        chat: "https://api.anthropic.com/v1/messages"
      }.freeze

      PARSEABLE_TYPES = %w[tool_use text].freeze

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
        ENV["ANTHROPIC_API_KEY"].presence ||
          Rails.application.credentials.dig(:anthropic, :api_key).presence ||
          Rails.application.credentials.dig(:app, :anthropic_api_key).presence ||
          Rails.application.credentials[:anthropic_api_key].presence
      end

      def self.api_key_present?
        api_key.present?
      end

      def call
        request_body = payload.to_json
        request_timeout = requirements[:timeout] || 90

        @http_response = measure_api_call do
          connection::Request.execute(
            method: :post,
            url: endpoint_path,
            payload: request_body,
            headers: headers,
            timeout: request_timeout,
            read_timeout: request_timeout
          )
        end
        @raw_response = JSON.parse(@http_response)
      rescue RestClient::ExceptionWithResponse => e
        Rails.logger.error("[Anthropic] API error (#{e.http_code}): #{e.response&.body}")
        raise
      end

      def parse_response(raw_response)
        content_block = raw_response["content"].find { |block| PARSEABLE_TYPES.include?(block["type"]) }

        if content_block["type"] == "tool_use"
          content_block["input"].to_json
        else
          content_block["text"]
        end
      end

      private

      def provider_name
        "anthropic"
      end

      def endpoint_path
        ENDPOINTS.fetch(operation_type) do
          raise ConfigurationError, "#{self.class.name} does not support :#{operation_type}"
        end
      end

      def attributes
        {
          model: requirements[:model],
          system: requirements[:system],
          messages: [
            {
              role: "user",
              content: requirements[:prompt]
            }
          ]
        }
      end

      def headers
        {
          "Content-Type": "application/json",
          "x-api-key": self.class.api_key,
          "anthropic-version": "2023-06-01"
        }
      end

      def payload
        attributes = base_attributes.deep_dup
        attributes.merge!(policy_schema) if requirements[:response_format] == "structured_json"
        attributes.merge!(max_tokens) if requirements[:max_tokens]
        attributes.merge!(thinking) if requirements[:thinking]
        apply_effort!(attributes) if requirements[:effort]

        attributes
      end

      def policy_schema
        return runtime_schema if requirements.key?(:schema)

        raise ConfigurationError, "requirements[:schema_name] is required for structured JSON" if requirements[:schema_name].blank?

        JsonSchema.find_by!(name: "anthropic_#{requirements[:schema_name]}").schema
      end

      def runtime_schema
        schema = requirements[:schema]
        raise ConfigurationError, "requirements[:schema] is required when provided" if schema.blank?

        schema
      end

      def max_tokens
        { max_tokens: requirements[:max_tokens] }
      end

      def thinking
        { thinking: requirements[:thinking] }
      end

      def apply_effort!(attributes)
        config = attributes.delete("output_config") || {}
        config["effort"] = requirements[:effort]
        attributes["output_config"] = config
      end

      def token_usage
        {
          input_tokens: usage["input_tokens"],
          output_tokens: usage["output_tokens"],
          cached_input_tokens: usage["cache_read_input_tokens"],
          total_tokens: token_total(usage["input_tokens"], usage["output_tokens"])
        }
      end

      def raw_usage
        raw_response&.fetch("usage", {}) || {}
      end

      def usage
        raw_usage
      end
    end
  end
end
