require "test_helper"

class SharedDocumentTest < ActiveSupport::TestCase
  test "requires the document to belong to the share account" do
    shared_document = SharedDocument.new(
      share_event: share_events(:one),
      document: documents(:outside_account)
    )

    assert_not shared_document.valid?
    assert_includes shared_document.errors[:document], "must belong to the share account"
  end
end
