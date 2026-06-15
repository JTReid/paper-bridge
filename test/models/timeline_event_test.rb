require "test_helper"

class TimelineEventTest < ActiveSupport::TestCase
  test "fixture is valid and belongs to a chunk" do
    event = timeline_events(:first_evaluation)

    assert_predicate event, :valid?
    assert_equal document_chunks(:one), event.document_chunk
    assert_equal documents(:advance_directive), event.document
    assert_equal accounts(:greenfield), event.account
  end

  test "requires a known event type" do
    event = timeline_events(:first_evaluation).dup
    event.event_type = "other"
    event.content_hash = "new-hash"

    assert_not event.valid?
    assert_includes event.errors[:event_type], "is not included in the list"
  end

  test "requires an ordered date range" do
    event = timeline_events(:first_evaluation).dup
    event.started_on = Date.new(2024, 1, 1)
    event.ended_on = Date.new(2023, 1, 1)
    event.content_hash = "new-hash"

    assert_not event.valid?
    assert_includes event.errors[:ended_on], "must be on or after the start date"
  end

  test "builds deterministic event hashes" do
    hash = TimelineEvent.content_hash_for(
      event_type: "diagnosis",
      title: "Autism Spectrum Disorder",
      description: "Diagnosis recorded.",
      occurred_on: "2023-07-21",
      started_on: nil,
      ended_on: nil
    )

    assert_equal hash, TimelineEvent.content_hash_for(
      event_type: "DIAGNOSIS",
      title: " Autism Spectrum Disorder ",
      description: "Diagnosis recorded.",
      occurred_on: "2023-07-21",
      started_on: nil,
      ended_on: nil
    )
  end
end
