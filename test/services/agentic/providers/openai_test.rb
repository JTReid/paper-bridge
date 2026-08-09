# frozen_string_literal: true

require "test_helper"

class Agentic::Providers::OpenaiTest < ActiveSupport::TestCase
  class FakeStreamResponse
    attr_reader :code

    def initialize(code:, chunks:)
      @code = code.to_s
      @chunks = chunks
    end

    def read_body
      @chunks.each { |chunk| yield chunk }
    end
  end

  class InterruptedStreamResponse
    attr_reader :code

    def initialize(code:, chunks:)
      @code = code.to_s
      @chunks = chunks
    end

    def read_body
      @chunks.each { |chunk| yield chunk }
      raise IOError, "connection closed"
    end
  end

  class StreamingConnection
    class << self
      attr_accessor :last_request, :response
    end

    class Request
      def self.execute(**kwargs)
        StreamingConnection.last_request = kwargs
        kwargs.fetch(:block_response).call(StreamingConnection.response)
      end
    end
  end

  class FakeConnection
    class << self
      attr_accessor :last_request
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.last_request = kwargs
        return embeddings_response if kwargs.fetch(:url).include?("/embeddings")

        chat_response
      end

      def self.chat_response
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

      def self.embeddings_response
        {
          data: [
            {
              object: "embedding",
              index: 0,
              embedding: [ 0.1, 0.2, 0.3 ]
            }
          ],
          model: "text-embedding-3-large",
          usage: {
            prompt_tokens: 8,
            total_tokens: 8
          }
        }.to_json
      end
    end
  end

  class BufferedHttpFailureConnection
    class Request
      def self.execute(**)
        response = Struct.new(:code, :body).new(400, "private provider detail")
        raise RestClient::BadRequest.new(response)
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

  test "builds embedding requests and parses embedding rows" do
    provider = Agentic::Providers::Openai.new(
      connection: FakeConnection,
      operation_type: :embeddings,
      requirements: {
        model: "text-embedding-3-large",
        input: [ "chunk text" ],
        encoding_format: "float"
      }
    )

    raw_response = provider.call
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))

    assert_equal "https://api.openai.com/v1/embeddings", FakeConnection.last_request.fetch(:url)
    assert_equal "text-embedding-3-large", payload.fetch("model")
    assert_equal [ "chunk text" ], payload.fetch("input")
    assert_equal "float", payload.fetch("encoding_format")
    assert_equal [ 0.1, 0.2, 0.3 ], provider.parse_response(raw_response).first.fetch("embedding")
    assert_equal 8, provider.llm_metadata.fetch(:input_tokens)
    assert_nil provider.llm_metadata.fetch(:output_tokens)
  end

  test "classifies buffered HTTP client failures without exposing response bodies" do
    provider = Agentic::Providers::Openai.new(
      connection: BufferedHttpFailureConnection,
      operation_type: :embeddings,
      requirements: {
        model: "text-embedding-3-large",
        input: [ "query" ],
        encoding_format: "float"
      }
    )

    error = assert_raises(Agentic::Providers::Openai::HttpError) { provider.call }

    assert_equal 400, error.http_code
    assert_not_predicate error, :retryable?
    assert_equal "OpenAI request failed with HTTP 400", error.message
    assert_not_includes error.message, "private provider detail"
  end

  test "streams chat deltas and rebuilds a normal response with final usage" do
    content = '{"answer":"A streamed answer.","citations":[],"limitations":[]}'
    stream_body = sse_body(
      stream_chunk(content.first(23)),
      stream_chunk(content[23..]),
      stream_chunk(nil, finish_reason: "stop"),
      {
        choices: [],
        usage: {
          prompt_tokens: 12,
          completion_tokens: 8,
          total_tokens: 20,
          prompt_tokens_details: { cached_tokens: 4 }
        }
      },
      "[DONE]"
    )
    StreamingConnection.response = FakeStreamResponse.new(
      code: 200,
      chunks: [ stream_body.first(31), stream_body[31, 17], stream_body[48..] ]
    )
    deltas = []
    provider = streaming_provider(->(delta) { deltas << delta })

    raw_response = provider.call
    request_payload = JSON.parse(StreamingConnection.last_request.fetch(:payload))

    assert_equal true, request_payload.fetch("stream")
    assert_equal true, request_payload.dig("stream_options", "include_usage")
    assert_equal "json_schema", request_payload.dig("response_format", "type")
    assert_equal 50_000, request_payload.fetch("max_completion_tokens")
    assert_equal content, deltas.join
    assert_equal content, provider.parse_response(raw_response)
    assert_equal 12, provider.llm_metadata.fetch(:input_tokens)
    assert_equal 4, provider.llm_metadata.fetch(:cached_input_tokens)
    assert_equal 8, provider.llm_metadata.fetch(:output_tokens)
  end

  test "reports synchronous draft delivery time without changing request wall time" do
    content = '{"answer":"Draft","citations":[],"limitations":[]}'
    StreamingConnection.response = FakeStreamResponse.new(
      code: 200,
      chunks: [ sse_body(stream_chunk(content, finish_reason: "stop"), "[DONE]") ]
    )
    provider = streaming_provider(->(_delta) { })
    clock_values = [ 0.0, 2.0, 7.0, 10.0 ]
    provider.define_singleton_method(:monotonic_time) { clock_values.shift }

    provider.call

    metadata = provider.llm_metadata
    assert_equal 10_000, metadata.fetch(:elapsed_ms)
    assert_equal 5_000, metadata.fetch(:stream_callback_elapsed_ms)
    assert_not metadata.key?(:provider_elapsed_ms)
  end

  test "rejects streams that end without the done event" do
    StreamingConnection.response = FakeStreamResponse.new(
      code: 200,
      chunks: [ sse_body(stream_chunk("{}", finish_reason: "stop")) ]
    )

    error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end

    assert_equal "OpenAI stream ended before completion", error.message
  end

  test "rejects output-limit and non-success responses without exposing response bodies" do
    StreamingConnection.response = FakeStreamResponse.new(
      code: 200,
      chunks: [
        sse_body(
          stream_chunk("{", finish_reason: "length"),
          {
            choices: [],
            usage: {
              prompt_tokens: 7,
              completion_tokens: 3,
              total_tokens: 10,
              prompt_tokens_details: { cached_tokens: 2 }
            }
          },
          "[DONE]"
        )
      ]
    )
    length_provider = streaming_provider(->(_delta) { })

    length_error = assert_raises(Agentic::Errors::ExecutionError) do
      length_provider.call
    end
    assert_equal "OpenAI stream reached its output limit", length_error.message
    assert_instance_of Agentic::Errors::NonRetryableExecutionError, length_error
    assert_not_predicate length_error, :retryable?
    assert_equal 7, length_provider.failure_metadata(length_error).fetch(:input_tokens)
    assert_equal 2, length_provider.failure_metadata(length_error).fetch(:cached_input_tokens)
    assert_equal 3, length_provider.failure_metadata(length_error).fetch(:output_tokens)

    StreamingConnection.response = FakeStreamResponse.new(
      code: 200,
      chunks: [ sse_body(stream_chunk(nil, finish_reason: "content_filter"), "[DONE]") ]
    )
    content_filter_error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end
    assert_equal "OpenAI stream was stopped by a content filter", content_filter_error.message
    assert_not_predicate content_filter_error, :retryable?

    StreamingConnection.response = FakeStreamResponse.new(
      code: 429,
      chunks: [ '{"error":{"message":"private provider detail"}}' ]
    )

    http_error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end
    assert_equal "OpenAI streaming request failed with HTTP 429", http_error.message
    assert_equal 429, http_error.http_code
    assert_predicate http_error, :retryable?
    assert_not_includes http_error.message, "private provider detail"

    StreamingConnection.response = FakeStreamResponse.new(code: 400, chunks: [ "bad request" ])
    client_error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end
    assert_equal 400, client_error.http_code
    assert_not_predicate client_error, :retryable?

    StreamingConnection.response = FakeStreamResponse.new(code: 408, chunks: [ "timeout" ])
    timeout_error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end
    assert_equal 408, timeout_error.http_code
    assert_predicate timeout_error, :retryable?

    StreamingConnection.response = FakeStreamResponse.new(code: 409, chunks: [ "conflict" ])
    conflict_error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end
    assert_equal 409, conflict_error.http_code
    assert_predicate conflict_error, :retryable?

    StreamingConnection.response = FakeStreamResponse.new(code: 503, chunks: [ "unavailable" ])
    server_error = assert_raises(Agentic::Errors::ExecutionError) do
      streaming_provider(->(_delta) { }).call
    end
    assert_equal 503, server_error.http_code
    assert_predicate server_error, :retryable?
  end

  test "keeps received usage when a stream disconnects and leaves missing usage unknown" do
    usage_event = {
      choices: [],
      usage: {
        prompt_tokens: 9,
        completion_tokens: 4,
        total_tokens: 13,
        prompt_tokens_details: { cached_tokens: 2 }
      }
    }
    StreamingConnection.response = InterruptedStreamResponse.new(
      code: 200,
      chunks: [ sse_body(usage_event) ]
    )
    provider = streaming_provider(->(_delta) { })

    error = assert_raises(IOError) { provider.call }
    metadata = provider.failure_metadata(error)

    assert_equal 9, metadata.fetch(:input_tokens)
    assert_equal 2, metadata.fetch(:cached_input_tokens)
    assert_equal 4, metadata.fetch(:output_tokens)
    assert_equal usage_event.fetch(:usage).deep_stringify_keys, metadata.fetch(:raw_usage)

    StreamingConnection.response = InterruptedStreamResponse.new(code: 200, chunks: [])
    provider_without_usage = streaming_provider(->(_delta) { })

    missing_usage_error = assert_raises(IOError) { provider_without_usage.call }
    missing_usage_metadata = provider_without_usage.failure_metadata(missing_usage_error)

    assert_nil missing_usage_metadata.fetch(:input_tokens)
    assert_nil missing_usage_metadata.fetch(:cached_input_tokens)
    assert_nil missing_usage_metadata.fetch(:output_tokens)
    assert_empty missing_usage_metadata.fetch(:raw_usage)
  end

  test "a draft callback failure does not abort the paid stream" do
    content = '{"answer":"Still completes.","citations":[],"limitations":[]}'
    StreamingConnection.response = FakeStreamResponse.new(
      code: 200,
      chunks: [
        sse_body(
          stream_chunk(content.first(20)),
          stream_chunk(content[20..], finish_reason: "stop"),
          "[DONE]"
        )
      ]
    )
    callback_count = 0
    provider = streaming_provider(lambda do |_delta|
      callback_count += 1
      raise "Cable is unavailable"
    end)

    raw_response = provider.call

    assert_equal 1, callback_count
    assert_equal content, provider.parse_response(raw_response)
  end

  test "rejects malformed, error, and refusal events" do
    failing_bodies = [
      [ "data: {not-json}\n\n", "OpenAI returned a malformed streaming event" ],
      [ sse_body({ error: { message: "private detail" } }), "OpenAI streaming API returned an error" ],
      [
        sse_body(
          { choices: [ { delta: { refusal: "Cannot answer" }, finish_reason: "stop" } ] },
          "[DONE]"
        ),
        "OpenAI refused the streaming request"
      ]
    ]

    failing_bodies.each do |body, expected_message|
      StreamingConnection.response = FakeStreamResponse.new(code: 200, chunks: [ body ])

      error = assert_raises(Agentic::Errors::ExecutionError) do
        streaming_provider(->(_delta) { }).call
      end

      assert_equal expected_message, error.message
      assert_not_includes error.message, "private detail"
      assert_not_predicate error, :retryable? if expected_message == "OpenAI refused the streaming request"
    end
  end

  private

    def streaming_provider(callback)
      Agentic::Providers::Openai.new(
        connection: StreamingConnection,
        operation_type: :chat,
        requirements: {
          model: "gpt-5.6",
          system: "System",
          prompt: "Prompt",
          max_tokens: 50_000,
          response_format: "structured_json",
          schema: {
            response_format: {
              type: "json_schema",
              json_schema: {
                name: "search_answer",
                strict: true,
                schema: {
                  type: "object",
                  properties: {
                    answer: { type: "string" },
                    citations: { type: "array" },
                    limitations: { type: "array" }
                  }
                }
              }
            }
          },
          on_content_delta: callback
        }
      )
    end

    def stream_chunk(content, finish_reason: nil)
      {
        choices: [
          {
            delta: content.nil? ? {} : { content: content },
            finish_reason: finish_reason
          }
        ],
        usage: nil
      }
    end

    def sse_body(*events)
      events.map do |event|
        data = event.is_a?(String) ? event : event.to_json
        "data: #{data}\n\n"
      end.join
    end
end
