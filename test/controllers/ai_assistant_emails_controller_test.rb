require "test_helper"

class AiAssistantEmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @dependent = dependents(:emma)
    @user = users(:family_admin)
    @query = create_query
    sign_in @user
  end

  test "requires authentication for the form and delivery" do
    sign_out @user

    assert_no_emails do
      get new_dependent_ai_assistant_email_path(@dependent, @query)
      assert_redirected_to new_user_session_path

      post dependent_ai_assistant_email_path(@dependent, @query), params: email_params
      assert_redirected_to new_user_session_path
    end
  end

  test "requires an active subscription for the form and delivery" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)

    assert_no_emails do
      get new_dependent_ai_assistant_email_path(@dependent, @query)
      assert_redirected_to billing_path

      post dependent_ai_assistant_email_path(@dependent, @query), params: email_params
      assert_redirected_to billing_path
    end
  end

  test "requires a current account" do
    user_without_account = User.create!(name: "No account", email: "no-account@example.test", password: "password")
    sign_in user_without_account

    assert_no_emails do
      get new_dependent_ai_assistant_email_path(@dependent, @query)
      assert_redirected_to root_path

      post dependent_ai_assistant_email_path(@dependent, @query), params: email_params
      assert_redirected_to root_path
    end
  end

  test "form offers an editable email and only this profile's care team contacts" do
    other_profile_contact = create_contact(dependent: dependents(:noah), email: "noah-contact@example.test")
    other_account_contact = create_contact(
      account: accounts(:other), dependent: dependents(:other_dependent), invited_by: users(:other_user),
      email: "outside-contact@example.test"
    )

    assert_no_emails do
      get new_dependent_ai_assistant_email_path(@dependent, @query), headers: frame_headers
    end

    assert_response :success
    assert_select "turbo-frame#ai_assistant_email dialog"
    assert_select "form[action='#{dependent_ai_assistant_email_path(@dependent, @query)}'][method='post']" do
      assert_select "input[type='email'][name='ai_assistant_email[recipient_email]']"
      assert_select "textarea[name='ai_assistant_email[message]']"
      assert_select "select option[value='#{care_team_memberships(:emma_therapist).email}']"
      assert_select "select option[value='#{other_profile_contact.email}']", count: 0
      assert_select "select option[value='#{other_account_contact.email}']", count: 0
    end
  end

  test "a profile without care team contacts can still enter any email address" do
    query = create_query(dependent: dependents(:noah))

    get new_dependent_ai_assistant_email_path(query.dependent, query), headers: frame_headers

    assert_response :success
    assert_select "input[type='email'][name='ai_assistant_email[recipient_email]']"
    assert_select "select", count: 0
  end

  test "query and profile must belong to the current user and account for both endpoints" do
    targets = [
      [ @dependent, create_query(user: users(:account_member)) ],
      [ @dependent, create_query(dependent: dependents(:noah)) ],
      [ dependents(:noah), @query ],
      [ dependents(:other_dependent), create_query(
        account: accounts(:other), dependent: dependents(:other_dependent), user: users(:other_user)
      ) ]
    ]

    targets.each do |dependent, query|
      assert_no_emails do
        sign_in @user
        get new_dependent_ai_assistant_email_path(dependent, query), headers: frame_headers
        assert_response :not_found

        sign_in @user
        post dependent_ai_assistant_email_path(dependent, query), params: email_params, headers: frame_headers
        assert_response :not_found
      end
    end
  end

  test "drafts failed queries and completed queries without answer text cannot be emailed" do
    queries = %i[queued processing failed].map do |state|
      create_query(state: state, draft_answer: "This answer is not final")
    end
    [ {}, { answer: "   " }, { answer: nil }, { answer: [ "Invalid answer" ] }, [ "Invalid payload" ] ].each do |answer|
      queries << create_query(answer: answer)
    end

    queries.each do |query|
      assert_no_emails do
        sign_in @user
        get new_dependent_ai_assistant_email_path(@dependent, query), headers: frame_headers
        assert_response :not_found

        sign_in @user
        post dependent_ai_assistant_email_path(@dependent, query), params: email_params, headers: frame_headers
        assert_response :not_found
      end
    end
  end

  test "emails the persisted response to an arbitrary address without creating or changing records or jobs" do
    original_query = @query.attributes

    assert_no_difference [ "AiAssistantQuery.count", "SavedAnswer.count", "PipelineRun.count", "ShareEvent.count" ] do
      assert_no_enqueued_jobs do
        assert_emails 1 do
          post dependent_ai_assistant_email_path(@dependent, @query),
            params: email_params(recipient_email: "  advocate@example.test  ", message: "  Please review before our meeting.  "),
            headers: frame_headers
        end
      end
    end

    assert_response :success
    assert_select "turbo-frame#ai_assistant_email", text: /Answer emailed to advocate@example\.test\./
    email = ActionMailer::Base.deliveries.last
    assert_equal [ "advocate@example.test" ], email.to
    assert_equal [ @user.email ], email.reply_to
    assert_includes email.text_part.body.decoded, @query.question
    assert_includes email.text_part.body.decoded, @query.answer.fetch("answer")
    assert_includes email.text_part.body.decoded, "Please review before our meeting."
    assert_not_includes email.text_part.body.decoded, "  Please review before our meeting.  "
    assert_empty email.attachments
    assert_equal original_query, @query.reload.attributes
  end

  test "emails to a care team contact using the same recipient field without requiring a frame request" do
    recipient = care_team_memberships(:emma_therapist).email

    assert_emails 1 do
      post dependent_ai_assistant_email_path(@dependent, @query), params: email_params(recipient_email: recipient)
    end

    assert_response :success
    assert_select "turbo-frame#ai_assistant_email", text: /Answer emailed to #{Regexp.escape(recipient)}\./
    assert_equal [ recipient ], ActionMailer::Base.deliveries.last.to
  end

  test "ignores forged query answer sender and document parameters" do
    unrelated_query = create_query(question: "Unrelated private question", answer: { answer: "Unrelated private answer" })
    params = email_params.merge(ai_assistant_query_id: unrelated_query.id)
    params[:ai_assistant_email].merge!(
      ai_assistant_query_id: unrelated_query.id, question: "Forged question", answer: "Forged answer",
      sender_id: users(:other_user).id, from: "forged@example.test", reply_to: "forged@example.test",
      document_ids: [ documents(:advance_directive).id ], cc: "copied@example.test", bcc: "hidden@example.test"
    )

    assert_emails 1 do
      post dependent_ai_assistant_email_path(@dependent, @query), params: params, headers: frame_headers
    end

    assert_response :success
    email = ActionMailer::Base.deliveries.last
    assert_equal [ "recipient@example.test" ], email.to
    assert_equal [ @user.email ], email.reply_to
    assert_not_includes email.from, "forged@example.test"
    assert_nil email.cc
    assert_nil email.bcc
    assert_empty email.attachments
    assert_includes email.text_part.body.decoded, @query.question
    assert_includes email.text_part.body.decoded, @query.answer.fetch("answer")
    assert_not_includes email.text_part.body.decoded, unrelated_query.question
    assert_not_includes email.text_part.body.decoded, "Forged answer"
  end

  test "a missing or blank recipient cannot send and preserves the message" do
    [ nil, "   " ].each do |recipient|
      assert_no_emails do
        post dependent_ai_assistant_email_path(@dependent, @query),
          params: email_params(recipient_email: recipient, message: "Please keep this message."), headers: frame_headers
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "Enter an email address."
      assert_select "textarea[name='ai_assistant_email[message]']", text: "Please keep this message."
    end
  end

  test "rejects malformed multiple and header injection recipients" do
    [
      "not-an-email",
      "first@example.test,second@example.test",
      "first@example.test;second@example.test",
      "Recipient <recipient@example.test>",
      "recipient@example.test\r\nBcc: hidden@example.test",
      "recipient@example.test\n",
      "\rrecipient@example.test"
    ].each do |recipient|
      assert_no_emails do
        post dependent_ai_assistant_email_path(@dependent, @query),
          params: email_params(recipient_email: recipient, message: "Keep these notes."), headers: frame_headers
      end

      assert_response :unprocessable_entity
      assert_includes response.body, "Enter a valid email address."
      assert_select "textarea[name='ai_assistant_email[message]']", text: "Keep these notes."
    end
  end

  test "delivery failure keeps the recipient and message available to retry without exposing server details" do
    failing_delivery = Class.new do
      def share
        self
      end

      def deliver_now
        raise Net::SMTPFatalError, "550 SMTP private provider rejection"
      end
    end.new

    with_stubbed_singleton_method(AiAssistantQueryMailer, :with, failing_delivery) do
      assert_no_emails do
        post dependent_ai_assistant_email_path(@dependent, @query),
          params: email_params(recipient_email: "caregiver@example.test", message: "Keep this <important> note."),
          headers: frame_headers
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Answer could not be emailed. Please try again."
    assert_not_includes response.body, "SMTP private provider rejection"
    assert_select "input[name='ai_assistant_email[recipient_email]'][value='caregiver@example.test']"
    assert_select "textarea[name='ai_assistant_email[message]']", text: "Keep this <important> note."
    assert_select "textarea important", count: 0
  end

  private

    def create_query(attributes = {})
      AiAssistantQuery.create!({
        account: accounts(:greenfield), dependent: @dependent, user: @user,
        question: "What support was recommended?", state: :completed, completed_at: Time.current,
        answer: { answer: "Use visual supports [1].", limitations: [ "Limited to the uploaded records." ], citations: [
          { source_number: 1, document_id: documents(:advance_directive).id,
            document_title: "Evaluation report", page_number: 2, quote: "Teacher observations" }
        ] }
      }.merge(attributes))
    end

    def create_contact(attributes = {})
      CareTeamMembership.create!({
        account: accounts(:greenfield), dependent: @dependent, invited_by: @user,
        name: "Other contact", email: "contact@example.test", role: :teacher
      }.merge(attributes))
    end

    def email_params(recipient_email: "recipient@example.test", message: "")
      { ai_assistant_email: { recipient_email: recipient_email, message: message } }
    end

    def frame_headers
      { "Turbo-Frame" => "ai_assistant_email" }
    end
end
