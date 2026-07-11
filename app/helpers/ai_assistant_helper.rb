module AiAssistantHelper
  SOURCE_MARKER = /\[(\d+(?:\s*,\s*\d+)*)\]/

  def ai_answer_with_source_links(answer, citations:, documents_by_id:)
    sources_by_number = Array(citations).index_by { |citation| citation[:source_number].to_i }
    paragraphs = answer.to_s.split(/\n{2,}/)

    safe_join(
      paragraphs.map do |paragraph|
        lines = paragraph.split("\n", -1)
        content_tag(:p, safe_join(lines.map { |line| linked_answer_line(line, sources_by_number, documents_by_id) }, tag.br))
      end,
      "\n"
    )
  end

  def ai_source_link(citation, documents_by_id:, label: nil, class_name: nil, testid: nil)
    destination = ai_source_destination(citation, documents_by_id: documents_by_id)
    return label || ai_source_label(citation) unless destination

    link_to(
      label || ai_source_label(citation),
      destination,
      target: "_blank",
      rel: "noopener",
      class: class_name,
      aria: { label: "Open source #{citation[:source_number]}: #{ai_source_label(citation)} in a new tab" },
      data: { testid: testid }.compact
    )
  end

  def ai_source_label(citation)
    [ citation[:document_title], citation[:page_number].present? ? "page #{citation[:page_number]}" : nil ].compact.join(", ")
  end

  private

    def linked_answer_line(line, sources_by_number, documents_by_id)
      fragments = []
      cursor = 0

      while (match = SOURCE_MARKER.match(line, cursor))
        fragments << line[cursor...match.begin(0)]
        source_numbers = match[1].split(",").map(&:to_i).uniq
        links = source_numbers.filter_map do |source_number|
          source = sources_by_number[source_number]
          next unless source

          ai_source_link(
            source,
            documents_by_id: documents_by_id,
            label: "[#{source_number}]",
            class_name: "font-semibold text-primary underline decoration-primary/30 underline-offset-2 hover:decoration-primary",
            testid: "ai-inline-source-#{source_number}"
          )
        end
        fragments << safe_join(links, " ")
        cursor = match.end(0)
      end

      fragments << line[cursor..]
      safe_join(fragments)
    end

    def ai_source_destination(citation, documents_by_id:)
      document = documents_by_id[citation[:document_id].to_i]
      return unless document

      if document.content_type == "application/pdf" && document.file.attached?
        page_number = citation[:page_number].to_i
        original_document_path(
          document,
          page: page_number.positive? ? page_number : nil
        )
      else
        document_path(document)
      end
    end
end
