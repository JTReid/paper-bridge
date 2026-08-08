require "test_helper"

class Agents::SearchAnswerGeneratorTest < ActiveSupport::TestCase
  class FakeStreamingConnection
    class << self
      attr_accessor :chunks, :last_request
    end

    class Response
      def code = "200"

      def read_body
        FakeStreamingConnection.chunks.each { |chunk| yield chunk }
      end
    end

    class Request
      def self.execute(**kwargs)
        FakeStreamingConnection.last_request = kwargs
        kwargs.fetch(:block_response).call(Response.new)
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
        {
          choices: [
            {
              message: {
                content: {
                  answer: "The document supports this answer [1].",
                  citations: [
                    {
                      chunk_id: 1,
                      document_title: "Model-provided title",
                      page_number: 99,
                      quote: "Model-provided quote"
                    }
                  ],
                  limitations: []
                }.to_json
              }
            }
          ],
          usage: {
            prompt_tokens: 10,
            completion_tokens: 5,
            total_tokens: 15
          }
        }.to_json
      end
    end
  end

  setup do
    Rails.application.load_seed
    FakeConnection.last_request = nil
  end

  test "uses ephemeral source numbers and canonicalizes the model citations" do
    chunk = document_chunks(:one)
    result = Documents::VectorSearch::Result.new(
      chunk: chunk,
      document: chunk.document,
      page: chunk.document_page,
      similarity: 0.9
    )
    pipeline_run = PipelineRun.create!(subject: chunk.document.account, user: users(:family_admin))
    agent = Agents::SearchAnswerGenerator.new(
      connection: FakeConnection,
      context: {
        pipeline_run_gid: pipeline_run.to_global_id.to_s,
        query: "What does the document say?",
        search_results: [ result ]
      }
    )

    response = agent.execute
    request_payload = JSON.parse(FakeConnection.last_request.fetch(:payload))
    request_prompt = request_payload.dig("messages", 1, "content")

    assert_includes request_prompt, "Source 1"
    assert_not_includes request_prompt, "chunk_id: #{chunk.id}"
    assert_not_includes request_prompt, "document_id: #{chunk.document.id}"
    assert_equal Agents::SearchAnswerGenerator::MAX_COMPLETION_TOKENS,
      request_payload.fetch("max_completion_tokens")
    assert_equal "The document supports this answer [1].", response[:answer]
    assert_equal chunk.document.title, response.dig(:citations, 0, :document_title)
    assert_equal chunk.document_page.page_number, response.dig(:citations, 0, :page_number)
    assert_equal chunk.content, response.dig(:citations, 0, :quote)
    assert_not response.fetch(:citations).first.key?(:chunk_id)
  end

  test "streams progressive answer text before canonicalizing the final citations" do
    chunk = document_chunks(:one)
    result = Documents::VectorSearch::Result.new(
      chunk: chunk,
      document: chunk.document,
      page: chunk.document_page,
      similarity: 0.9
    )
    pipeline_run = PipelineRun.create!(subject: chunk.document.account, user: users(:family_admin))
    drafts = []
    content_parts = [
      '{"answer":"The record ',
      'supports this answer [1].","citations":',
      '[{"chunk_id":1,"document_title":"Wrong","page_number":99,"quote":"Wrong"}],"limitations":[]}'
    ]
    events = content_parts.each_with_index.map do |content, index|
      {
        choices: [
          {
            delta: { content: content },
            finish_reason: index == content_parts.length - 1 ? "stop" : nil
          }
        ],
        usage: nil
      }
    end
    events << { choices: [], usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 } }
    body = events.map { |event| "data: #{event.to_json}\n\n" }.join + "data: [DONE]\n\n"
    FakeStreamingConnection.chunks = [ body.first(37), body[37, 51], body[88..] ]
    agent = Agents::SearchAnswerGenerator.new(
      connection: FakeStreamingConnection,
      context: {
        pipeline_run_gid: pipeline_run.to_global_id.to_s,
        query: "What does the document say?",
        search_results: [ result ],
        answer_stream_callback: ->(draft) { drafts << draft }
      }
    )

    response = agent.execute
    request_payload = JSON.parse(FakeStreamingConnection.last_request.fetch(:payload))

    assert_equal true, request_payload.fetch("stream")
    assert_equal "answer", request_payload.dig("response_format", "json_schema", "schema", "properties").keys.first
    assert_equal "The record ", drafts.first
    assert_equal "The record supports this answer [1].", drafts.last
    assert_equal "The record supports this answer [1].", response[:answer]
    assert_equal chunk.document.title, response.dig(:citations, 0, :document_title)
    assert_equal chunk.document_page.page_number, response.dig(:citations, 0, :page_number)
    assert_equal chunk.content, response.dig(:citations, 0, :quote)
  end
end
