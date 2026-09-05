require "test_helper"

class DocumentsHelperTest < ActionView::TestCase
  include ApplicationHelper

  DocumentStub = Struct.new(:status, :content_type, :original_filename)

  test "defines a color for every document category" do
    assert_equal Document.categories.keys.sort, DocumentsHelper::DOCUMENT_CATEGORY_CLASSES.keys.sort
  end

  test "assigns a stable color to each document category" do
    assert_equal "bg-blue-50 text-blue-700", document_category_classes(:educational)
    assert_equal "bg-red-50 text-red-700", document_category_classes(:medical)
    assert_equal "bg-violet-50 text-violet-700", document_category_classes(:prescriptions)
    assert_equal "bg-green-50 text-green-700", document_category_classes(:therapy)
    assert_equal "bg-amber-50 text-amber-700", document_category_classes(:insurance)
    assert_equal "bg-slate-100 text-slate-700", document_category_classes(:general)
  end

  test "uses the general color for an unknown category" do
    assert_equal document_category_classes(:general), document_category_classes(:unknown)
  end

  test "defines a family-facing label for every document status" do
    assert_equal Document.statuses.keys.sort, DocumentsHelper::DOCUMENT_STATUS_LABELS.keys.sort
    assert_equal "Uploaded", document_status_label(DocumentStub.new("uploaded"))
    assert_equal "Getting ready", document_status_label(DocumentStub.new("queued"))
    assert_equal "Preparing", document_status_label(DocumentStub.new("processing"))
    assert_equal "Ready", document_status_label(DocumentStub.new("processed"))
    assert_equal "Stored—not processed", document_status_label(DocumentStub.new("stored"))
    assert_equal "Needs attention", document_status_label(DocumentStub.new("failed"))
  end

  test "defines a color for every document status and keeps stored files neutral" do
    assert_equal Document.statuses.keys.sort, DocumentsHelper::DOCUMENT_STATUS_CLASSES.keys.sort
    assert_equal "border-slate-200 bg-slate-100 text-slate-700", document_status_classes(DocumentStub.new("stored"))
  end

  test "describes file types without exposing MIME types" do
    assert_equal "PDF", document_file_type(DocumentStub.new(nil, "application/pdf", "record.pdf"))
    assert_equal "Text document", document_file_type(DocumentStub.new(nil, "text/plain", "notes.txt"))
    assert_equal "Image", document_file_type(DocumentStub.new(nil, "image/jpeg", "photo.jpg"))
    assert_equal "DOCX", document_file_type(DocumentStub.new(nil, "application/octet-stream", "plan.docx"))
  end

  test "processing stats describe customer outcomes instead of internal mechanics" do
    labels = document_processing_stats(documents(:advance_directive)).pluck(:label)

    assert_equal [ "Pages", "File size", "Summary", "Ask PaperBridge" ], labels
    assert_not_includes labels, "Chunks"
    assert_not_includes labels, "Embeddings"
  end

  test "stored files do not imply that a summary or answers are waiting or failed" do
    document = documents(:advance_directive)
    document.status = :stored
    stats = document_processing_stats(document).index_by { |stat| stat[:label] }

    assert_equal "Not supported", stats.fetch("Summary")[:value]
    assert_equal :unsupported, stats.fetch("Summary")[:state]
    assert_equal "Not supported", stats.fetch("Ask PaperBridge")[:value]
    assert_equal :unsupported, stats.fetch("Ask PaperBridge")[:state]
    assert_equal :unsupported, stats.fetch("Pages")[:state]
    assert_equal :complete, stats.fetch("File size")[:state]
  end

  test "unsupported stats have a neutral accessible indicator without a spinner" do
    markup = processing_stat_indicator(:unsupported, label: "Ask PaperBridge")

    assert_includes markup, 'aria-label="Ask PaperBridge not supported"'
    assert_includes markup, "bg-slate-100"
    assert_not_includes markup, "animate-spin"
    assert_not_includes markup, "unavailable"
  end
end
