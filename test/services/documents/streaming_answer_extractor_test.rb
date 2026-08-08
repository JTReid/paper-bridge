require "test_helper"

class Documents::StreamingAnswerExtractorTest < ActiveSupport::TestCase
  test "returns progressive answer snapshots and stops at the answer field" do
    extractor = Documents::StreamingAnswerExtractor.new

    assert_nil extractor.feed('{"ans')
    assert_equal "Hello ", extractor.feed('wer":"Hello ')
    assert_equal "Hello world", extractor.feed("world")
    assert_equal "Hello world!", extractor.feed('!","citations":[]')
    assert_predicate extractor, :complete?
    assert_nil extractor.feed(',"limitations":[]}')
  end

  test "decodes split JSON escapes without exposing incomplete escape sequences" do
    extractor = Documents::StreamingAnswerExtractor.new

    assert_equal "A ", extractor.feed('{"answer":"A \\')
    assert_equal "A \"quote", extractor.feed('"quote')
    assert_equal "A \"quote\"", extractor.feed('\\"\\')
    assert_equal "A \"quote\"\n and ", extractor.feed("n and \\u2")
    assert_equal "A \"quote\"\n and ☺", extractor.feed('63A","citations":[]')
    assert_predicate extractor, :complete?
  end

  test "decodes a surrogate pair split across deltas" do
    extractor = Documents::StreamingAnswerExtractor.new

    assert_equal "Smile: ", extractor.feed('{"answer":"Smile: \\uD83D')
    assert_equal "Smile: 😀", extractor.feed('\\uDE00","citations":[]')
    assert_predicate extractor, :complete?
  end

  test "does not publish another escape after an incomplete high surrogate" do
    extractor = Documents::StreamingAnswerExtractor.new

    assert_equal "Smile: ", extractor.feed('{"answer":"Smile: \\uD83D')
    assert_raises(JSON::ParserError) { extractor.feed('\\n') }
    assert_equal "Smile: ", extractor.answer
  end

  test "rejects invalid escapes" do
    extractor = Documents::StreamingAnswerExtractor.new

    error = assert_raises(JSON::ParserError) do
      extractor.feed('{"answer":"Bad \\x')
    end

    assert_equal "Invalid escape in streamed answer", error.message
  end

  test "does not stream a nested or out-of-order answer field" do
    extractor = Documents::StreamingAnswerExtractor.new

    assert_nil extractor.feed('{"metadata":{"answer":"Wrong"},')
    assert_nil extractor.feed('"answer":"Right","citations":[]}')
    assert_equal "", extractor.answer
    assert_not_predicate extractor, :complete?
  end
end
