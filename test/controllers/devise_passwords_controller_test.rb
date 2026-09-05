require "test_helper"

class DevisePasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "password reset sends from PaperBridge and allows the password to change once" do
    user = users(:family_admin)

    assert_emails 1 do
      post user_password_path, params: { user: { email: user.email } }
    end
    assert_redirected_to new_user_session_path

    email = ActionMailer::Base.deliveries.last
    assert_equal [ ApplicationMailer::DEFAULT_FROM_ADDRESS ], email.from
    assert_equal email.from, email.reply_to
    assert_equal [ user.email ], email.to
    reset_url = Nokogiri::HTML(email.body.decoded).at_css("a")["href"]
    token = Rack::Utils.parse_query(URI.parse(reset_url).query).fetch("reset_password_token")

    get reset_url
    assert_response :success
    assert_select "input[name='user[reset_password_token]'][value='#{token}']"

    put user_password_path, params: {
      user: { reset_password_token: token, password: "updated-password", password_confirmation: "updated-password" }
    }
    assert_redirected_to dashboard_path
    assert user.reload.valid_password?("updated-password")
    assert_not user.valid_password?("password")

    sign_out user
    put user_password_path, params: {
      user: { reset_password_token: token, password: "another-password", password_confirmation: "another-password" }
    }
    assert_response :unprocessable_content
    assert user.reload.valid_password?("updated-password")
  end

  test "password reset uses the configured application sender" do
    credentials = Rails.application.credentials
    original_lookup = credentials.method(:[])
    lookup = ->(key) { key == :mailer_from ? "custom-sender@example.test" : original_lookup.call(key) }

    with_stubbed_singleton_method(credentials, :[], lookup) do
      assert_emails 1 do
        post user_password_path, params: { user: { email: users(:family_admin).email } }
      end
    end

    email = ActionMailer::Base.deliveries.last
    assert_equal [ "custom-sender@example.test" ], email.from
    assert_equal email.from, email.reply_to
  end

  test "unknown email does not send reset instructions" do
    assert_no_emails do
      post user_password_path, params: { user: { email: "missing@example.test" } }
    end

    assert_response :unprocessable_content
  end

  test "expired password reset token cannot change the password" do
    user = users(:family_admin)
    token = user.send_reset_password_instructions
    user.update!(reset_password_sent_at: (User.reset_password_within + 1.minute).ago)

    put user_password_path, params: {
      user: { reset_password_token: token, password: "updated-password", password_confirmation: "updated-password" }
    }

    assert_response :unprocessable_content
    assert user.reload.valid_password?("password")
  end
end
