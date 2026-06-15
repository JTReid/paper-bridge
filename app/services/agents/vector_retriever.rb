# frozen_string_literal: true

module Agents
  class VectorRetriever
    include PipelineNotifiable
    include Agentic::Instrumented

    attr_reader :data, :response

    def initialize(data = {})
      @data = data
    end

    def execute
      @response = {
        results: results,
        result_count: results.count,
        allowed_chunk_labels: access_profile.allowed_chunk_labels
      }

      data[:context][:search_results] = results

      log_activity(
        action: "search_results_retrieved",
        message: "Vector search results retrieved",
        metadata: {
          result_count: results.count,
          allowed_chunk_labels: access_profile.allowed_chunk_labels
        }
      )

      response
    end

    def step_started
      "Retrieving matching document chunks"
    end

    def step_complete
      "Matching document chunks retrieved"
    end

    private

      def results
        @results ||= Documents::VectorSearch.new(
          account: account,
          query_embedding: query_embedding,
          access_profile: access_profile,
          limit: limit
        ).call
      end

      def account
        @account ||= locate_context_record!(:account_gid, Account)
      end

      def query_embedding
        data.dig(:context, :query_embedding).tap do |embedding|
          raise Agentic::Errors::ConfigurationError, "context[:query_embedding] is required" if embedding.blank?
        end
      end

      def access_profile
        @access_profile ||= data.dig(:context, :access_profile) || Documents::SearchAccessProfile.new(role: nil)
      end

      def limit
        data.dig(:context, :limit).presence || Documents::VectorSearch::DEFAULT_LIMIT
      end

      def locate_context_record!(key, expected_class)
        gid = data.dig(:context, key)
        raise Agentic::Errors::ConfigurationError, "context[:#{key}] is required" if gid.blank?

        GlobalID::Locator.locate(gid).tap do |record|
          raise Agentic::Errors::ConfigurationError, "context[:#{key}] could not be resolved" unless record.is_a?(expected_class)
        end
      end
  end
end
