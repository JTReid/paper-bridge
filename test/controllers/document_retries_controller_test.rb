require "test_helper"

class DocumentRetriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @document = documents(:advance_directive)
    @document.file.attach(io: StringIO.new("Original document contents."), filename: "original-record.txt", content_type: "text/plain")
    @document.update!(
      status: :failed,
      preparation_status: :prepared,
      preparation_error: "A previous attempt stopped.",
      summary: { summary: "Summary from the unfinished attempt.", key_points: [ "An unfinished key point." ] },
      summarized_at: 1.hour.ago
    )
    clear_enqueued_jobs
    sign_in users(:family_admin)
  end

  test "requires authentication and an active subscription" do
    sign_out users(:family_admin)

    assert_no_enqueued_jobs do
      post retry_processing_document_path(@document)
    end
    assert_redirected_to new_user_session_path

    sign_in users(:family_admin)
    billing_subscriptions(:greenfield_active).update!(status: "canceled")

    assert_no_enqueued_jobs do
      post retry_processing_document_path(@document)
    end
    assert_redirected_to billing_path
    assert_predicate @document.reload, :failed?
  end

  test "requires a family account before finding the document" do
    sign_out users(:family_admin)
    sign_in users(:super_admin)

    assert_no_enqueued_jobs do
      post retry_processing_document_path(@document)
    end

    assert_redirected_to admin_accounts_path
    assert_predicate @document.reload, :failed?
  end

  test "does not retry another account document" do
    with_stubbed_singleton_method(Documents::RetryProcessing, :call, ->(*) { flunk "Unauthorized documents must not reach retry processing" }) do
      post retry_processing_document_path(documents(:outside_account))
      assert_response :not_found
    end

    assert_predicate @document.reload, :failed?
  end

  test "does not retry a document outside the supplied profile" do
    with_stubbed_singleton_method(Documents::RetryProcessing, :call, ->(*) { flunk "Unauthorized documents must not reach retry processing" }) do
      post retry_processing_document_path(@document), params: { dependent_id: dependents(:noah).id }
      assert_response :not_found
    end

    assert_predicate @document.reload, :failed?
  end

  test "does not accept another account profile for a retry" do
    with_stubbed_singleton_method(Documents::RetryProcessing, :call, ->(*) { flunk "Unauthorized documents must not reach retry processing" }) do
      post retry_processing_document_path(@document), params: { dependent_id: dependents(:other_dependent).id }
      assert_response :not_found
    end

    assert_predicate @document.reload, :failed?
  end

  test "queues one retry with a Turbo redirect and ignores forged document attributes" do
    before = @document.attributes.except("status", "processing_job_id", "updated_at")
    attachment_id = @document.file_attachment.id
    blob_id = @document.file_blob.id

    assert_no_difference [ "Document.count", "ActiveStorage::Attachment.count", "ActiveStorage::Blob.count" ] do
      assert_enqueued_jobs 1, only: ProcessDocumentJob do
        post retry_processing_document_path(@document), params: {
          dependent_id: @document.dependent_id,
          document: { title: "Forged title", description: "Forged description", category: "medical", status: "processed", dependent_id: dependents(:noah).id }
        }, headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
      end
    end

    assert_response :see_other
    assert_redirected_to document_path(@document)
    assert_equal "Document queued for processing.", flash[:notice]
    assert_predicate @document.reload, :queued?
    assert_equal before, @document.attributes.except("status", "processing_job_id", "updated_at")
    assert_equal attachment_id, @document.file_attachment.id
    assert_equal blob_id, @document.file_blob.id

    follow_redirect!(headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" })

    assert_response :success
    assert_equal "text/html", response.media_type
    assert_select "[data-testid='flash-notice']", text: "Document queued for processing."
    assert_select "[data-testid='document-retry-processing']", count: 0
    assert_includes response.body, "Summary from the unfinished attempt."
  end

  test "another member of the same family account can retry the document" do
    sign_out users(:family_admin)
    sign_in users(:account_member)

    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      post retry_processing_document_path(@document)
    end

    assert_response :see_other
    assert_redirected_to document_path(@document)
    assert_predicate @document.reload, :queued?
  end

  test "repeated posts queue only one attempt" do
    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      post retry_processing_document_path(@document)
      post retry_processing_document_path(@document)
    end

    assert_response :see_other
    assert_redirected_to document_path(@document)
    assert_equal "This document is already being prepared.", flash[:alert]
    assert_predicate @document.reload, :queued?
  end

  test "does not queue a document that has already finished processing" do
    @document.processed!
    before = @document.attributes

    assert_no_enqueued_jobs do
      post retry_processing_document_path(@document)
    end

    assert_response :see_other
    assert_redirected_to document_path(@document)
    assert_equal "This document is not available to retry.", flash[:alert]
    assert_equal before, @document.reload.attributes
  end

  test "explains when a failed document already has an automatic processing attempt" do
    before = @document.attributes

    with_stubbed_singleton_method(Documents::RetryProcessing, :call, false) do
      assert_no_enqueued_jobs do
        post retry_processing_document_path(@document)
      end
    end

    assert_response :see_other
    assert_redirected_to document_path(@document)
    assert_equal "A processing attempt is already queued or running.", flash[:alert]
    assert_equal before, @document.reload.attributes
  end

  test "an enqueue failure keeps the failed document and shows a generic recovery message" do
    before = @document.attributes

    with_stubbed_singleton_method(Documents::RetryProcessing, :call, ->(*) { raise Documents::RetryProcessing::EnqueueError, "Private queue connection details" }) do
      assert_no_enqueued_jobs do
        post retry_processing_document_path(@document)
      end
    end

    assert_response :see_other
    assert_redirected_to document_path(@document)
    assert_equal "We couldn’t queue this document. Please try again.", flash[:alert]
    assert_equal before, @document.reload.attributes

    follow_redirect!

    assert_select "[data-testid='document-retry-processing']", text: "Retry processing"
    assert_not_includes response.body, "Private queue connection details"
  end

  test "failed document keeps its generated summary alongside the failure and retry control" do
    get document_path(@document)

    assert_response :success
    assert_select "form[action='#{retry_processing_document_path(@document)}'][method='post']" do
      assert_select "button[data-testid='document-retry-processing'][data-turbo-submits-with='Queuing…']", text: "Retry processing"
    end
    assert_includes response.body, "You can retry using your saved original file."
    assert_includes response.body, "Summary from the unfinished attempt."
    assert_includes response.body, "An unfinished key point."
    assert_select "##{ActionView::RecordIdentifier.dom_id(@document, :summary)}", text: /Generated/
    assert_select "[data-testid='document-processing-status']", text: /Needs attention/
    assert_select "[aria-label='Summary ready']"
    assert_select "[aria-label='Ask PaperBridge unavailable']"
    assert_equal "Summary from the unfinished attempt.", @document.reload.summary.fetch("summary")
  end

  test "generated summaries are available independently of overall processing status" do
    %i[uploaded queued processing processed].each do |status|
      @document.update!(status: status)

      get document_path(@document)

      assert_response :success
      assert_select "[data-testid='document-retry-processing']", count: 0
      assert_includes response.body, "Summary from the unfinished attempt."
      assert_includes response.body, "An unfinished key point."
      assert_select "##{ActionView::RecordIdentifier.dom_id(@document, :summary)}", text: /Generated/
      assert_select "[aria-label='Summary ready']"
    end
  end

  test "starting the retry clears the previous summary until a new one is generated" do
    post retry_processing_document_path(@document)
    assert Documents::ResetProcessing.call(@document.reload)

    get document_path(@document)

    assert_response :success
    assert_not_includes response.body, "Summary from the unfinished attempt."
    assert_not_includes response.body, "An unfinished key point."
    assert_includes response.body, "Your summary will appear when it’s ready."
    assert_select "[aria-label='Summary ready']", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(@document, :summary)}", text: /Generated/, count: 0
  end

  test "an error payload is not presented as a generated summary" do
    @document.update!(summary: { error: { message: "Private processing error" } })

    get document_path(@document)

    assert_response :success
    assert_select "[data-testid='document-retry-processing']"
    assert_select "[aria-label='Summary ready']", count: 0
    assert_select "##{ActionView::RecordIdentifier.dom_id(@document, :summary)}", text: /Generated/, count: 0
    assert_not_includes response.body, "Private processing error"
  end

  test "storage-only documents have no generated summary" do
    @document.stored!
    get document_path(@document)

    assert_response :success
    assert_select "[data-testid='document-retry-processing']", count: 0
    assert_not_includes response.body, "Summary from the unfinished attempt."
    assert_not_includes response.body, "An unfinished key point."
    assert_select "##{ActionView::RecordIdentifier.dom_id(@document, :summary)}", text: /Generated/, count: 0
  end

  test "failed unsupported documents and missing originals have no retry button" do
    @document.file.blob.update!(content_type: "application/zip")
    @document.update!(content_type: "application/zip")

    get document_path(@document)

    assert_response :success
    assert_select "[data-testid='document-retry-processing']", count: 0

    @document.file.detach
    get document_path(@document)

    assert_response :success
    assert_select "[data-testid='document-retry-processing']", count: 0
    assert_includes response.body, "Please contact support."
  end
end
