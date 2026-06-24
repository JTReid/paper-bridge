require "test_helper"

class ShareEventsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    post share_events_path, params: {
      share_event: {
        recipient_email: "recipient@example.test",
        document_ids: [ documents(:advance_directive).id ]
      }
    }

    assert_redirected_to new_user_session_path
  end

  test "shares selected account documents by email attachment" do
    document = documents(:advance_directive)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: document.content_type
    )
    sign_in users(:family_admin)

    assert_difference -> { ShareEvent.count }, 1 do
      assert_difference -> { SharedDocument.count }, 1 do
        assert_emails 1 do
          post share_events_path(dependent_id: document.dependent_id), params: {
            share_event: {
              recipient_email: "recipient@example.test",
              subject: "Please review",
              message: "Attached for review.",
              document_ids: [ document.id ]
            }
          }, headers: { "HTTP_REFERER" => dependent_documents_url(document.dependent) }
        end
      end
    end

    share_event = ShareEvent.order(:created_at).last
    email = ActionMailer::Base.deliveries.last

    assert_redirected_to dependent_documents_path(document.dependent)
    assert_equal "sent", share_event.status
    assert_equal accounts(:greenfield), share_event.account
    assert_equal users(:family_admin), share_event.sender
    assert_equal "recipient@example.test", share_event.recipient_email
    assert_equal [ document ], share_event.documents.to_a
    assert_equal [ "recipient@example.test" ], email.to
    assert_equal "Please review", email.subject
    assert_equal "advance-directive.txt", email.attachments.first.filename
  end

  test "ignores document ids outside the current account" do
    document = documents(:advance_directive)
    outside_document = documents(:outside_account)
    document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: document.original_filename,
      content_type: document.content_type
    )
    outside_document.file.attach(
      io: file_fixture("sample.txt").open,
      filename: outside_document.original_filename,
      content_type: outside_document.content_type
    )
    sign_in users(:family_admin)

    assert_emails 1 do
      post share_events_path(dependent_id: document.dependent_id), params: {
        share_event: {
          recipient_email: "recipient@example.test",
          document_ids: [ document.id, outside_document.id ]
        }
      }
    end

    share_event = ShareEvent.order(:created_at).last
    assert_equal [ document ], share_event.documents.to_a
  end

  test "does not create a share event without selected documents" do
    sign_in users(:family_admin)

    assert_no_difference -> { ShareEvent.count } do
      assert_no_emails do
        post share_events_path(dependent_id: dependents(:emma).id), params: {
          share_event: {
            recipient_email: "recipient@example.test",
            document_ids: []
          }
        }
      end
    end

    assert_redirected_to dependent_documents_path(dependents(:emma))
    assert_equal "Choose at least one document to share.", flash[:alert]
  end
end
