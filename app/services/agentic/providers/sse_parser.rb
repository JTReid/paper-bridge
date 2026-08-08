# frozen_string_literal: true

module Agentic
  module Providers
    class SseParser
      def initialize(&on_event)
        @on_event = on_event
        @buffer = String.new(encoding: Encoding::BINARY)
        @data_lines = []
      end

      def feed(chunk)
        buffer << chunk.to_s.b

        while (newline_index = buffer.index("\n".b))
          raw_line = buffer.slice!(0, newline_index + 1)
          process_line(normalize_line(raw_line))
        end

        self
      end

      def finish
        process_line(normalize_line(buffer.slice!(0, buffer.bytesize))) unless buffer.empty?
        dispatch_event
        self
      end

      private

        attr_reader :buffer, :data_lines, :on_event

        def normalize_line(raw_line)
          line = raw_line.delete_suffix("\n".b).delete_suffix("\r".b)
          line.force_encoding(Encoding::UTF_8)
        end

        def process_line(line)
          if line.empty?
            dispatch_event
            return
          end

          return if line.start_with?(":")

          field, value = line.split(":", 2)
          return unless field == "data"

          data_lines << value.to_s.delete_prefix(" ")
        end

        def dispatch_event
          return if data_lines.empty?

          data = data_lines.join("\n")
          data_lines.clear
          on_event&.call(data)
        end
    end
  end
end
