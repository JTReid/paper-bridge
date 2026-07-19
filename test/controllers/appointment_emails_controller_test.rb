require "test_helper"

class AppointmentEmailsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    post appointment_emails_path, params: appointment_email_params

    assert_redirected_to new_user_session_path
  end

  test "emails an appointment from the current account" do
    appointment = appointments(:emma_therapy)
    recipient_email = "caregiver@example.test"
    sign_in users(:family_admin)

    assert_emails 1 do
      post appointment_emails_path, params: {
        appointment_email: {
          appointment_id: appointment.id,
          recipient_email: recipient_email
        }
      }
    end

    email = ActionMailer::Base.deliveries.last

    assert_redirected_to calendar_path(month: appointment.scheduled_at.in_time_zone.strftime("%Y-%m"))
    assert_equal "Appointment emailed to #{recipient_email}.", flash[:notice]
    assert_equal [ recipient_email ], email.to
  end

  test "requires a recipient email" do
    sign_in users(:family_admin)

    assert_no_emails do
      post appointment_emails_path, params: appointment_email_params(recipient_email: "  ")
    end

    assert_redirected_to calendar_path(month: appointment_month)
    assert_equal "Enter an email address.", flash[:alert]
  end

  test "requires a valid recipient email" do
    sign_in users(:family_admin)

    assert_no_emails do
      post appointment_emails_path, params: appointment_email_params(recipient_email: "not-an-email")
    end

    assert_redirected_to calendar_path(month: appointment_month)
    assert_equal "Enter a valid email address.", flash[:alert]
  end

  test "does not email an appointment from another account" do
    outside_appointment = Appointment.create!(
      dependent: dependents(:other_dependent),
      scheduled_at: Time.zone.local(2030, 8, 5, 9, 15),
      description: "Outside appointment"
    )
    sign_in users(:family_admin)

    assert_no_emails do
      post appointment_emails_path, params: appointment_email_params(appointment_id: outside_appointment.id)
    end

    assert_response :not_found
  end

  test "shows a safe alert and logs context when delivery fails" do
    appointment = appointments(:emma_therapy)
    sign_in users(:family_admin)
    failing_delivery = Class.new do
      def share
        self
      end

      def deliver_now
        raise StandardError, "SES delivery rejected\nprivate detail"
      end
    end.new
    logged_message = nil

    with_stubbed_singleton_method(AppointmentMailer, :with, failing_delivery) do
      with_stubbed_singleton_method(Rails.logger, :error, ->(message) { logged_message = message }) do
        assert_no_emails do
          post appointment_emails_path, params: appointment_email_params
        end
      end
    end

    assert_redirected_to calendar_path(month: appointment_month)
    assert_equal "Appointment could not be emailed.", flash[:alert]
    assert_includes logged_message, "appointment_email_delivery_failed"
    assert_includes logged_message, "appointment_id=#{appointment.id}"
    assert_includes logged_message, "account_id=#{accounts(:greenfield).id}"
    assert_includes logged_message, "error_class=StandardError"
    assert_includes logged_message, "error_message=SES delivery rejected private detail"
  end

  private

    def appointment_email_params(appointment_id: appointments(:emma_therapy).id, recipient_email: "caregiver@example.test")
      {
        appointment_email: {
          appointment_id: appointment_id,
          recipient_email: recipient_email
        }
      }
    end

    def appointment_month
      appointments(:emma_therapy).scheduled_at.in_time_zone.strftime("%Y-%m")
    end
end
