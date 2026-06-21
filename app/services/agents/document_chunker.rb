# frozen_string_literal: true

require "base64"

module Agents
  class DocumentChunker
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    def execute
      document.document_chunks.destroy_all
      broadcast_chunk_progress

      created_chunks = document_pages.flat_map do |page|
        create_chunks_for_page(page, chunk_page(page))
      end

      @response = {
        chunk_count: created_chunks.count,
        chunk_ids: created_chunks.map(&:id)
      }

      log_activity(
        action: "document_chunked",
        message: "Document chunks created",
        metadata: response
      )

      response
    end

    def requirements
      requirements_for(document_pages.first)
    end

    def step_started
      "Chunking prepared document pages"
    end

    def step_complete
      "Document chunks created"
    end

    def setup_content
      @document = locate_document!
      validate_prepared_document!
      @content = document_pages.map { |page| page_text(page) }.join("\n\n").strip

      raise Agentic::Errors::ConfigurationError, "Prepared document did not contain pages to chunk" if document_pages.empty?
    end

    def agent_type_name
      "document_chunker"
    end

    private

      attr_reader :document

      def locate_document!
        gid = data.dig(:context, :document_gid)
        raise Agentic::Errors::ConfigurationError, "context[:document_gid] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:document_gid] could not be resolved" unless record.is_a?(Document)
        end
      end

      def validate_prepared_document!
        raise Agentic::Errors::ConfigurationError, "Document file is missing" unless document.file.attached?
        raise Agentic::Errors::ConfigurationError, "Document has not been prepared" unless document.prepared?
      end

      def document_pages
        @document_pages ||= document.document_pages.includes(image_attachment: :blob).order(:page_number).to_a
      end

      def chunk_page(page)
        provider = @provider_klass.new(
          connection: connection,
          operation_type: :chat,
          requirements: requirements_for(page)
        )

        raw = provider.call
        log_llm_event(
          "Document page chunking completed",
          provider.llm_metadata.merge(
            status: "completed",
            document_page_id: page.id,
            page_number: page.page_number
          )
        )

        JSON.parse(provider.parse_response(raw)).with_indifferent_access
      rescue StandardError => e
        log_llm_event(
          "Document page chunking failed",
          provider.failure_metadata(e).merge(document_page_id: page.id, page_number: page.page_number)
        ) if provider
        raise
      end

      def requirements_for(page)
        {
          model: llm.name,
          system: prompt.system_directive,
          prompt: page_prompt(page),
          max_tokens: 4_000,
          timeout: 120,
          response_format: "structured_json",
          schema_name: "document_chunks"
        }
      end

      def page_prompt(page)
        blocks = [
          {
            type: "text",
            text: page_window_text(page)
          }
        ]

        page_window(page).each do |window_page|
          blocks << {
            type: "text",
            text: "#{window_label(page, window_page)} page screenshot follows."
          }

          image_content = page_image_content(window_page)
          blocks << image_content if image_content.present?
        end

        blocks
      end

      def page_window_text(page)
        <<~TEXT
          Document title: #{document.title}
          Original filename: #{document.original_filename}
          Content type: #{document.content_type}

          You are chunking the CURRENT page for search indexing.
          Use the previous and next pages only to preserve continuity.
          Return chunks whose content starts on the CURRENT page.
          Chunks may include continuation text from the next page when needed for coherence.
          Keep headings with their body. Merge tiny fragments into useful chunks.
          Use exactly one label per chunk: #{DocumentChunk::LABELS.join(", ")}.

          #{page_window(page).map { |window_page| page_window_entry(page, window_page) }.join("\n\n")}
        TEXT
      end

      def page_window(page)
        index = document_pages.index(page)
        document_pages[[ index - 1, 0 ].max..[ index + 1, document_pages.length - 1 ].min]
      end

      def page_window_entry(current_page, window_page)
        <<~TEXT.strip
          #{window_label(current_page, window_page)} PAGE #{window_page.page_number}
          #{page_text(window_page)}
        TEXT
      end

      def window_label(current_page, window_page)
        return "CURRENT" if current_page.id == window_page.id
        return "PREVIOUS" if window_page.page_number < current_page.page_number

        "NEXT"
      end

      def page_text(page)
        <<~TEXT.strip
          Embedded text:
          #{page.embedded_text}

          OCR text:
          #{page.ocr_text}
        TEXT
      end

      def page_image_content(page)
        return unless page.image.attached?

        {
          type: "image_url",
          image_url: {
            url: image_data_url(page),
            detail: "auto"
          }
        }
      end

      def image_data_url(page)
        content_type = page.image.blob.content_type.presence || "image/png"
        base64 = Base64.strict_encode64(page.image.download)

        "data:#{content_type};base64,#{base64}"
      end

      def create_chunks_for_page(page, parsed_response)
        created_chunks = Array(parsed_response[:chunks]).filter_map do |chunk_data|
          create_chunk(page, chunk_data)
        end

        broadcast_chunk_progress if created_chunks.any?

        created_chunks
      end

      def create_chunk(page, chunk_data)
        normalized_content = DocumentChunk.normalize_content(chunk_data[:content])
        return if normalized_content.blank?

        content_hash = DocumentChunk.content_hash_for(normalized_content)
        return if document.document_chunks.exists?(content_hash: content_hash)

        document.document_chunks.create!(
          account: document.account,
          document_page: page,
          content: normalized_content,
          content_hash: content_hash,
          label: normalized_label(chunk_data[:label]),
          chunk_index: next_chunk_index
        )
      end

      def normalized_label(label)
        label = label.to_s
        return label if DocumentChunk::LABELS.include?(label)

        "general"
      end

      def next_chunk_index
        @next_chunk_index ||= 0
        @next_chunk_index += 1
      end

      def broadcast_chunk_progress
        document.broadcast_processing_stats_update
        document.broadcast_chunks_update
      end
  end
end
