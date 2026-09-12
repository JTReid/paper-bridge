require "test_helper"

class DocumentShareMailerTest < ActionMailer::TestCase
  test "shares selected documents as email attachments" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: document.content_type
    )
    share_event = share_events(:one)

    email = DocumentShareMailer.with(share_event: share_event).share

    assert_equal [ ApplicationMailer::DEFAULT_FROM_ADDRESS ], email.from
    assert_equal [ "teacher@example.test" ], email.to
    assert_equal "Shared documents", email.subject
    assert_includes email.text_part.body.to_s, "Original files are attached"
    assert_includes email.text_part.body.to_s, document.title
    assert_equal 1, email.attachments.count
    assert_equal "advance-directive.txt", email.attachments.first.filename
  end

  test "keeps duplicate attachment filenames unique" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: "shared-name.txt",
      content_type: document.content_type
    )
    document.save!
    second_document = Document.new(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: users(:family_admin),
      title: "Duplicate Filename",
      category: :general
    )
    second_document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: "shared-name.txt",
      content_type: "text/plain"
    )
    second_document.save!
    share_event = share_events(:one)
    share_event.documents << second_document

    email = DocumentShareMailer.with(share_event: share_event).share

    assert_equal [ "shared-name.txt", "shared-name-2.txt" ], email.attachments.map(&:filename)
  end

  test "shares an available summary and the original despite unfinished overall processing" do
    document = documents(:advance_directive)
    document.file.attach(io: StringIO.new("Original evidence"), filename: "original.txt", content_type: "text/plain")

    %i[failed queued processing].each do |status|
      document.update!(status: status, summary: { summary: "Successfully generated summary" }, summarized_at: 1.hour.ago)

      email = DocumentShareMailer.with(share_event: share_events(:one)).share

      assert_includes email.html_part.body.decoded, "Successfully generated summary", status
      assert_includes email.text_part.body.decoded, "Successfully generated summary", status
      assert_equal "Original evidence", email.attachments.sole.body.decoded, status
    end
  end
end
