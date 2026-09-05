require "base64"
require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "defines document categories in family-facing order" do
    assert_equal %w[educational medical prescriptions therapy insurance general], Document.categories.keys
  end

  test "belongs to an account and has one attached file" do
    document = build_document

    assert document.valid?
    assert document.file.attached?
  end

  test "requires an attached file" do
    document = Document.new(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: users(:family_admin),
      title: "Trust"
    )

    assert_not document.valid?
    assert_includes document.errors[:file], "must be attached"
  end

  test "caches file metadata" do
    document = build_document(title: nil)
    document.validate

    assert_equal "sample", document.title
    assert_equal "sample.txt", document.original_filename
    assert_equal "text/plain", document.content_type
    assert_equal file_fixture("sample.txt").size, document.byte_size
  end

  test "does not default blank title on persisted documents" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: "sample.txt",
      content_type: "text/plain"
    )

    document.title = ""

    assert_not document.valid?
    assert_includes document.errors[:title], "can't be blank"
  end

  test "requires document account to match uploading user account" do
    document = build_document(account: accounts(:other))

    assert_not document.valid?
    assert_includes document.errors[:account], "must be manageable by the uploading user"
  end

  test "requires document account to match dependent account" do
    document = build_document(dependent: dependents(:other_dependent))

    assert_not document.valid?
    assert_includes document.errors[:account], "must match the dependent"
  end

  test "queues processing after create commit" do
    document = build_document

    assert_enqueued_with(job: ProcessDocumentJob) do
      document.save!
    end

    assert_equal "queued", document.reload.status
  end

  test "queues image processing after an image document is created" do
    document = Document.new(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: users(:family_admin),
      title: "Prescription photo",
      category: :general,
      file: {
        io: StringIO.new(one_by_one_png),
        filename: "prescription.png",
        content_type: "image/png"
      }
    )

    assert_enqueued_with(job: ProcessImageDocumentJob) do
      document.save!
    end

    assert_equal "queued", document.reload.status
  end

  test "stores non-processable files without waiting for metadata or enqueueing ingestion" do
    document = build_document
    document.initial_metadata_pending = true
    document.file.attach(
      io: StringIO.new("original Word document bytes"), filename: "record.docx",
      content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", identify: false,
      metadata: { analyzed: true }
    )

    assert_no_enqueued_jobs do
      document.save!
    end

    assert document.reload.stored?
    assert_not document.processable?
    assert_not document.initial_metadata_pending?
    assert_nil document.description
    assert_equal "general", document.category
    assert document.update(category: "educational", description: "School notes")
    assert_not document.complete_initial_metadata!(category: "medical", description: "Unwanted automatic result")
    assert_equal "educational", document.reload.category
    assert_equal "School notes", document.description
    assert_empty document.pipeline_runs
  end

  test "every currently supported text format still queues ingestion" do
    { "text/plain" => "txt", "text/csv" => "csv", "text/markdown" => "md", "application/json" => "json" }.each do |content_type, extension|
      document = build_document
      document.initial_metadata_pending = true
      document.file.attach(io: StringIO.new("Source #{extension}"), filename: "record.#{extension}", content_type: content_type, identify: false)

      assert_enqueued_with(job: ProcessDocumentJob) { document.save! }

      assert document.reload.processable?, content_type
      assert document.queued?, content_type
      assert document.initial_metadata_pending?, content_type
    end
  end

  test "searches original filenames case insensitively by partial match" do
    assert_equal [ documents(:advance_directive) ], Document.search_by_filename("DIRECT").to_a
  end

  test "treats SQL wildcard characters as literal filename search text" do
    assert_empty Document.search_by_filename("%")
    assert_empty Document.search_by_filename("_")
  end

  test "initial metadata is completed once and never replaces later edits" do
    document = build_document
    document.initial_metadata_pending = true
    document.save!
    stale_document = Document.find(document.id)

    assert document.complete_initial_metadata!(category: "medical", description: "  Initial description.  ")
    assert_not document.reload.initial_metadata_pending?
    assert_equal "medical", document.category
    assert_equal "Initial description.", document.description

    document.update!(category: "therapy", description: "Family correction.")

    assert_not stale_document.complete_initial_metadata!(category: "insurance", description: "Retried description.")
    assert_equal "therapy", document.reload.category
    assert_equal "Family correction.", document.description
  end

  test "existing documents are not opted into initial metadata generation" do
    document = build_document
    document.description = "Original description"
    document.save!

    assert_not document.initial_metadata_pending?
    assert_not document.complete_initial_metadata!(category: "medical", description: "Generated description")
    assert_equal "general", document.reload.category
    assert_equal "Original description", document.description
  end

  test "initial metadata accepts every supported category" do
    Document.categories.each_key do |category|
      document = build_document
      document.initial_metadata_pending = true
      document.save!

      document.complete_initial_metadata!(category: category, description: "A description of this document.")

      assert_equal category, document.reload.category
      assert_not document.initial_metadata_pending?
    end
  end

  test "invalid initial metadata stays pending and does not save a partial result" do
    document = build_document
    document.initial_metadata_pending = true
    document.save!

    [ [ nil, "Description" ], [ "unknown", "Description" ], [ "medical", "  " ], [ "medical", [ "Description" ] ] ].each do |category, description|
      assert_raises(ArgumentError) do
        document.complete_initial_metadata!(category: category, description: description)
      end

      assert document.reload.initial_metadata_pending?
      assert_equal "general", document.category
      assert_nil document.description
    end
  end

  test "pending metadata cannot be edited but the document title can" do
    document = build_document
    document.initial_metadata_pending = true
    document.save!

    assert document.update(title: "New title")
    assert_not document.update(category: "medical", description: "Premature change")
    assert_includes document.errors[:base], "Category and description can be edited after initial document processing finishes."
    assert_equal "general", document.reload.category
    assert_nil document.description
  end

  private

    def build_document(account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin), title: "Trust")
      Document.new(
        account: account,
        dependent: dependent,
        user: user,
        title: title,
        category: :general,
        file: {
          io: file_fixture("sample.txt").open,
          filename: "sample.txt",
          content_type: "text/plain"
        }
      )
    end

    def one_by_one_png
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
      )
    end
end
