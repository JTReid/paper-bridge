require "test_helper"

class AiAssistantQueryMailerTest < ActionMailer::TestCase
  test "shares the complete stored answer with source labels and a reply address" do
    query = create_query
    original = query.attributes.deep_dup
    email = nil

    assert_no_enqueued_jobs do
      assert_no_difference [ "AiAssistantQuery.count", "SavedAnswer.count", "PipelineRun.count" ] do
        email = AiAssistantQueryMailer.with(
          query: query, recipient_email: "caregiver@example.test", message: "For our meeting.\nPlease review the support plan."
        ).share
        email.message
      end
    end

    assert_equal [ ApplicationMailer.default_from_address ], email.from
    assert_equal [ "caregiver@example.test" ], email.to
    assert_equal [ query.user.email ], email.reply_to
    assert_equal "PaperBridge: Answer for Emma Greenfield", email.subject
    assert_empty email.attachments

    html = email.html_part.body.decoded
    text = email.text_part.body.decoded
    [ html, text ].each do |body|
      assert_includes body, query.user.name
      assert_includes body, "Emma Greenfield"
      assert_includes body, "September 11, 2026"
      assert_includes body, query.question
      assert_includes body, "Use visual supports [1, 2]."
      assert_includes body, "Practice each morning."
      assert_includes body, "Ask the teacher to track progress."
      assert_includes body, "For our meeting."
      assert_includes body, "Please review the support plan."
      assert_includes body, "[1] IEP Progress Summary, page 3"
      assert_includes body, "[2] Teacher Notes"
      assert_includes body, "Only the spring report is available."
      assert_includes body, "This AI-generated answer is for informational purposes only and is not professional advice."
      assert_not_includes body, "A private source excerpt."
      assert_not_includes body, "https://private.example.test/record"
      assert_not_includes body, "/documents/"
    end
    assert_includes text, query.answer["answer"]
    assert_includes html, "supports [1, 2].\n<br />Practice"
    assert_empty Nokogiri::HTML(html).css("a")
    assert_equal original, query.reload.attributes
  end

  test "escapes user and generated HTML while retaining readable text" do
    query = create_query(
      question: "What does <strong>support</strong> mean?",
      answer: {
        answer: "<script>alert('answer')</script>\nUse <strong>visual</strong> cues.",
        citations: [ { source_number: 1, document_title: "<img src=x onerror=alert('source')>", page_number: "<b>3</b>" } ],
        limitations: [ "<iframe>Limited context</iframe>" ]
      }
    )
    message = "<a href='https://example.test'>Review this</a>\nThank you."
    email = AiAssistantQueryMailer.with(query: query, recipient_email: "caregiver@example.test", message: message).share
    html = email.html_part.body.decoded
    body = Nokogiri::HTML(html)

    assert_empty body.css("script, img, a, iframe, strong, b")
    assert_includes body.text, query.question
    assert_includes body.text, "<script>alert('answer')</script>"
    assert_includes body.text, "Use <strong>visual</strong> cues."
    assert_includes body.text, "<img src=x onerror=alert('source')>"
    assert_includes body.text, "page <b>3</b>"
    assert_includes body.text, "<iframe>Limited context</iframe>"
    assert_includes body.text, "<a href='https://example.test'>Review this</a>"
    assert_includes html, "&lt;script&gt;"
    assert_includes email.text_part.body.decoded, query.answer["answer"]
    assert_includes email.text_part.body.decoded, message
  end

  test "omits absent optional content and falls back to the query update date" do
    query = create_query(answer: { answer: "A complete answer without sources." }, completed_at: nil)
    email = AiAssistantQueryMailer.with(query: query, recipient_email: "caregiver@example.test").share

    [ email.html_part.body.decoded, email.text_part.body.decoded ].each do |body|
      assert_includes body, "A complete answer without sources."
      assert_includes body, I18n.l(query.updated_at.to_date, format: :long)
      assert_not_includes body, "Sources"
      assert_not_includes body, "Things to keep in mind"
    end
    assert_empty email.attachments
  end

  private

    def create_query(**attributes)
      AiAssistantQuery.create!({
        account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin),
        question: "What support should we discuss?", state: :completed, completed_at: Time.utc(2026, 9, 11, 15),
        answer: {
          answer: "Use visual supports [1, 2].\nPractice each morning.\n\nAsk the teacher to track progress.",
          citations: [
            {
              source_number: 1, document_id: documents(:advance_directive).id,
              document_title: "IEP Progress Summary", page_number: 3,
              quote: "A private source excerpt.", url: "https://private.example.test/record"
            },
            { source_number: 2, document_title: "Teacher Notes" }
          ],
          limitations: [ "Only the spring report is available." ]
        }
      }.merge(attributes))
    end
end
