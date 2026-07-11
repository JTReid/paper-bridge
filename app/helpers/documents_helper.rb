module DocumentsHelper
  DOCUMENT_CATEGORY_CLASSES = {
    "educational" => "bg-blue-50 text-blue-700",
    "medical" => "bg-red-50 text-red-700",
    "therapy" => "bg-green-50 text-green-700",
    "insurance" => "bg-amber-50 text-amber-700",
    "general" => "bg-slate-100 text-slate-700"
  }.freeze

  DOCUMENT_STATUS_LABELS = {
    "uploaded" => "Uploaded",
    "queued" => "Getting ready",
    "processing" => "Preparing",
    "processed" => "Ready",
    "failed" => "Needs attention"
  }.freeze

  DOCUMENT_STATUS_CLASSES = {
    "uploaded" => "border-slate-200 bg-slate-100 text-slate-700",
    "queued" => "border-amber-200 bg-amber-50 text-amber-800",
    "processing" => "border-sky-200 bg-sky-50 text-sky-800",
    "processed" => "border-emerald-200 bg-emerald-50 text-emerald-800",
    "failed" => "border-red-200 bg-red-50 text-red-800"
  }.freeze

  def document_category_classes(category)
    DOCUMENT_CATEGORY_CLASSES.fetch(category.to_s, DOCUMENT_CATEGORY_CLASSES.fetch("general"))
  end

  def document_status_label(document)
    DOCUMENT_STATUS_LABELS.fetch(document.status, "Getting ready")
  end

  def document_status_classes(document)
    DOCUMENT_STATUS_CLASSES.fetch(document.status, DOCUMENT_STATUS_CLASSES.fetch("uploaded"))
  end

  def document_file_type(document)
    return "PDF" if document.content_type == "application/pdf"
    return "Text document" if document.content_type == "text/plain"
    return "Image" if document.content_type.to_s.start_with?("image/")

    File.extname(document.original_filename.to_s).delete_prefix(".").upcase.presence || "File"
  end

  def document_processing_stats(document)
    chunk_count = document.document_chunks.count
    embedding_count = document.document_embeddings.count
    page_count = document.document_pages.count

    [
      { label: "Pages", value: page_count.positive? ? page_count : "—", state: page_state(document, page_count) },
      { label: "File size", value: document.byte_size ? number_to_human_size(document.byte_size) : "—", state: document.byte_size.present? ? :complete : :idle },
      { label: "Summary", value: readiness_label(summary_state(document)), state: summary_state(document) },
      { label: "Ask PaperBridge", value: readiness_label(question_state(document, chunk_count, embedding_count)), state: question_state(document, chunk_count, embedding_count) }
    ]
  end

  def processing_stat_indicator(state, label:)
    case state.to_sym
    when :complete
      stat_indicator("check", "#{label} ready", "bg-emerald-50 text-emerald-700 ring-emerald-200")
    when :failed
      stat_indicator("x", "#{label} unavailable", "bg-red-50 text-red-700 ring-red-200")
    when :working
      content_tag(
        :span,
        content_tag(:span, "", class: "block h-3 w-3 animate-spin rounded-full border-2 border-sky-200 border-t-sky-700"),
        class: "inline-flex h-5 w-5 items-center justify-center rounded-full bg-sky-50 ring-1 ring-sky-200",
        role: "status",
        title: "Getting #{label.downcase} ready",
        aria: { label: "Getting #{label.downcase} ready" }
      )
    end
  end

  private

    def page_state(document, page_count)
      return :failed if document.failed? || document.preparation_failed?
      return :complete if document.prepared? && page_count.positive?
      return :working if processing_active?(document)

      :idle
    end

    def question_state(document, chunk_count, embedding_count)
      return :failed if document.failed? || document.preparation_failed?
      return :complete if chunk_count.positive? && embedding_count >= chunk_count
      return :working if processing_active?(document)

      :idle
    end

    def summary_state(document)
      return :failed if document.failed? || document.preparation_failed?
      return :complete if document.summarized_at.present?
      return :working if processing_active?(document)

      :idle
    end

    def readiness_label(state)
      {
        complete: "Ready",
        failed: "Unavailable",
        working: "Getting ready",
        idle: "Not ready"
      }.fetch(state)
    end

    def processing_active?(document)
      document.queued? || document.processing? || document.preparing?
    end

    def stat_indicator(icon, label, classes)
      content_tag(
        :span,
        pb_icon(icon, class_name: "h-3 w-3"),
        class: "inline-flex h-5 w-5 items-center justify-center rounded-full ring-1 #{classes}",
        role: "img",
        title: label,
        aria: { label: label }
      )
    end
end
