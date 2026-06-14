require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get documents_path

    assert_redirected_to new_user_session_path
  end

  test "lists documents for the signed in account" do
    sign_in users(:family_admin)

    get documents_path

    assert_response :success
    assert_includes response.body, documents(:advance_directive).title
    assert_not_includes response.body, documents(:outside_account).title
  end

  test "uploads a document into the signed in account" do
    user = users(:family_admin)
    sign_in user

    assert_enqueued_with(job: ProcessDocumentJob) do
      assert_difference -> { Document.count } do
        post documents_path, params: {
          document: {
            title: "Durable Power of Attorney",
            description: "Signed copy",
            file: Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain")
          }
        }
      end
    end

    document = Document.order(:created_at).last
    assert_redirected_to document_path(document)
    assert_equal user.account, document.account
    assert_equal user, document.user
    assert document.file.attached?
    assert_equal "sample.txt", document.original_filename
    assert_equal "queued", document.status
  end

  test "shows persisted document chunks" do
    document = documents(:advance_directive)
    sign_in users(:family_admin)

    get document_path(document)

    assert_response :success
    assert_includes response.body, "Legal chunk 1"
    assert_includes response.body, "Embedded page text"
    assert_includes response.body, "Starts on page 1"
  end

  test "does not show documents from another account" do
    sign_in users(:family_admin)

    get document_path(documents(:outside_account))

    assert_response :not_found
  end
end
