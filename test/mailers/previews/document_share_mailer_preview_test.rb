require "test_helper"
require Rails.root.join("test/mailers/previews/document_share_mailer_preview")

class DocumentShareMailerPreviewTest < ActiveSupport::TestCase
  test "renders the document share preview" do
    email = DocumentShareMailerPreview.new.share

    assert email.to.present?
    assert email.subject.present?
    assert_includes email.body.encoded, "Original files are attached"
  end
end
