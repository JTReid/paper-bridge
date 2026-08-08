require "test_helper"

class Agentic::Providers::SseParserTest < ActiveSupport::TestCase
  test "parses complete events across arbitrary network chunks" do
    events = []
    parser = Agentic::Providers::SseParser.new { |event| events << event }

    parser.feed("data: first\r\n")
    parser.feed("data: sec")
    parser.feed("ond\r\n\r")
    parser.feed("\n: keepalive\n\ndata: [DO")
    parser.feed("NE]\n\n")
    parser.finish

    assert_equal [ "first\nsecond", "[DONE]" ], events
  end

  test "dispatches the last event when the connection closes without a blank line" do
    events = []
    parser = Agentic::Providers::SseParser.new { |event| events << event }

    parser.feed("event: message\ndata: final")
    parser.finish

    assert_equal [ "final" ], events
  end
end
