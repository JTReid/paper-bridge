require "test_helper"

class TimelineControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get timeline_path

    assert_redirected_to new_user_session_path
  end

  test "lists timeline events for the signed in account" do
    sign_in users(:family_admin)

    get timeline_path

    assert_response :success
    assert_includes response.body, "2023"
    assert_includes response.body, "Initial evaluation"
    assert_includes response.body, "Advance Directive"
    assert_includes response.body, "Page 1"
    assert_includes response.body, "Explicit"
    assert_includes response.body, "Source evidence"
  end

  test "does not list timeline events from another account" do
    create_outside_account_event!
    sign_in users(:family_admin)

    get timeline_path

    assert_response :success
    assert_not_includes response.body, "Outside appointment"
  end

  private

    def create_outside_account_event!
      document = documents(:outside_account)
      page = document.document_pages.create!(
        account: accounts(:other),
        page_number: 1,
        embedded_text: "Outside account page text",
        ocr_text: "",
        status: "processed"
      )
      content = "Outside appointment was scheduled on May 5, 2024."
      chunk = document.document_chunks.create!(
        account: accounts(:other),
        document_page: page,
        content: content,
        content_hash: DocumentChunk.content_hash_for(content),
        label: "medical",
        chunk_index: 1
      )

      chunk.timeline_events.create!(
        event_type: "service",
        title: "Outside appointment",
        description: "Outside appointment was scheduled.",
        occurred_on: Date.new(2024, 5, 5),
        date_precision: "exact",
        date_source: "explicit",
        source_quote: content,
        content_hash: TimelineEvent.content_hash_for(
          event_type: "service",
          title: "Outside appointment",
          description: "Outside appointment was scheduled.",
          occurred_on: Date.new(2024, 5, 5),
          started_on: nil,
          ended_on: nil
        )
      )
    end
end
