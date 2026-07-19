require "test_helper"

class AppointmentsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    post appointments_path, params: {
      appointment: {
        dependent_id: dependents(:emma).id,
        scheduled_at: "2030-08-05T09:15",
        description: "Occupational therapy"
      }
    }

    assert_redirected_to new_user_session_path
  end

  test "creates an appointment for a profile in the current account" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_difference -> { dependent.appointments.count }, 1 do
      post appointments_path, params: {
        appointment: {
          dependent_id: dependent.id,
          scheduled_at: "2030-08-05T09:15",
          description: "Occupational therapy"
        }
      }
    end

    appointment = dependent.appointments.order(:created_at).last
    assert_redirected_to calendar_path(month: "2030-08")
    assert_equal Time.zone.local(2030, 8, 5, 9, 15), appointment.scheduled_at
    assert_equal "Occupational therapy", appointment.description
    assert_equal "Appointment added.", flash[:notice]
  end

  test "renders the calendar form with errors when an appointment is invalid" do
    sign_in users(:family_admin)

    assert_no_difference -> { Appointment.count } do
      post appointments_path, params: {
        month: "2030-07",
        appointment: {
          dependent_id: dependents(:emma).id,
          scheduled_at: "2030-07-23T11:00",
          description: ""
        }
      }
    end

    assert_response :unprocessable_entity
    assert_select "[data-testid='calendar-page']"
    assert_select "h2", text: "July 2030"
    assert_select "[data-testid='appointment-errors']", text: /Description can.t be blank/
    assert_select "select[data-testid='appointment-dependent'] option[selected][value='#{dependents(:emma).id}']"
  end

  test "does not create an appointment for a profile in another account" do
    sign_in users(:family_admin)

    assert_no_difference -> { Appointment.count } do
      post appointments_path, params: {
        appointment: {
          dependent_id: dependents(:other_dependent).id,
          scheduled_at: "2030-08-05T09:15",
          description: "Unauthorized appointment"
        }
      }
    end

    assert_response :not_found
  end
end
