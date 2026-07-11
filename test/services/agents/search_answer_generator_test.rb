require "test_helper"

class Agents::SearchAnswerGeneratorTest < ActiveSupport::TestCase
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
    request_prompt = JSON.parse(FakeConnection.last_request.fetch(:payload)).dig("messages", 1, "content")

    assert_includes request_prompt, "Source 1"
    assert_not_includes request_prompt, "chunk_id: #{chunk.id}"
    assert_not_includes request_prompt, "document_id: #{chunk.document.id}"
    assert_equal "The document supports this answer [1].", response[:answer]
    assert_equal chunk.document.title, response.dig(:citations, 0, :document_title)
    assert_equal chunk.document_page.page_number, response.dig(:citations, 0, :page_number)
    assert_equal chunk.content, response.dig(:citations, 0, :quote)
    assert_not response.fetch(:citations).first.key?(:chunk_id)
  end
end
