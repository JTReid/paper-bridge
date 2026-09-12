require "test_helper"
require "action_cable/test_helper"

class DocumentListBroadcastTest < ActiveSupport::TestCase
  include ActionCable::TestHelper

  setup do
    @document = Document.new(account: accounts(:greenfield), dependent: dependents(:emma), user: users(:family_admin), title: "Private source title")
    @document.file.attach(io: StringIO.new("Synthetic document list broadcast test."), filename: "list.txt", content_type: "text/plain")
    @document.save!
    @stream = "#{@document.account.to_gid_param}:#{@document.dependent.to_gid_param}:documents"
  end

  test "status and category changes signal only this account and profile list" do
    [ { status: :processed }, { category: :medical }, { status: :failed } ].each do |attributes|
      messages = capture_broadcasts(@stream) { @document.update!(attributes) }

      assert_equal 1, messages.length
      assert_includes messages.sole, "target=\"documents_update_#{ActionView::RecordIdentifier.dom_id(@document.dependent)}\""
      assert_includes messages.sole, "data-document-list-target=\"update\""
      assert_not_includes messages.sole, @document.title
    end

    other_stream = "#{@document.account.to_gid_param}:#{dependents(:noah).to_gid_param}:documents"
    assert_no_broadcasts(other_stream) { @document.processing! }
  end

  test "description-only edits do not refresh the list" do
    assert_no_broadcasts(@stream) { @document.update!(description: "Revised description") }
  end

  test "rolled back processing changes do not signal the list" do
    assert_no_broadcasts(@stream) do
      Document.transaction(requires_new: true) do
        @document.processed!
        raise ActiveRecord::Rollback
      end
    end

    assert @document.reload.queued?
  end

  test "a list broadcast outage does not fail a committed document update" do
    original = @document.method(:broadcast_replace_to)
    replacement = lambda do |*streamables, **options|
      raise IOError, "Cable unavailable" if streamables.last == :documents

      original.call(*streamables, **options)
    end

    with_stubbed_singleton_method(@document, :broadcast_replace_to, replacement) { @document.processed! }

    assert @document.reload.processed?
  end
end
