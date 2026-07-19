require "test_helper"

class AppointmentMailerTest < ActionMailer::TestCase
  test "shares appointment details in Central Time" do
    appointment = Appointment.create!(
      dependent: dependents(:emma),
      scheduled_at: Time.utc(2026, 7, 25, 16, 30),
      description: "Annual checkup. Bring the current medication list."
    )

    email = AppointmentMailer.with(
      appointment: appointment,
      recipient_email: "caregiver@example.test"
    ).share

    assert_equal [ ApplicationMailer::DEFAULT_FROM_ADDRESS ], email.from
    assert_equal [ "caregiver@example.test" ], email.to
    assert_equal "PaperBridge: Appointment for Emma Greenfield", email.subject

    [ email.html_part.body.decoded, email.text_part.body.decoded ].each do |body|
      assert_includes body, "Emma Greenfield"
      assert_includes body, "Saturday, July 25, 2026 at 11:30 AM CDT"
      assert_includes body, "Annual checkup. Bring the current medication list."
    end
  end
end
