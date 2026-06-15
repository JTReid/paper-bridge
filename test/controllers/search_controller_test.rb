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

        raise "Unexpected search test request: #{kwargs.fetch(:url)}" unless kwargs.fetch(:url).include?("/embeddings")

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

      def self.query_vector
        Array.new(DocumentEmbedding::DIMENSIONS, 0.0).tap do |vector|
          vector[0] = 1.0
        end
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
    assert_includes response.body, "Similarity"
    assert_equal 1, FakeConnection.requests.count
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
