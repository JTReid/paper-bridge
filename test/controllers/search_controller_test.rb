require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  class FakeConnection
    class << self
      attr_accessor :requests
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.requests << kwargs
        payload = JSON.parse(kwargs.fetch(:payload))

        return embedding_response(payload) if kwargs.fetch(:url).include?("/embeddings")
        return answer_response(payload) if kwargs.fetch(:url).include?("/chat/completions")

        raise "Unexpected search test request: #{kwargs.fetch(:url)}"
      end

      def self.embedding_response(payload)
        {
          data: [
            {
              object: "embedding",
              index: 0,
              embedding: query_vector
            }
          ],
          model: payload.fetch("model"),
          usage: {
            prompt_tokens: 6,
            total_tokens: 6
          }
        }.to_json
      end

      def self.answer_response(payload)
        {
          choices: [
            {
              message: {
                content: {
                  answer: "The indexed evidence says the page text is relevant to the question.",
                  citations: [
                    {
                      chunk_id: document_chunk_id(payload),
                      document_title: "Advance Directive",
                      page_number: 1,
                      quote: "Embedded page text"
                    }
                  ],
                  limitations: []
                }.to_json
              }
            }
          ],
          usage: {
            prompt_tokens: 20,
            completion_tokens: 18,
            total_tokens: 38
          }
        }.to_json
      end

      def self.query_vector
        Array.new(DocumentEmbedding::DIMENSIONS, 0.0).tap do |vector|
          vector[0] = 1.0
        end
      end

      def self.document_chunk_id(payload)
        payload.dig("messages", 1, "content").to_s[/chunk_id: (\d+)/, 1].to_i
      end
    end
  end

  setup do
    Rails.application.load_seed
    @original_connection = SearchController.llm_connection
    SearchController.llm_connection = FakeConnection
    FakeConnection.requests = []
  end

  teardown do
    SearchController.llm_connection = @original_connection
  end

  test "requires authentication" do
    get search_path

    assert_redirected_to new_user_session_path
  end

  test "renders empty state without creating a pipeline for blank query" do
    sign_in users(:family_admin)

    assert_no_difference -> { PipelineRun.count } do
      get search_path
    end

    assert_response :success
    assert_includes response.body, "Enter a search query"
    assert_empty FakeConnection.requests
  end

  test "searches account chunks through the search pipeline" do
    sign_in users(:family_admin)
    create_embedding!(document_chunks(:one), FakeConnection::Request.query_vector)

    assert_difference -> { PipelineRun.count }, 1 do
      get search_path(q: "embedded page")
    end

    pipeline_run = PipelineRun.order(:created_at).last

    assert_response :success
    assert_equal "completed", pipeline_run.state
    assert_includes response.body, "Advance Directive"
    assert_includes response.body, "Legal chunk 1"
    assert_includes response.body, "Embedded page text"
    assert_includes response.body, "The indexed evidence says the page text is relevant to the question."
    assert_includes response.body, "Similarity"
    assert_equal 2, FakeConnection.requests.count
    assert_equal "gpt-5.4-mini", JSON.parse(FakeConnection.requests.last.fetch(:payload)).fetch("model")
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "search_answer_synthesized" }
  end

  test "does not call answer synthesis when retrieval returns no chunks" do
    sign_in users(:family_admin)

    assert_difference -> { PipelineRun.count }, 1 do
      get search_path(q: "missing evidence")
    end

    pipeline_run = PipelineRun.order(:created_at).last

    assert_response :success
    assert_equal "completed", pipeline_run.state
    assert_includes response.body, "No matching chunks found."
    assert_equal 1, FakeConnection.requests.count
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "search_answer_skipped" }
  end

  private

    def create_embedding!(chunk, embedding)
      chunk.document_embeddings.create!(
        provider: DocumentEmbedding::PROVIDER,
        model: DocumentEmbedding::MODEL,
        dimensions: DocumentEmbedding::DIMENSIONS,
        distance_metric: DocumentEmbedding::DISTANCE_METRIC,
        embedding: embedding
      )
    end
end
