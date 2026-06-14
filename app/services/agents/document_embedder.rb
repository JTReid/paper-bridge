# frozen_string_literal: true

module Agents
  class DocumentEmbedder
    include LocallyInteractable
    include PipelineNotifiable
    include Agentic::Instrumented

    def execute
      call
      set_response
      response
    end

    def operation_type
      :embeddings
    end

    def requirements
      {
        model: llm.name,
        input: chunks.map(&:content),
        encoding_format: "float"
      }
    end

    def step_started
      "Embedding document chunks"
    end

    def step_complete
      "Document chunks embedded"
    end

    def setup_content
      @document = locate_document!
      @chunks = document.document_chunks.order(:chunk_index).to_a
      @content = chunks.map(&:content).join("\n\n")

      raise Agentic::Errors::ConfigurationError, "Document has no chunks to embed" if chunks.empty?
    end

    def agent_type_name
      "document_embedder"
    end

    def set_response
      embedding_rows = provider.parse_response(raw_response).sort_by { |row| row.fetch("index") }
      raise Agentic::Errors::ExecutionError, "Embedding response count did not match chunk count" unless embedding_rows.length == chunks.length

      DocumentEmbedding.where(document_chunk: chunks).destroy_all

      created_embeddings = embedding_rows.zip(chunks).map do |embedding_row, chunk|
        chunk.document_embeddings.create!(
          provider: DocumentEmbedding::PROVIDER,
          model: llm.name,
          dimensions: DocumentEmbedding::DIMENSIONS,
          distance_metric: DocumentEmbedding::DISTANCE_METRIC,
          embedding: embedding_row.fetch("embedding")
        )
      end

      @response = {
        embedding_count: created_embeddings.count,
        embedding_ids: created_embeddings.map(&:id),
        provider: DocumentEmbedding::PROVIDER,
        model: llm.name,
        dimensions: DocumentEmbedding::DIMENSIONS,
        distance_metric: DocumentEmbedding::DISTANCE_METRIC
      }

      log_activity(
        action: "document_chunks_embedded",
        message: "Document chunk embeddings created",
        metadata: response
      )
    end

    private

      attr_reader :document, :chunks

      def locate_document!
        gid = data.dig(:context, :document_gid)
        raise Agentic::Errors::ConfigurationError, "context[:document_gid] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:document_gid] could not be resolved" unless record.is_a?(Document)
        end
      end
  end
end
