# frozen_string_literal: true

module Documents
  class StreamingAnswerExtractor
    ANSWER_PREFIX = /\A\s*\{\s*"answer"\s*:\s*"/
    ESCAPES = {
      '"' => '"',
      "\\" => "\\",
      "/" => "/",
      "b" => "\b",
      "f" => "\f",
      "n" => "\n",
      "r" => "\r",
      "t" => "\t"
    }.freeze

    attr_reader :answer

    def initialize
      @prefix_buffer = +""
      @answer = +""
      @started = false
      @complete = false
      @escaped = false
      @unicode_digits = nil
      @pending_high_surrogate = nil
    end

    def feed(content_delta)
      return if complete?

      content = content_after_prefix(content_delta.to_s)
      return if content.nil?

      changed = consume_answer_content(content)
      answer.dup if changed
    end

    def complete?
      @complete
    end

    private

      attr_reader :prefix_buffer

      def content_after_prefix(content_delta)
        return content_delta if @started

        prefix_buffer << content_delta
        match = ANSWER_PREFIX.match(prefix_buffer)
        return unless match

        @started = true
        prefix_buffer.slice!(match.end(0)..)
      end

      def consume_answer_content(content)
        changed = false

        content.each_char do |character|
          break if complete?

          if @unicode_digits
            changed = consume_unicode_digit(character) || changed
          elsif @escaped
            changed = consume_escape(character) || changed
          elsif character == "\\"
            @escaped = true
          elsif character == '"'
            raise JSON::ParserError, "Incomplete Unicode surrogate in streamed answer" if @pending_high_surrogate

            @complete = true
          else
            raise JSON::ParserError, "Incomplete Unicode surrogate in streamed answer" if @pending_high_surrogate

            answer << character
            changed = true
          end
        end

        changed
      end

      def consume_escape(character)
        @escaped = false

        if @pending_high_surrogate && character != "u"
          raise JSON::ParserError, "Invalid Unicode surrogate in streamed answer"
        end

        if character == "u"
          @unicode_digits = +""
          return false
        end

        decoded = ESCAPES[character]
        raise JSON::ParserError, "Invalid escape in streamed answer" unless decoded

        answer << decoded
        true
      end

      def consume_unicode_digit(character)
        unless character.match?(/\A[0-9a-fA-F]\z/)
          raise JSON::ParserError, "Invalid Unicode escape in streamed answer"
        end

        @unicode_digits << character
        return false if @unicode_digits.length < 4

        codepoint = @unicode_digits.to_i(16)
        @unicode_digits = nil
        append_codepoint(codepoint)
      end

      def append_codepoint(codepoint)
        if codepoint.between?(0xD800, 0xDBFF)
          raise JSON::ParserError, "Invalid Unicode surrogate in streamed answer" if @pending_high_surrogate

          @pending_high_surrogate = codepoint
          return false
        end

        if codepoint.between?(0xDC00, 0xDFFF)
          raise JSON::ParserError, "Invalid Unicode surrogate in streamed answer" unless @pending_high_surrogate

          high = @pending_high_surrogate
          @pending_high_surrogate = nil
          codepoint = 0x10000 + ((high - 0xD800) << 10) + (codepoint - 0xDC00)
        elsif @pending_high_surrogate
          raise JSON::ParserError, "Invalid Unicode surrogate in streamed answer"
        end

        answer << [ codepoint ].pack("U")
        true
      end
  end
end
