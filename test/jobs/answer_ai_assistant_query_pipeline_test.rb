require "test_helper"

class AnswerAiAssistantQueryPipelineTest < ActiveJob::TestCase
  SOURCE_TEXT = "José uses a visual schedule.\nSchool staff report calmer transitions."
  ANSWER_TEXT = "José benefits from a visual schedule [1].\n\nAsk the school about transitions."

  # Only the HTTP boundary is replaced. The real job, agents, streaming parser,
  # PostgreSQL vector search, citation normalization, and persistence all run.
  class FakeConnection
    class << self
      attr_accessor :requests
    end

    class StreamResponse
      def code
        200
      end

      def read_body
        content = {
          answer: ANSWER_TEXT,
          citations: [ { chunk_id: 1, document_title: "Invented title", page_number: 99, quote: "Invented quote" } ],
          limitations: [ "Only the uploaded records were considered." ]
        }.to_json
        events = [
          { choices: [ { delta: { content: content[0, 50] }, finish_reason: nil } ] },
          { choices: [ { delta: { content: content[50..] }, finish_reason: "stop" } ] },
          { choices: [], usage: { prompt_tokens: 30, completion_tokens: 20, total_tokens: 50 } }
        ]
        body = events.map { |event| "data: #{event.to_json}\n\n" }.join + "data: [DONE]\n\n"
        body.bytes.each_slice(37) { |bytes| yield bytes.pack("C*") }
      end
    end

    class Request
      def self.execute(**options)
        payload = JSON.parse(options.fetch(:payload))
        FakeConnection.requests << { url: options.fetch(:url), payload: payload }

        case options.fetch(:url)
        when "https://api.openai.com/v1/embeddings"
          {
            data: [ { index: 0, embedding: [ 1.0 ] + Array.new(DocumentEmbedding::DIMENSIONS - 1, 0.0) } ],
            model: payload.fetch("model"), usage: { prompt_tokens: 5, total_tokens: 5 }
          }.to_json
        when "https://api.openai.com/v1/chat/completions"
          response = StreamResponse.new
          options.fetch(:block_response).call(response)
          response
        else
          raise "Unexpected Ask pipeline test endpoint"
        end
      end
    end
  end

  setup do
    Rails.application.load_seed
    @original_connection = AnswerAiAssistantQueryJob.llm_connection
    AnswerAiAssistantQueryJob.llm_connection = FakeConnection
    FakeConnection.requests = []
    @document = documents(:advance_directive)
    @document.file.attach(io: StringIO.new(SOURCE_TEXT), filename: "school-notes.txt", content_type: "text/plain")
    @document.update!(status: :processed, initial_metadata_pending: false)
    @chunk = document_chunks(:one)
    @chunk.update!(content: SOURCE_TEXT, content_hash: DocumentChunk.content_hash_for(SOURCE_TEXT))
    embed(@chunk, [ 0.8, 0.6 ])
    create_unfinished_document
    clear_enqueued_jobs
  end

  teardown do
    AnswerAiAssistantQueryJob.llm_connection = @original_connection
  end

  test "runs the real Ask pipeline and persists the streamed answer with actual source citations" do
    query = create_query

    assert_no_difference "SavedAnswer.count" do
      AnswerAiAssistantQueryJob.perform_now(query)
    end

    query.reload
    assert_predicate query, :completed?
    assert_equal 1, query.result_count
    assert_equal ANSWER_TEXT, query.answer_payload.fetch(:answer)
    assert_equal [ {
      source_number: 1, document_id: @document.id, document_title: @document.title,
      page_number: 1, quote: SOURCE_TEXT.squish
    } ], query.answer_payload.fetch(:citations)
    assert_equal [ "Only the uploaded records were considered." ], query.answer_payload.fetch(:limitations)
    assert_nil query.draft_answer
    assert_not_nil query.completed_at
    assert_predicate query.pipeline_runs.sole, :completed?

    embedding_request, answer_request = FakeConnection.requests
    assert_equal 2, FakeConnection.requests.size
    assert_equal query.question, embedding_request.fetch(:payload).fetch("input")
    assert_equal true, answer_request.fetch(:payload).fetch("stream")
    prompt = answer_request.fetch(:payload).dig("messages", 1, "content")
    assert_includes prompt, SOURCE_TEXT
    assert_not_includes prompt, "Unfinished evidence"
  end

  test "withholds unfinished evidence and completes an empty search without calling answer generation" do
    @document.update!(status: :failed)
    query = create_query

    AnswerAiAssistantQueryJob.perform_now(query)

    query.reload
    assert_predicate query, :completed?
    assert_equal 0, query.result_count
    assert_empty query.answer_payload.fetch(:citations)
    assert_includes query.answer_payload.fetch(:answer), "couldn’t find an answer"
    assert_equal [ "https://api.openai.com/v1/embeddings" ], FakeConnection.requests.pluck(:url)
    assert_predicate query.pipeline_runs.sole, :completed?
  end

  private

    def create_query
      AiAssistantQuery.create!(
        account: @document.account, dependent: @document.dependent, user: @document.user,
        question: "What helps José at school?"
      )
    end

    def embed(chunk, values)
      chunk.document_embeddings.create!(
        provider: DocumentEmbedding::PROVIDER, model: DocumentEmbedding::MODEL,
        dimensions: DocumentEmbedding::DIMENSIONS, distance_metric: DocumentEmbedding::DISTANCE_METRIC,
        embedding: values + Array.new(DocumentEmbedding::DIMENSIONS - values.length, 0.0)
      )
    end

    def create_unfinished_document
      document = Document.create!(
        account: @document.account, dependent: @document.dependent, user: @document.user,
        title: "Unfinished source", category: :general,
        file: { io: StringIO.new("Unfinished evidence"), filename: "unfinished.txt", content_type: "text/plain" }
      )
      document.update!(status: :processing)
      page = document.document_pages.create!(account: document.account, page_number: 1, status: :processed)
      chunk = page.document_chunks.create!(
        account: document.account, document: document, content: "Unfinished evidence",
        content_hash: DocumentChunk.content_hash_for("Unfinished evidence"), label: :general, chunk_index: 1
      )
      embed(chunk, [ 1.0 ])
    end
end
