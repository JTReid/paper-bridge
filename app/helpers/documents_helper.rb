module DocumentsHelper
  def document_processing_stats(document)
    chunk_count = document.document_chunks.count
    embedding_count = document.document_embeddings.count
    page_count = document.document_pages.count

    [
      { label: "Chunks", value: chunk_count, state: chunk_state(document, chunk_count, embedding_count) },
      { label: "Embeddings", value: embedding_count, state: embedding_state(document, chunk_count, embedding_count) },
      { label: "Pages", value: page_count, state: page_state(document, page_count) },
      { label: "Size", value: document.byte_size ? number_to_human_size(document.byte_size) : "Unknown", state: document.byte_size.present? ? :complete : :idle }
    ]
  end

  def processing_stat_indicator(state, label:)
    case state.to_sym
    when :complete
      stat_indicator("check", "#{label} ready", "bg-emerald-50 text-emerald-700 ring-emerald-200")
    when :failed
      stat_indicator("x", "#{label} failed", "bg-red-50 text-red-700 ring-red-200")
    when :working
      content_tag(
        :span,
        content_tag(:span, "", class: "block h-3 w-3 animate-spin rounded-full border-2 border-sky-200 border-t-sky-700"),
        class: "inline-flex h-5 w-5 items-center justify-center rounded-full bg-sky-50 ring-1 ring-sky-200",
        role: "status",
        title: "Working on #{label.downcase}",
        aria: { label: "Working on #{label.downcase}" }
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

    def chunk_state(document, chunk_count, embedding_count)
      return :failed if document.failed? || document.preparation_failed?
      return :complete if chunk_count.positive? && (embedding_count.positive? || document.processed?)
      return :working if processing_active?(document)

      :idle
    end

    def embedding_state(document, chunk_count, embedding_count)
      return :failed if document.failed? || document.preparation_failed?
      return :complete if embedding_count.positive? && embedding_count >= chunk_count
      return :working if processing_active?(document)

      :idle
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
