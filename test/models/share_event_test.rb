require "test_helper"

class ShareEventTest < ActiveSupport::TestCase
  test "requires the sender to belong to the account" do
    share_event = ShareEvent.new(
      account: accounts(:greenfield),
      sender: users(:other_user),
      recipient_email: "recipient@example.test"
    )

    assert_not share_event.valid?
    assert_includes share_event.errors[:sender], "must belong to the account"
  end

  test "requires a valid recipient email" do
    share_event = ShareEvent.new(
      account: accounts(:greenfield),
      sender: users(:family_admin),
      recipient_email: "not-an-email",
      status: :pending
    )

    assert_not share_event.valid?
    assert_includes share_event.errors[:recipient_email], "is invalid"
  end

  test "marks share events sent and failed" do
    share_event = share_events(:one)

    share_event.mark_failed!(StandardError.new("delivery failed"))
    assert_equal "failed", share_event.status
    assert_equal "delivery failed", share_event.error_message

    share_event.mark_sent!
    assert_equal "sent", share_event.status
    assert share_event.sent_at.present?
    assert_nil share_event.error_message
  end
end
