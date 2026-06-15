# frozen_string_literal: true

module Agents
  class QueryEmbedder
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
        input: query,
        encoding_format: "float"
      }
    end

    def step_started
      "Embedding search query"
    end

    def step_complete
      "Search query embedded"
    end

    def setup_content
      @query = data.dig(:context, :query).to_s.strip
      @content = query

      raise Agentic::Errors::ConfigurationError, "context[:query] is required" if query.blank?
    end

    def agent_type_name
      "query_embedder"
    end

    def set_response
      embedding_row = provider.parse_response(raw_response).first
      raise Agentic::Errors::ExecutionError, "Embedding response did not include a query embedding" if embedding_row.blank?

      embedding = embedding_row.fetch("embedding")
      data[:context][:query_embedding] = embedding

      @response = {
        provider: DocumentEmbedding::PROVIDER,
        model: llm.name,
        dimensions: embedding.length,
        distance_metric: DocumentEmbedding::DISTANCE_METRIC
      }

      log_activity(
        action: "search_query_embedded",
        message: "Search query embedding created",
        metadata: response
      )
    end

    private

      attr_reader :query
  end
end
