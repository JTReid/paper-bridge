# frozen_string_literal: true

module Agentic
  module Providers
    class Openai
      include Errors
      include LlmCallTelemetry

      class HttpError < ExecutionError
        attr_reader :http_code

        def initialize(http_code, message: nil)
          @http_code = http_code
          super(message || "OpenAI request failed with HTTP #{http_code}")
        end

        def retryable?
          http_code.in?([ 408, 409, 429 ]) || http_code.between?(500, 599)
        end
      end

      class StreamingHttpError < HttpError
        def initialize(http_code)
          super(http_code, message: "OpenAI streaming request failed with HTTP #{http_code}")
        end
      end

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
        return call_stream if streaming?

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
      rescue RestClient::ExceptionWithResponse => e
        raise HttpError.new(e.http_code)
      end

      def parse_response(raw_response)
        return raw_response["data"] if operation_type == :embeddings

        raw_response["choices"][0]["message"]["content"]
      end

      private

      def call_stream
        request_timeout = requirements[:timeout] || 90
        request_payload = payload.to_json
        reset_stream_state
        parser = SseParser.new { |event| process_stream_event(event) }

        @http_response = measure_api_call do
          connection::Request.execute(
            method: :post,
            url: endpoint_path,
            payload: request_payload,
            headers: headers,
            timeout: request_timeout,
            read_timeout: request_timeout,
            block_response: proc { |response| consume_stream_response(response, parser) }
          )
        end

        @raw_response = synthetic_stream_response
        validate_completed_stream!
        @raw_response
      end

      def consume_stream_response(response, parser)
        status = response.code.to_i

        unless status.between?(200, 299)
          response.read_body { |_chunk| }
          raise StreamingHttpError.new(status)
        end

        response.read_body { |chunk| parser.feed(chunk) }
        parser.finish
      end

      def process_stream_event(event)
        if event == "[DONE]"
          @stream_done = true
          return
        end

        payload = JSON.parse(event)
        raise ExecutionError, "OpenAI streaming API returned an error" if payload["error"]

        @stream_usage = payload["usage"] if payload["usage"].is_a?(Hash)
        choice = Array(payload["choices"]).first
        return unless choice

        delta = choice["delta"] || {}
        append_stream_content(delta["content"])
        @stream_refusal << delta["refusal"] if delta["refusal"].is_a?(String)
        @stream_finish_reason = choice["finish_reason"] if choice["finish_reason"].present?
      rescue JSON::ParserError
        raise ExecutionError, "OpenAI returned a malformed streaming event"
      end

      def append_stream_content(content_delta)
        return unless content_delta.is_a?(String)

        @stream_content << content_delta
        deliver_content_delta(content_delta)
      end

      def deliver_content_delta(content_delta)
        return unless @content_delta_callback

        measure_stream_callback do
          @content_delta_callback.call(content_delta)
        end
      rescue StandardError => e
        Rails.logger.warn("openai_stream_callback_failed error_class=#{e.class.name}")
        @content_delta_callback = nil
      end

      def validate_completed_stream!
        raise ExecutionError, "OpenAI stream ended before completion" unless @stream_done
        raise NonRetryableExecutionError, "OpenAI refused the streaming request" if @stream_refusal.present?

        case @stream_finish_reason
        when "stop"
          nil
        when "length"
          raise NonRetryableExecutionError, "OpenAI stream reached its output limit"
        when "content_filter"
          raise NonRetryableExecutionError, "OpenAI stream was stopped by a content filter"
        else
          raise ExecutionError, "OpenAI stream ended without a successful finish reason"
        end
      end

      def synthetic_stream_response
        {
          "choices" => [
            {
              "message" => {
                "content" => @stream_content,
                "refusal" => @stream_refusal.presence
              },
              "finish_reason" => @stream_finish_reason
            }
          ],
          "usage" => @stream_usage
        }
      end

      def reset_stream_state
        @content_delta_callback = requirements[:on_content_delta]
        @stream_content = +""
        @stream_refusal = +""
        @stream_usage = nil
        @stream_finish_reason = nil
        @stream_done = false
      end

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
        attributes.merge!(stream: true, stream_options: { include_usage: true }) if streaming?

        attributes
      end

      def streaming?
        operation_type == :chat && requirements[:on_content_delta].respond_to?(:call)
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
        raw_response&.fetch("usage", nil) || @stream_usage || {}
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
