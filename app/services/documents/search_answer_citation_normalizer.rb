# frozen_string_literal: true

module Documents
  class SearchAnswerCitationNormalizer
    CITATION_MARKER = /\[(\d+(?:\s*,\s*\d+)*)\]/
    EXCERPT_LENGTH = 420

    def initialize(response:, search_results:)
      @response = response.deep_symbolize_keys
      @search_results = Array(search_results)
    end

    def call
      sources, source_number_by_reference = build_sources

      response.merge(
        answer: normalize_answer(response[:answer], source_number_by_reference),
        citations: sources
      )
    end

    private

      attr_reader :response, :search_results

      def build_sources
        sources = []
        source_by_document_page = {}
        source_number_by_reference = {}

        ordered_source_references.each do |source_reference|
          result = result_for(source_reference)
          next unless valid_result?(result)

          key = [ result.document.id, result.page.page_number ]
          source = source_by_document_page[key]

          unless source
            source = canonical_source(result, source_number: sources.length + 1)
            source_by_document_page[key] = source
            sources << source
          end

          source_number_by_reference[source_reference] = source[:source_number]
        end

        [ sources, source_number_by_reference ]
      end

      def ordered_source_references
        (answer_source_references + structured_source_references).uniq
      end

      def answer_source_references
        response[:answer].to_s.scan(CITATION_MARKER).flatten.flat_map do |references|
          references.split(",").filter_map { |value| positive_integer(value) }
        end
      end

      def structured_source_references
        Array(response[:citations]).filter_map do |citation|
          next unless citation.respond_to?(:to_h)

          positive_integer(citation.to_h.with_indifferent_access[:chunk_id])
        end
      end

      def positive_integer(value)
        integer = Integer(value, exception: false)
        integer if integer&.positive?
      end

      def result_for(source_reference)
        search_results[source_reference - 1]
      end

      def valid_result?(result)
        return false unless result&.chunk && result.document && result.page
        return false unless result.chunk.document_id == result.document.id
        return false unless result.page.document_id == result.document.id

        result.page.page_number.to_i.positive?
      end

      def canonical_source(result, source_number:)
        {
          source_number: source_number,
          document_id: result.document.id,
          document_title: result.document.title,
          page_number: result.page.page_number,
          quote: result.chunk.content.to_s.squish.truncate(EXCERPT_LENGTH, omission: "…")
        }
      end

      def normalize_answer(answer, source_number_by_reference)
        answer.to_s.gsub(CITATION_MARKER) do
          source_numbers = Regexp.last_match(1).split(",").filter_map do |value|
            source_reference = positive_integer(value)
            source_number_by_reference[source_reference]
          end.uniq

          source_numbers.any? ? "[#{source_numbers.join(", ")}]" : ""
        end.gsub(/[ \t]+([,.;:!?])/, "\\1").gsub(/[ \t]{2,}/, " ")
      end
  end
end
