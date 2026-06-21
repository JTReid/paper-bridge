require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependent_documents_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "lists documents inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_documents_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "Care Records"
    assert_includes response.body, dependent_ai_assistant_path(dependent)
    assert_includes response.body, documents(:advance_directive).title
  end

  test "renders upload form inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get new_dependent_document_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, dependent_documents_path(dependent)
  end

  test "uploads a document into the signed in account" do
    user = users(:family_admin)
    sign_in user

    assert_enqueued_with(job: ProcessDocumentJob) do
      assert_difference -> { Document.count } do
        post dependent_documents_path(dependents(:emma)), params: {
          document: {
            title: "Durable Power of Attorney",
            description: "Signed copy",
            category: "general",
            file: Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain")
          }
        }
      end
    end

    document = Document.order(:created_at).last
    assert_redirected_to document_path(document)
    assert_equal user.account, document.account
    assert_equal dependents(:emma), document.dependent
    assert_equal "general", document.category
    assert_equal user, document.user
    assert document.file.attached?
    assert_equal "sample.txt", document.original_filename
    assert_equal "queued", document.status
  end

  test "failed scoped upload preserves dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { Document.count } do
      post dependent_documents_path(dependent), params: {
        document: {
          title: "Missing file",
          category: "general"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, dependent_documents_path(dependent)
  end

  test "shows persisted document chunks" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: document.content_type
    )
    document.update!(status: :processed, preparation_status: :prepared)
    sign_in users(:family_admin)

    get document_path(document)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent_documents_path(document.dependent)
    assert_includes response.body, "Legal chunk 1"
    assert_includes response.body, "Embedded page text"
    assert_includes response.body, "Starts on page 1"
    assert_not_includes response.body, "No chunks have been created yet."
    assert_includes response.body, "Chunks ready"
    assert_includes response.body, "Pages ready"
    assert_includes response.body, "turbo-cable-stream-source"
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :processing_status)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :processing_stats)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :chunks)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :file_details)
  end

  test "deletes document and returns to dependent documents" do
    document = documents(:advance_directive)
    sign_in users(:family_admin)

    assert_difference -> { Document.count }, -1 do
      delete document_path(document)
    end

    assert_redirected_to dependent_documents_path(document.dependent)
  end

  test "does not show documents from another account" do
    sign_in users(:family_admin)

    get document_path(documents(:outside_account))

    assert_response :not_found
  end
end
