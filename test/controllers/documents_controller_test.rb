require "test_helper"
require "tempfile"
require "vips"

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
    assert_select "a[data-testid='documents-add-link'][data-tour='add-documents'][data-action='product-tour#advance'][data-product-tour-from-phase-param='add_documents'][data-product-tour-next-phase-param='choose_files']"
    assert_select "a[data-testid='documents-ask-ai-link'][data-tour='open-ask'][data-action='product-tour#advance'][data-product-tour-from-phase-param='open_ask'][data-product-tour-next-phase-param='ask_question']"
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
    assert_not_includes response.body, "data-file-dropzone-category-options-value"
    assert_includes response.body, "name=\"document[files][]\""
    assert_includes response.body, "multiple=\"multiple\""
    assert_select "input[type='file'][accept]", count: 0
    assert_select "textarea[name='document[description]']", count: 0
    assert_select "select[name='document[category]']", count: 0
    assert_select "form[data-testid='document-upload-form'][data-tour='upload-form'][data-action='input->product-tour#pause submit->file-dropzone#validateSubmission turbo:submit-end->product-tour#advanceAfterSubmit'][data-product-tour-from-phase-param='upload_submit'][data-product-tour-next-phase-param='open_ask']"
    assert_select "form[data-file-dropzone-max-files-value='50']"
    assert_select "[data-tour='choose-files'] input[data-testid='document-file-field'][data-action='change->file-dropzone#changed change->product-tour#filesSelected']"
    assert_select "button[type='submit'][data-testid='document-upload-submit'][data-tour='upload-submit']", text: "Upload"
  end

  test "does not preselect a category passed to the upload form" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get new_dependent_document_path(dependent, category: "prescriptions")

    assert_response :success
    assert_select "select[name='document[category]']", count: 0
  end

  test "ignores unknown upload category hints" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get new_dependent_document_path(dependent, category: "unknown")

    assert_response :success
    assert_select "select[name='document[category]']", count: 0
  end

  test "filtered empty state links to automatic document upload without a category hint" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_documents_path(dependent, category: "insurance")

    assert_response :success
    assert_includes response.body, "No insurance documents yet"
    assert_includes response.body, "Add Documents"
    assert_select "a[data-testid='documents-empty-add-link'][href='#{new_dependent_document_path(dependent)}']"
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
            initial_metadata_pending: false,
            files: [ Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain") ]
          }
        }
      end
    end

    document = Document.order(:created_at).last
    assert_redirected_to dependent_documents_path(dependents(:emma))
    assert_equal "1 document uploaded and being prepared.", flash[:notice]
    assert_equal user.account, document.account
    assert_equal dependents(:emma), document.dependent
    assert_equal "general", document.category
    assert_nil document.description
    assert_equal "sample", document.title
    assert document.initial_metadata_pending?
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
              Rack::Test::UploadedFile.new(StringIO.new("A different document."), "text/plain", original_filename: "second-document.txt")
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
    assert_equal [ "general", "general" ], documents.map(&:category)
    assert_equal [ nil, nil ], documents.map(&:description)
    assert documents.all?(&:initial_metadata_pending?)
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
    assert_includes flash[:alert], "1 file could not be uploaded."
    assert_includes flash[:alert], "Unnamed file:"

    document = Document.order(:created_at).last
    assert_equal "partial-valid", document.title
    assert_equal "partial-valid.txt", document.original_filename
  end

  test "converts a TIFF image to JPEG before attaching it" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    with_uploaded_files(
      { bytes: test_image.write_to_buffer(".tiff"), filename: "handwritten-prescription.tiff", content_type: "image/tiff" }
    ) do |files|
      assert_difference -> { Document.count }, 1 do
        post dependent_documents_path(dependent), params: {
          document: {
            category: "prescriptions",
            files: files
          }
        }
      end
    end

    document = Document.order(:created_at).last
    assert_redirected_to dependent_documents_path(dependent)
    assert document.initial_metadata_pending?
    assert_equal "handwritten-prescription", document.title
    assert_equal "handwritten-prescription.jpg", document.original_filename
    assert_equal "image/jpeg", document.content_type
    assert_equal [ 0xff, 0xd8, 0xff ], document.file.download.bytes.first(3)
  end

  test "image validation participates in multi-file partial failure handling" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    with_uploaded_files(
      { bytes: "valid notes", filename: "valid-notes.txt", content_type: "text/plain" },
      { bytes: "not really an image", filename: "invalid.png", content_type: "image/png" }
    ) do |files|
      assert_difference -> { Document.count }, 1 do
        post dependent_documents_path(dependent), params: {
          document: {
            category: "general",
            files: files
          }
        }
      end
    end

    assert_redirected_to dependent_documents_path(dependent)
    assert_equal "1 document uploaded and being prepared.", flash[:notice]
    assert_includes flash[:alert], "invalid.png: File does not contain a valid image"
    assert_equal "valid-notes.txt", Document.order(:created_at).last.original_filename
  end

  test "stores Word and other non-processable files unchanged with immediate metadata editing" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)
    files_to_store = [
      { bytes: "PK\x03\x04word document", filename: "school.docx", content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
      { bytes: "PK\x03\x04archive", filename: "records.zip", content_type: "application/zip" },
      { bytes: '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', filename: "drawing.svg", content_type: "image/svg+xml" }
    ]

    with_uploaded_files(*files_to_store) do |files|
      assert_no_enqueued_jobs do
        assert_difference -> { Document.count }, 3 do
          post dependent_documents_path(dependent), params: { document: { files: files, category: "medical", description: "Ignored", status: "processed" } }
        end
      end
    end

    assert_redirected_to dependent_documents_path(dependent)
    assert_equal "3 documents saved without processing.", flash[:notice]

    files_to_store.each do |specification|
      document = dependent.documents.find_by!(original_filename: specification[:filename])
      assert_equal specification[:bytes], document.file.download
      assert document.stored?
      assert_not document.initial_metadata_pending?
      assert_equal "general", document.category
      assert_nil document.description
      assert_empty document.pipeline_runs

      get original_document_path(document)
      follow_redirect!
      assert_response :success
      assert_match(/attachment/, response.headers.fetch("Content-Disposition"))
      assert_equal specification[:bytes], response.body

      get edit_document_path(document)
      assert_select "fieldset[data-testid='document-editable-metadata']:not([disabled])"
      patch document_path(document), params: { document: { category: "educational", description: "Added by family" } }
      assert_redirected_to document_path(document)
      assert_equal "Added by family", document.reload.description
      assert document.stored?
    end
  end

  test "mixed batches distinguish processing uploads from storage-only files" do
    sign_in users(:family_admin)
    with_uploaded_files(
      { bytes: "name,value\nheight,110", filename: "measurements.csv", content_type: "text/csv" },
      { bytes: "PK\x03\x04archive", filename: "records.zip", content_type: "application/zip" }
    ) do |files|
      assert_enqueued_jobs 1, only: [ ProcessDocumentJob, ProcessImageDocumentJob ] do
        assert_difference -> { Document.count }, 2 do
          post dependent_documents_path(dependents(:emma)), params: { document: { files: files } }
        end
      end
    end

    assert_redirected_to dependent_documents_path(dependents(:emma))
    assert_equal "1 document uploaded and being prepared. 1 document saved without processing.", flash[:notice]
    assert dependents(:emma).documents.find_by!(original_filename: "measurements.csv").queued?
    assert dependents(:emma).documents.find_by!(original_filename: "records.zip").stored?
  end

  test "rejects more than 50 files before creating documents blobs or jobs" do
    sign_in users(:family_admin)
    files = Array.new(51) { |index| Rack::Test::UploadedFile.new(StringIO.new("Document #{index}"), "text/plain", original_filename: "record-#{index}.txt") }

    assert_no_enqueued_jobs do
      assert_no_difference [ -> { Document.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count } ] do
        post dependent_documents_path(dependents(:emma)), params: { document: { files: files } }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "You can upload up to 50 files at a time. No files were uploaded."
  ensure
    files&.each(&:close)
  end

  test "accepts exactly 50 distinct files" do
    sign_in users(:family_admin)
    files = Array.new(50) { |index| Rack::Test::UploadedFile.new(StringIO.new("Document #{index}"), "text/plain", original_filename: "record-#{index}.txt") }

    assert_enqueued_jobs 50, only: ProcessDocumentJob do
      assert_difference -> { Document.count }, 50 do
        post dependent_documents_path(dependents(:emma)), params: { document: { files: files } }
      end
    end

    assert_redirected_to dependent_documents_path(dependents(:emma))
    assert_equal "50 documents uploaded and being prepared.", flash[:notice]
  ensure
    files&.each(&:close)
  end

  test "rejects renamed duplicates of existing files without overwriting or creating orphan blobs" do
    dependent = dependents(:emma)
    original = create_attached_document(dependent: dependent, title: "Original", category: "medical")
    original.update!(description: "Keep this description")
    original_attributes = original.reload.attributes
    sign_in users(:family_admin)
    clear_enqueued_jobs

    assert_no_enqueued_jobs do
      assert_no_difference [ -> { Document.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count } ] do
        post dependent_documents_path(dependent), params: {
          document: { files: [ Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain", original_filename: "renamed.txt") ] }
        }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "is already saved in this profile"
    assert_equal original_attributes, original.reload.attributes
  end

  test "duplicates in a batch are rejected while unique files continue" do
    sign_in users(:family_admin)
    with_uploaded_files(
      { bytes: "same content", filename: "first.txt", content_type: "text/plain" },
      { bytes: "same content", filename: "renamed.txt", content_type: "text/plain" },
      { bytes: "different content", filename: "third.txt", content_type: "text/plain" }
    ) do |files|
      assert_enqueued_jobs 2, only: ProcessDocumentJob do
        assert_difference [ -> { Document.count }, -> { ActiveStorage::Blob.count } ], 2 do
          post dependent_documents_path(dependents(:emma)), params: { document: { files: files } }
        end
      end
    end

    assert_redirected_to dependent_documents_path(dependents(:emma))
    assert_equal "2 documents uploaded and being prepared.", flash[:notice]
    assert_includes flash[:alert], "renamed.txt: File is already saved in this profile"
    assert_not dependents(:emma).documents.exists?(original_filename: "renamed.txt")
  end

  test "allows identical filenames with different contents and identical content in another profile" do
    dependent = dependents(:emma)
    create_attached_document(dependent: dependent, title: "Original", category: "medical", filename: "record.txt")
    other_profile = Dependent.create!(account: accounts(:greenfield), first_name: "Another", last_name: "Profile")
    sign_in users(:family_admin)

    with_uploaded_files({ bytes: "different content", filename: "record.txt", content_type: "text/plain" }) do |files|
      assert_difference -> { dependent.documents.count } do
        post dependent_documents_path(dependent), params: { document: { files: files } }
      end
    end
    assert_redirected_to dependent_documents_path(dependent)

    assert_difference -> { other_profile.documents.count } do
      post dependent_documents_path(other_profile), params: {
        document: { files: [ Rack::Test::UploadedFile.new(file_fixture("sample.txt"), "text/plain", original_filename: "record.txt") ] }
      }
    end
    assert_redirected_to dependent_documents_path(other_profile)
  end

  test "duplicates are detected after supported image normalization" do
    sign_in users(:family_admin)
    with_uploaded_files(
      { bytes: test_image.write_to_buffer(".tiff"), filename: "photo.tiff", content_type: "image/tiff" },
      { bytes: test_image.write_to_buffer(".tiff"), filename: "renamed.tiff", content_type: "image/tiff" }
    ) do |files|
      assert_enqueued_jobs 1, only: ProcessImageDocumentJob do
        assert_difference -> { Document.count } do
          post dependent_documents_path(dependents(:emma)), params: { document: { files: files } }
        end
      end
    end

    assert_redirected_to dependent_documents_path(dependents(:emma))
    assert_includes flash[:alert], "renamed.tiff: File is already saved in this profile"
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
    assert_select "a[data-testid='document-back-to-documents'][data-tour='back-to-documents'][data-action='product-tour#advance'][data-product-tour-from-phase-param='open_ask'][data-product-tour-next-phase-param='open_ask']"

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

  test "initial metadata fields are locked until completion and title editing stays available" do
    document = create_attached_document(dependent: dependents(:emma), title: "Pending document", category: :general)
    document.update_column(:initial_metadata_pending, true)
    sign_in users(:family_admin)

    get edit_document_path(document)

    assert_response :success
    assert_select "fieldset[data-testid='document-editable-metadata'][disabled]"
    assert_select "input[data-testid='document-title-field']:not([disabled])"
    assert_select "[data-testid='document-metadata-pending']"

    patch document_path(document), params: {
      document: { category: "medical", description: "Too soon", initial_metadata_pending: false }
    }

    assert_response :unprocessable_entity
    assert document.reload.initial_metadata_pending?
    assert_equal "general", document.category
    assert_nil document.description

    patch document_path(document), params: { document: { title: "A clearer title" } }

    assert_redirected_to document_path(document)
    assert_equal "A clearer title", document.reload.title

    document.complete_initial_metadata!(category: "medical", description: "An automatically generated description.")
    get edit_document_path(document)

    assert_response :success
    assert_select "fieldset[data-testid='document-editable-metadata']:not([disabled])"
    assert_select "select[name='document[category]'] option[selected='selected'][value='medical']"
    assert_select "textarea[name='document[description]']", text: "An automatically generated description."
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

    def test_image
      @test_image ||= Vips::Image.black(12, 8, bands: 3) + [ 35, 90, 140 ]
    end

    def with_uploaded_files(*specifications)
      source_files = specifications.map do |specification|
        Tempfile.new([ "paper-bridge-controller-upload-", File.extname(specification.fetch(:filename)) ]).tap do |file|
          file.binmode
          file.write(specification.fetch(:bytes))
          file.rewind
        end
      end
      uploads = source_files.zip(specifications).map do |file, specification|
        Rack::Test::UploadedFile.new(
          file.path,
          specification.fetch(:content_type),
          original_filename: specification.fetch(:filename)
        )
      end

      yield uploads
    ensure
      uploads&.each(&:close)
      source_files&.each(&:close!)
    end
end
