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

  test "get renders the assistant without starting work" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference [ -> { AiAssistantQuery.count }, -> { PipelineRun.count } ] do
      assert_no_enqueued_jobs do
        get dependent_ai_assistant_path(dependent, q: "This old URL must not run a query")
      end
    end

    assert_response :success
    assert_includes response.body, "Ask PaperBridge"
    assert_includes response.body, "Suggested questions"
    assert_includes response.body, "Based on your records"
    assert_includes response.body, "Most answers begin appearing within about 30 seconds"
    assert_select "form[method='post'][data-testid='ai-assistant-form']"
    assert_select "turbo-cable-stream-source"
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "[data-controller='ai-assistant-query'][data-ai-assistant-query-reassure-after-value='10000'][data-ai-assistant-query-long-wait-after-value='30000']"
    assert_select "[data-ai-assistant-query-target='announcer'][aria-live='polite']"

    visible_text = Nokogiri::HTML(response.body).text.squish
    assert_no_match(/\bchunks?\b|\bembeddings?\b|\bretrieval\b|Run #/i, visible_text)
  end

  test "renders assistant inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "Ask PaperBridge"
    assert_includes response.body, "Care Team"
  end

  test "post saves the stripped question and enqueues the answer job" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_difference -> { AiAssistantQuery.count }, 1 do
      assert_enqueued_with(job: AnswerAiAssistantQueryJob, queue: "ai_assistant") do
        post dependent_ai_assistant_path(dependent), params: { q: "  What changed?  " }
      end
    end

    query = AiAssistantQuery.order(:id).last
    assert_redirected_to dependent_ai_assistant_path(dependent)
    assert_equal "What changed?", query.question
    assert_equal users(:family_admin), query.user
    assert_equal dependent, query.dependent
    assert_predicate query, :queued?
    assert_not_nil query.enqueued_at
    assert_equal 0, PipelineRun.where(subject: query).count
  end

  test "turbo post installs the queued query before requesting background work" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_enqueued_jobs do
      post dependent_ai_assistant_path(dependent),
        params: { q: "What changed?" },
        headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_select "turbo-stream[action='update'][target='ai_assistant_result']"
    assert_includes response.body, "Your question is queued"
    assert_includes response.body, "What changed?"
    query = AiAssistantQuery.order(:id).last
    start_path = start_dependent_ai_assistant_query_path(dependent, query)
    assert_select "[data-ai-assistant-query-target='query'][data-phase='queued'][data-active='true'][data-start-url='#{start_path}']"
    assert_nil query.enqueued_at
  end

  test "start enqueues a saved query once" do
    query = create_query
    sign_in users(:family_admin)

    assert_enqueued_with(job: AnswerAiAssistantQueryJob, args: [ query ], queue: "ai_assistant") do
      post start_dependent_ai_assistant_query_path(query.dependent, query)
    end

    assert_response :accepted
    assert_equal true, response.parsed_body["started"]
    assert_not_nil query.reload.enqueued_at

    assert_no_enqueued_jobs do
      post start_dependent_ai_assistant_query_path(query.dependent, query)
    end

    assert_response :accepted
    assert_equal false, response.parsed_body["started"]
  end

  test "another user cannot start a saved query" do
    query = create_query
    sign_in users(:account_member)

    assert_no_enqueued_jobs do
      post start_dependent_ai_assistant_query_path(query.dependent, query)
    end

    assert_response :not_found
    assert_nil query.reload.enqueued_at
  end

  test "blank post does not save or enqueue a query" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { AiAssistantQuery.count } do
      assert_no_enqueued_jobs do
        post dependent_ai_assistant_path(dependent), params: { q: "   " }
      end
    end

    assert_redirected_to dependent_ai_assistant_path(dependent)
    assert_equal "Question can't be blank", flash[:alert]
  end

  test "cannot query a dependent from another account" do
    sign_in users(:family_admin)

    assert_no_difference -> { AiAssistantQuery.count } do
      post dependent_ai_assistant_path(dependents(:other_dependent)), params: { q: "What changed?" }
    end

    assert_response :not_found
  end

  test "get restores the current user's latest query" do
    query = create_query(question: "What should I ask next?")
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(query.dependent)

    assert_response :success
    assert_includes response.body, query.question
    assert_includes response.body, "Your question is queued"
    start_path = start_dependent_ai_assistant_query_path(query.dependent, query)
    assert_select "[data-testid='ai-assistant-query-result'][data-phase='queued'][data-active='true'][data-start-url='#{start_path}']"
  end

  test "get does not restart a query that has already been enqueued" do
    query = create_query(enqueued_at: Time.current)
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(query.dependent)

    assert_response :success
    assert_select "[data-testid='ai-assistant-query-result'][data-phase='queued'][data-active='true']"
    assert_select "[data-testid='ai-assistant-query-result'][data-start-url]", count: 0
  end

  test "renders validated inline citations from a completed query" do
    dependent = dependents(:emma)
    document = documents(:advance_directive)
    document.file.attach(
      io: StringIO.new("%PDF-1.4\n% fake test pdf"),
      filename: "advance-directive.pdf",
      content_type: "application/pdf"
    )
    document.update!(original_filename: "advance-directive.pdf", content_type: "application/pdf")
    create_query(
      state: :completed,
      result_count: 1,
      completed_at: Time.current,
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
    )
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(dependent)

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

  test "renders a safe message for a failed query" do
    create_query(
      state: :failed,
      failed_at: Time.current,
      error_message: "We couldn’t answer that right now. Please try again in a moment."
    )
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(dependents(:emma))

    assert_response :success
    assert_includes response.body, "We couldn’t answer that right now"
    assert_not_includes response.body, "Simulated QA failure"
    assert_no_match(/PaperBridge Answer/, response.body)
  end

  test "renders a streamed draft as escaped plain text" do
    create_query(
      state: :processing,
      started_at: Time.current,
      draft_answer: "Draft <script>alert('draft')</script>"
    )
    sign_in users(:family_admin)

    get dependent_ai_assistant_path(dependents(:emma))

    assert_response :success
    assert_select "[data-testid='ai-assistant-draft']"
    assert_select "[data-testid='ai-assistant-query-result'][data-phase='drafting'][data-active='true']"
    assert_includes Nokogiri::HTML(response.body).text, "Draft <script>alert('draft')</script>"
    assert_not_includes response.body, "Draft <script>alert('draft')</script>"
    assert_includes response.body, "PaperBridge is checking the sources"
  end

  private

    def create_query(attributes = {})
      AiAssistantQuery.create!({
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        question: "What changed?"
      }.merge(attributes))
    end
end
