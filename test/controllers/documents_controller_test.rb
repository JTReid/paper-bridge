require "test_helper"

class DocumentsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependent_documents_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "original file requires authentication" do
    get original_document_path(documents(:advance_directive))

    assert_redirected_to new_user_session_path
  end

  test "opens an authorized PDF at a requested page through a temporary storage URL" do
    document = documents(:advance_directive)
    document.file.attach(
      io: StringIO.new("%PDF-1.4\n% fake test pdf"),
      filename: "advance-directive.pdf",
      content_type: "application/pdf"
    )
    document.update!(original_filename: "advance-directive.pdf", content_type: "application/pdf")
    sign_in users(:family_admin)

    get original_document_path(document, page: 4)

    assert_response :redirect
    assert_equal "page=4", URI.parse(response.location).fragment

    follow_redirect!

    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match(/inline/, response.headers.fetch("Content-Disposition"))
  end

  test "does not open an original file from another account" do
    sign_in users(:family_admin)

    get original_document_path(documents(:outside_account))

    assert_response :not_found
  end

  test "downloads a non-PDF original without a page fragment" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: "text/plain"
    )
    sign_in users(:family_admin)

    get original_document_path(document, page: 4)

    assert_response :redirect
    assert_nil URI.parse(response.location).fragment

    follow_redirect!

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
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
    assert_includes response.body, "data-controller=\"document-share\""
    assert_includes response.body, "Share Documents"
    assert_includes response.body, "Share Selected"
    assert_includes response.body, "Choose care team email"
    assert_includes response.body, "therapist@example.test"
    assert_includes response.body, "data-document-share-target=\"modal\""
    assert_includes response.body, "Share #{documents(:advance_directive).title}"
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(documents(:advance_directive), :share_checkbox)
  end

  test "filters documents by category" do
    dependent = dependents(:emma)
    medical_document = create_attached_document(
      dependent: dependent,
      title: "Medical Evaluation",
      category: :medical
    )
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, category: "medical")

    assert_response :success
    assert_select "[data-testid='document-row-#{medical_document.id}']", text: /#{Regexp.escape(medical_document.title)}/
    assert_select "[data-testid='document-row-#{documents(:advance_directive).id}']", count: 0
    assert_select "a[data-testid='documents-category-filter-medical'][aria-current='page'][href='#{dependent_documents_path(dependent, category: "medical")}']", text: "Medical"
    assert_select "a[data-testid='documents-category-filter-all'][href='#{dependent_documents_path(dependent)}']"
  end

  test "filters prescription documents by category" do
    dependent = dependents(:emma)
    prescription_document = create_attached_document(
      dependent: dependent,
      title: "Medication Schedule",
      category: :prescriptions
    )
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, category: "prescriptions")

    assert_response :success
    assert_select "[data-testid='document-row-#{prescription_document.id}']", text: /#{Regexp.escape(prescription_document.title)}/
    assert_select "[data-testid='document-row-#{documents(:advance_directive).id}']", count: 0
    assert_select "a[data-testid='documents-category-filter-prescriptions'][aria-current='page'][href='#{dependent_documents_path(dependent, category: "prescriptions")}']", text: "Prescriptions"
  end

  test "searches documents by original filename" do
    dependent = dependents(:emma)
    matching_document = create_attached_document(
      dependent: dependent,
      title: "Annual Evaluation",
      category: :medical,
      filename: "Annual-Medical-Evaluation.PDF"
    )
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, q: "medical-evaluation")

    assert_response :success
    assert_select "form[data-controller='document-search'][data-testid='documents-search-form'][action='#{dependent_documents_path(dependent)}'][method='get']"
    assert_select "input[data-testid='documents-search-field'][data-action='search->document-search#clear'][name='q'][value='medical-evaluation']"
    assert_select "[data-testid='document-row-#{matching_document.id}']", text: /Annual-Medical-Evaluation\.PDF/
    assert_select "[data-testid='document-row-#{documents(:advance_directive).id}']", count: 0
    assert_select "a[data-testid='documents-category-filter-medical'][href='#{dependent_documents_path(dependent, category: "medical", q: "medical-evaluation")}']"
  end

  test "filename search composes with category and has a clearable empty state" do
    dependent = dependents(:emma)
    create_attached_document(
      dependent: dependent,
      title: "Annual Evaluation",
      category: :medical,
      filename: "annual-evaluation.pdf"
    )
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, category: "general", q: "annual")

    assert_response :success
    assert_select "input[type='hidden'][name='category'][value='general']"
    assert_select "[data-testid^='document-row-']", count: 0
    assert_select "h2", text: "No documents found"
    assert_select "a[data-testid='documents-search-clear'][href='#{dependent_documents_path(dependent, category: "general")}']", text: "Clear search"
  end

  test "filename search treats SQL wildcards literally and remains dependent scoped" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, q: "%")

    assert_response :success
    assert_select "[data-testid^='document-row-']", count: 0
    assert_select "h2", text: "No documents found"

    get dependent_documents_path(dependent, q: "outside")

    assert_response :success
    assert_select "[data-testid^='document-row-']", count: 0
    assert_not_includes response.body, documents(:outside_account).title
  end

  test "ignores an unknown category filter" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, category: "unknown")

    assert_response :success
    assert_includes response.body, documents(:advance_directive).title
    assert_select "a[data-testid='documents-category-filter-all'][aria-current='page'][href='#{dependent_documents_path(dependent)}']", text: "All Categories"
    assert_select "a[data-testid^='documents-category-filter-'][aria-current='page']", count: 1
  end

  test "renders a filter chip for every document category" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_documents_path(dependent)

    assert_response :success
    Document.categories.each_key do |category|
      assert_select "a[data-testid='documents-category-filter-#{category}'][href='#{dependent_documents_path(dependent, category: category)}']", text: category.humanize
    end
  end

  test "category badge color follows the document category rather than its chunk label" do
    document = documents(:advance_directive)
    assert_not_equal document.category, document.document_chunks.first.label
    sign_in users(:family_admin)

    get dependent_documents_path(document.dependent)

    assert_response :success
    assert_select "[data-testid='document-row-#{document.id}'] span.bg-slate-100.text-slate-700", text: "General"
  end

  test "renders upload form inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get new_dependent_document_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, dependent_documents_path(dependent)
    assert_includes response.body, "data-controller=\"file-dropzone\""
    assert_includes response.body, "data-file-dropzone-category-options-value"
    assert_includes response.body, "name=\"document[files][]\""
    assert_includes response.body, "multiple=\"multiple\""
  end

  test "preselects a valid category passed to the upload form" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get new_dependent_document_path(dependent, category: "prescriptions")

    assert_response :success
    assert_select "select[name='document[category]'] option[selected='selected'][value='prescriptions']", text: "Prescriptions"
  end

  test "falls back to general when the upload category is unknown" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get new_dependent_document_path(dependent, category: "unknown")

    assert_response :success
    assert_select "select[name='document[category]'] option[selected='selected'][value='general']", text: "General"
  end

  test "filtered empty state carries its category to the upload form" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, category: "insurance")

    assert_response :success
    assert_includes response.body, "No insurance documents yet"
    assert_includes response.body, "Add Insurance Document"
    assert_select "a[data-testid='documents-empty-add-link'][href='#{new_dependent_document_path(dependent, category: "insurance")}']"
  end

  test "uploads a document into the signed in account" do
    user = users(:family_admin)
    sign_in user

    assert_enqueued_with(job: ProcessDocumentJob) do
      assert_difference -> { Document.count } do
        post dependent_documents_path(dependents(:emma)), params: {
          document: {
            title: "Medication Instructions",
            description: "Current prescription directions",
            category: "prescriptions",
            files: [ Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain") ]
          }
        }
      end
    end

    document = Document.order(:created_at).last
    assert_redirected_to document_path(document)
    assert_equal user.account, document.account
    assert_equal dependents(:emma), document.dependent
    assert_equal "prescriptions", document.category
    assert_equal user, document.user
    assert document.file.attached?
    assert_equal "sample.txt", document.original_filename
    assert_equal "queued", document.status
  end

  test "uploads multiple documents into the signed in account" do
    user = users(:family_admin)
    dependent = dependents(:emma)
    sign_in user

    assert_enqueued_jobs 2, only: ProcessDocumentJob do
      assert_difference -> { Document.count }, 2 do
        post dependent_documents_path(dependent), params: {
          document: {
            description: "Shared context",
            category: "medical",
            file_categories: [ "educational", "therapy" ],
            files: [
              Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain", original_filename: "first-document.txt"),
              Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain", original_filename: "second-document.txt")
            ]
          }
        }
      end
    end

    assert_redirected_to dependent_documents_path(dependent)
    assert_equal "2 documents uploaded and being prepared.", flash[:notice]

    documents = Document.order(:created_at).last(2)
    assert_equal [ "first-document", "second-document" ], documents.map(&:title)
    assert_equal [ "first-document.txt", "second-document.txt" ], documents.map(&:original_filename)
    assert_equal [ "educational", "therapy" ], documents.map(&:category)
    assert_equal [ "Shared context", "Shared context" ], documents.map(&:description)
    assert_equal [ user.account, user.account ], documents.map(&:account)
    assert_equal [ dependent, dependent ], documents.map(&:dependent)
    assert_equal [ user, user ], documents.map(&:user)
    assert documents.all? { |document| document.file.attached? }
    assert_equal [ "queued", "queued" ], documents.map(&:status)
  end

  test "multi document upload reports partial failures without blocking valid files" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_enqueued_jobs 1, only: ProcessDocumentJob do
      assert_difference -> { Document.count }, 1 do
        post dependent_documents_path(dependent), params: {
          document: {
            category: "general",
            files: [
              Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain", original_filename: "partial-valid.txt"),
              "not-a-file"
            ]
          }
        }
      end
    end

    assert_redirected_to dependent_documents_path(dependent)
    assert_equal "1 document uploaded and being prepared.", flash[:notice]
    assert_equal "1 file could not be uploaded: Unnamed file.", flash[:alert]

    document = Document.order(:created_at).last
    assert_equal "partial-valid", document.title
    assert_equal "partial-valid.txt", document.original_filename
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

  test "shows family-facing document details and opens the original file" do
    document = documents(:advance_directive)
    document.file.attach(
      io: StringIO.new("%PDF-1.4\n% fake test pdf"),
      filename: "advance-directive.pdf",
      content_type: "application/pdf"
    )
    document.update!(original_filename: "advance-directive.pdf", content_type: "application/pdf")
    document.update!(
      status: :processed,
      preparation_status: :prepared,
      summary: {
        title: "Advance Directive Summary",
        summary: "This document covers legal planning needs.",
        key_points: [
          "Legal authority is documented.",
          "Planning details are available for review."
        ]
      },
      summarized_at: Time.zone.local(2026, 6, 14, 12, 0, 0)
    )
    sign_in users(:family_admin)

    get document_path(document)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent_documents_path(document.dependent)
    assert_includes response.body, "Summary"
    assert_includes response.body, "This document covers legal planning needs."
    assert_includes response.body, "Legal authority is documented."
    assert_includes response.body, "File name"
    assert_includes response.body, "PDF"
    assert_includes response.body, "Ask PaperBridge"
    assert_not_includes response.body, "View document text"
    assert_not_includes response.body, "Embedded page text"
    assert_select "a[data-testid='document-open-original'][target='_blank'][rel='noopener'][href='#{original_document_path(document)}']", text: "Open original"

    visible_text = Nokogiri::HTML(response.body).text.squish
    assert_no_match(/\bchunks?\b|\bembeddings?\b|ingestion job|\bchars\b/i, visible_text)
    assert_includes response.body, "turbo-cable-stream-source"
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :processing_status)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :processing_stats)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :summary)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(document, :file_details)
  end

  test "renders edit form for basic document details" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: document.content_type
    )
    sign_in users(:family_admin)

    get edit_document_path(document)

    assert_response :success
    assert_includes response.body, "Edit Document"
    assert_includes response.body, document.title
    assert_includes response.body, "Save changes"
    assert_includes response.body, document_path(document)
    assert_not_includes response.body, "type=\"file\""
  end

  test "updates basic document details without enqueueing processing" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: document.content_type
    )
    document.update!(status: :processed, preparation_status: :prepared)
    sign_in users(:family_admin)

    assert_no_enqueued_jobs only: ProcessDocumentJob do
      patch document_path(document), params: {
        document: {
          title: "Updated Planning Document",
          description: "Updated notes",
          category: "medical",
          file: Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain")
        }
      }
    end

    document.reload
    assert_redirected_to document_path(document)
    assert_equal "Updated Planning Document", document.title
    assert_equal "Updated notes", document.description
    assert_equal "medical", document.category
    assert_equal "processed", document.status
    assert_equal "prepared", document.preparation_status
    assert_equal "advance-directive.txt", document.original_filename
  end

  test "does not edit documents from another account" do
    sign_in users(:family_admin)

    get edit_document_path(documents(:outside_account))

    assert_response :not_found
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

  private

    def create_attached_document(dependent:, title:, category:, filename: "#{title.parameterize}.txt")
      Document.new(
        account: dependent.account,
        dependent: dependent,
        user: users(:family_admin),
        title: title,
        category: category
      ).tap do |document|
        document.file.attach(
          io: file_fixture("sample.txt").open,
          filename: filename,
          content_type: "text/plain"
        )
        document.save!
      end
    end
end
