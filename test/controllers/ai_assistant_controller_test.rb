require "test_helper"

class AiAssistantControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependent_ai_assistant_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "requires an active subscription" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(dependents(:emma))

    assert_redirected_to billing_path
    assert_equal "A subscription is required to continue.", flash[:alert]
  end

  test "renders empty assistant without creating a pipeline run" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { PipelineRun.count } do
      get dependent_ai_assistant_path(dependent)
    end

    assert_response :success
    assert_includes response.body, "Ask PaperBridge"
    assert_includes response.body, "Suggested questions"
    assert_includes response.body, "Based on your records"
    assert_includes response.body, "PaperBridge uses AI to answer from these records"
    assert_no_match(/<button[^>]+disabled/, response.body)

    visible_text = Nokogiri::HTML(response.body).text.squish
    assert_no_match(/\bchunks?\b|\bembeddings?\b|\bretrieval\b|Run #/i, visible_text)
  end

  test "renders assistant inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { PipelineRun.count } do
      get dependent_ai_assistant_path(dependent)
    end

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "Ask PaperBridge"
    assert_includes response.body, "Care Team"
  end

  test "renders validated inline citations and source cards that open the cited PDF page" do
    dependent = dependents(:emma)
    document = documents(:advance_directive)
    chunk = document_chunks(:one)
    document.file.attach(
      io: StringIO.new("%PDF-1.4\n% fake test pdf"),
      filename: "advance-directive.pdf",
      content_type: "application/pdf"
    )
    document.update!(original_filename: "advance-directive.pdf", content_type: "application/pdf")
    result = Documents::VectorSearch::Result.new(
      chunk: chunk,
      document: document,
      page: chunk.document_page,
      similarity: 0.95
    )
    pipeline = Struct.new(:response) do
      def execute; end
      def to_response = response
    end.new(
      {
        results: [ result ],
        result_count: 1,
        answer: {
          answer: "The record supports this answer [1].",
          citations: [
            {
              source_number: 1,
              document_id: document.id,
              document_title: document.title,
              page_number: 1,
              quote: "<script>alert('source')</script>"
            }
          ],
          limitations: [ "<img src=x onerror=alert(1)>" ]
        }
      }
    )
    sign_in users(:family_admin)

    with_stubbed_singleton_method(Agentic::DocumentSearchPipeline, :new, ->(*_args) { pipeline }) do
      get dependent_ai_assistant_path(dependent, q: "What does the record say?")
    end

    assert_response :success
    source_path = original_document_path(document, page: 1)
    assert_select "a[data-testid='ai-inline-source-1'][target='_blank'][rel='noopener'][href='#{source_path}']", text: "[1]"
    assert_select "a[data-testid='ai-source-card-1'][target='_blank'][rel='noopener'][href='#{source_path}']", text: "#{document.title}, page 1"
    visible_text = Nokogiri::HTML(response.body).text
    assert_includes visible_text, "<script>alert('source')</script>"
    assert_includes visible_text, "<img src=x onerror=alert(1)>"
    assert_not_includes response.body, "<script>alert('source')</script>"
    assert_not_includes response.body, "<img src=x onerror=alert(1)>"
  end

  test "renders search error when agentic pipeline fails" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    pipeline = Class.new do
      def execute
        raise Agentic::Errors::ConfigurationError, "Simulated QA failure"
      end
    end.new

    pipeline_class = Agentic::DocumentSearchPipeline.singleton_class
    pipeline_class.alias_method :new_without_failure_stub, :new
    Agentic::DocumentSearchPipeline.define_singleton_method(:new) { |*| pipeline }

    begin
      get dependent_ai_assistant_path(dependent, q: "What changed?")
    ensure
      pipeline_class.alias_method :new, :new_without_failure_stub
      pipeline_class.remove_method :new_without_failure_stub
    end

    assert_response :success
    assert_includes response.body, "We couldn’t answer that right now"
    assert_not_includes response.body, "Simulated QA failure"
    assert_no_match(/PaperBridge Answer/, response.body)
  end
end
