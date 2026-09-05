# frozen_string_literal: true

require "base64"

module Agents
  class ImageDocumentExtractor
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    def execute
      call
      set_response
      response
    end

    def requirements
      {
        model: llm.name,
        system: prompt.system_directive,
        prompt: extraction_prompt,
        max_tokens: 6_000,
        timeout: 180,
        response_format: "structured_json",
        schema_name: "image_document_extraction"
      }
    end

    def step_started
      "Extracting image document text and search content"
    end

    def step_complete
      "Image document extracted and classified"
    end

    def setup_content
      @document = locate_document!
      @page = document.document_pages.includes(image_attachment: :blob).find_by!(page_number: 1)

      validate_image_document!
      @content = "Image document #{document.original_filename}"
    end

    def agent_type_name
      "image_document_extractor"
    end

    def set_response
      parsed = JSON.parse(provider.parse_response(raw_response)).with_indifferent_access
      extracted_text = DocumentChunk.normalize_content(parsed[:extracted_text])
      detected_category = normalized_category(parsed[:category])
      key_points = Array(parsed[:key_points]).filter_map { |point| point.to_s.squish.presence }
      chunks = normalized_chunks(parsed[:search_chunks], fallback_text: extracted_text)
      extracted_text = DocumentChunk.normalize_content(chunks.map { |chunk| chunk.fetch(:content) }.join("\n\n")) if extracted_text.blank?

      raise Agentic::Errors::ConfigurationError, "Image extraction did not produce searchable text" if extracted_text.blank? || chunks.empty?

      created_chunks = persist_extraction!(
        extracted_text: extracted_text,
        detected_category: detected_category,
        category: parsed[:category],
        description: parsed[:description],
        summary: parsed[:summary].to_s.squish,
        key_points: key_points,
        chunks: chunks
      )

      @response = {
        extracted_text: extracted_text,
        detected_category: detected_category,
        summary: parsed[:summary].to_s.squish,
        key_points: key_points,
        search_chunks: created_chunks.map { |chunk| { content: chunk.content, label: chunk.label } },
        chunk_count: created_chunks.count,
        chunk_ids: created_chunks.map(&:id)
      }

      log_activity(
        action: "image_document_extracted",
        message: "Image document text, classification, and search chunks created",
        metadata: response.except(:extracted_text, :search_chunks)
      )
    end

    private

      attr_reader :document, :page

      def locate_document!
        gid = data.dig(:context, :document_gid)
        raise Agentic::Errors::ConfigurationError, "context[:document_gid] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:document_gid] could not be resolved" unless record.is_a?(Document)
        end
      end

      def validate_image_document!
        raise Agentic::Errors::ConfigurationError, "Document has not been prepared" unless document.prepared?
        raise Agentic::Errors::ConfigurationError, "Prepared image page is missing" unless page.image.attached?
        return if page.image.blob.content_type.to_s.start_with?("image/")

        raise Agentic::Errors::ConfigurationError, "Prepared page attachment is not an image"
      end

      def extraction_prompt
        [
          {
            type: "text",
            text: <<~PROMPT
              Extract as much visible text as possible from this uploaded image document, including printed and handwritten text.
              Preserve uncertainty instead of guessing; use [illegible] where text cannot be read reliably.
              Create a concise caregiver-facing summary and key points grounded only in the image.
              #{Documents::MetadataSchemas::INSTRUCTIONS}
              Create coherent search chunks containing the useful extracted facts and wording.
              Each chunk must use exactly one search label: #{DocumentChunk::LABELS.join(", ")}.

              Document title: #{document.title}
              Original filename: #{document.original_filename}
              Uploaded content type: #{document.content_type}
            PROMPT
          },
          image_prompt_block
        ]
      end

      def image_prompt_block
        encoded = Base64.strict_encode64(page.image.download)
        content_type = page.image.blob.content_type.presence || "image/jpeg"

        if @provider_klass == Agentic::Providers::Anthropic
          {
            type: "image",
            source: {
              type: "base64",
              media_type: content_type,
              data: encoded
            }
          }
        else
          {
            type: "image_url",
            image_url: {
              url: "data:#{content_type};base64,#{encoded}",
              detail: "high"
            }
          }
        end
      end

      def normalized_category(category)
        value = category.to_s
        return value if Document.categories.key?(value)

        "general"
      end

      def normalized_chunks(raw_chunks, fallback_text:)
        chunks = Array(raw_chunks).filter_map do |chunk|
          chunk = chunk.with_indifferent_access
          content = DocumentChunk.normalize_content(chunk[:content])
          next if content.blank?

          {
            content: content,
            label: normalized_label(chunk[:label])
          }
        end

        if chunks.empty? && fallback_text.present?
          chunks << {
            content: fallback_text,
            label: "general"
          }
        end

        chunks.uniq { |chunk| DocumentChunk.content_hash_for(chunk[:content]) }
      end

      def normalized_label(label)
        value = label.to_s
        return value if DocumentChunk::LABELS.include?(value)

        "general"
      end

      def persist_extraction!(extracted_text:, detected_category:, category:, description:, summary:, key_points:, chunks:)
        created_chunks = []

        Document.transaction do
          document.complete_initial_metadata!(category: category, description: description)
          document.document_chunks.destroy_all

          page.update!(
            ocr_text: extracted_text,
            metadata: page.metadata.merge(
              "source" => "image_document_extractor",
              "model" => llm.name,
              "detected_category" => detected_category
            ),
            status: :processed
          )

          chunks.each_with_index do |chunk, index|
            created_chunks << document.document_chunks.create!(
              account: document.account,
              document_page: page,
              content: chunk.fetch(:content),
              content_hash: DocumentChunk.content_hash_for(chunk.fetch(:content)),
              label: chunk.fetch(:label),
              chunk_index: index + 1
            )
          end

          document.update!(
            prepared_payload: extracted_payload(extracted_text, detected_category),
            summary: {
              summary: summary,
              key_points: key_points,
              metadata: {
                source: "image_document_extractor",
                model: llm.name,
                chunk_count: created_chunks.count,
                detected_category: detected_category
              }
            },
            summarized_at: Time.current
          )
        end

        document.broadcast_processing_stats_update
        created_chunks
      end

      def extracted_payload(extracted_text, detected_category)
        document.prepared_payload.to_h.deep_merge(
          "full_text" => extracted_text,
          "extracted_text" => extracted_text,
          "classification" => {
            "detected_category" => detected_category,
            "source" => "image_document_extractor",
            "model" => llm.name
          },
          "pages" => [
            {
              "id" => page.id,
              "number" => page.page_number,
              "embedded_text" => "",
              "ocr_text" => extracted_text,
              "image_attached" => page.image.attached?,
              "image_blob_id" => page.image.blob_id,
              "metadata" => page.metadata.merge(
                "source" => "image_document_extractor",
                "model" => llm.name,
                "detected_category" => detected_category
              )
            }
          ]
        )
      end
  end
end
