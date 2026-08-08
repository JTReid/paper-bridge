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

  test "creates an appointment for another profile without losing the family calendar context" do
    calendar_context = dependents(:emma)
    appointment_dependent = dependents(:noah)
    sign_in users(:family_admin)

    assert_difference -> { appointment_dependent.appointments.count }, 1 do
      post appointments_path(calendar_context_id: calendar_context.id, panel: 1), params: {
        appointment: {
          dependent_id: appointment_dependent.id,
          scheduled_at: "2030-08-05T09:15",
          description: "Panel occupational therapy"
        }
      }, headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }
    end

    assert_response :see_other
    assert_redirected_to calendar_path(month: "2030-08", calendar_context_id: calendar_context.id, panel: 1)
    created_appointment = appointment_dependent.appointments.find_by!(description: "Panel occupational therapy")
    assert_equal appointment_dependent, created_appointment.dependent
  end

  test "renders panel appointment errors without losing its profile context" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    assert_no_difference -> { Appointment.count } do
      post appointments_path(calendar_context_id: dependent.id, panel: 1), params: {
        month: "2030-07",
        appointment: {
          dependent_id: dependent.id,
          scheduled_at: "2030-07-23T11:00",
          description: ""
        }
      }, headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }
    end

    assert_response :unprocessable_entity
    assert_select "turbo-frame##{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}"
    assert_select "[data-testid='appointment-errors']", text: /Description can.t be blank/
    assert_select "select[data-testid='appointment-dependent'] option[selected][value='#{dependent.id}']"
    assert_select "form[data-testid='appointment-form'][action='#{appointments_path(calendar_context_id: dependent.id, panel: 1)}']"
  end

  test "does not accept a family calendar context from another account" do
    sign_in users(:family_admin)

    assert_no_difference -> { Appointment.count } do
      post appointments_path(calendar_context_id: dependents(:other_dependent).id, panel: 1), params: {
        appointment: {
          dependent_id: dependents(:emma).id,
          scheduled_at: "2030-08-05T09:15",
          description: "Unauthorized panel appointment"
        }
      }, headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }
    end

    assert_response :not_found
  end
end
