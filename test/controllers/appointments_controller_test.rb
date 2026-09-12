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

  %i[patch delete].each do |request_method|
    test "#{request_method} requires authentication before changing an appointment" do
      appointment = create_appointment
      before = appointment.attributes

      public_send request_method, appointment_path(appointment), params: { appointment: valid_edit_attributes }

      assert_redirected_to new_user_session_path
      assert_equal before, appointment.reload.attributes
    end

    test "#{request_method} requires a family account" do
      appointment = create_appointment
      before = appointment.attributes
      sign_in users(:super_admin)

      public_send request_method, appointment_path(appointment), params: { appointment: valid_edit_attributes }

      assert_redirected_to admin_accounts_path
      assert_equal before, appointment.reload.attributes
    end

    test "#{request_method} does not change another account's appointment" do
      appointment = create_appointment(dependent: dependents(:other_dependent))
      before = appointment.attributes
      sign_in users(:family_admin)

      public_send request_method, appointment_path(appointment), params: { appointment: valid_edit_attributes }

      assert_response :not_found
      assert_equal before, appointment.reload.attributes
    end

    test "#{request_method} rejects another account's calendar context" do
      appointment = create_appointment
      before = appointment.attributes
      sign_in users(:family_admin)

      public_send request_method,
        appointment_path(appointment, calendar_context_id: dependents(:other_dependent).id, panel: 1),
        params: { appointment: valid_edit_attributes },
        headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }

      assert_response :not_found
      assert_equal before, appointment.reload.attributes
    end

    test "#{request_method} returns not found when an appointment was already removed" do
      appointment = create_appointment
      appointment.destroy!
      sign_in users(:family_admin)

      public_send request_method, appointment_path(appointment), params: { appointment: valid_edit_attributes }

      assert_response :not_found
    end
  end

  test "updates and reassigns an appointment within the account then opens its new month" do
    appointment = create_appointment
    sign_in users(:family_admin)

    assert_no_difference -> { Appointment.count } do
      patch appointment_path(appointment), params: {
        month: "2030-07", appointment: valid_edit_attributes.merge(account_id: accounts(:other).id)
      }
    end

    assert_response :see_other
    assert_redirected_to calendar_path(month: "2030-08")
    assert_equal "Appointment updated.", flash[:notice]
    assert_equal dependents(:noah), appointment.reload.dependent
    assert_equal accounts(:greenfield), appointment.account
    assert_equal Time.zone.local(2030, 8, 5, 9, 15), appointment.scheduled_at
    assert_equal "Rescheduled occupational therapy", appointment.description
  end

  test "an account member can update an appointment through the family calendar panel" do
    appointment = create_appointment
    context = dependents(:emma)
    sign_in users(:account_member)

    patch appointment_path(appointment, calendar_context_id: context.id, panel: 1), params: {
      month: "2030-07", appointment: valid_edit_attributes
    }, headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }

    assert_response :see_other
    assert_redirected_to calendar_path(month: "2030-08", calendar_context_id: context.id, panel: 1)
    follow_redirect! headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }
    assert_select "turbo-frame##{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}"
    assert_select "[data-testid='family-calendar-notice']", text: "Appointment updated."
    assert_select "[data-testid='appointment-#{appointment.id}']", text: /Noah Greenfield.*Rescheduled occupational therapy/m
  end

  test "does not reassign an appointment to another account's profile" do
    appointment = create_appointment
    before = appointment.attributes
    sign_in users(:family_admin)

    patch appointment_path(appointment), params: {
      appointment: valid_edit_attributes.merge(dependent_id: dependents(:other_dependent).id)
    }

    assert_response :not_found
    assert_equal before, appointment.reload.attributes
  end

  {
    description: "",
    scheduled_at: "",
    dependent_id: ""
  }.each do |attribute, value|
    test "invalid #{attribute} keeps the appointment unchanged and retains edit errors" do
      appointment = create_appointment
      before = appointment.attributes
      sign_in users(:family_admin)

      patch appointment_path(appointment), params: {
        month: "2030-07", appointment: valid_edit_attributes.merge(attribute => value)
      }

      assert_response :unprocessable_entity
      assert_equal before, appointment.reload.attributes
      assert_select "h2", text: "July 2030"
      assert_select "[data-testid='appointment-edit-errors'][role='alert']"
      assert_select "form[data-testid='appointment-edit-form'][action='#{appointment_path(appointment)}']" do
        assert_select "input[name='_method'][value='patch']"
      end
      assert_select "form[data-testid='appointment-form'][method='post'][action='#{appointments_path}']" do
        assert_select "input[name='_method']", count: 0
        assert_select "textarea[name='appointment[description]']", text: ""
      end
    end
  end

  test "panel edit errors preserve entered fields and the separate Add Appointment form" do
    appointment = create_appointment
    before = appointment.attributes
    context = dependents(:emma)
    sign_in users(:family_admin)

    patch appointment_path(appointment, calendar_context_id: context.id, panel: 1), params: {
      month: "2030-07", appointment: valid_edit_attributes.merge(description: "")
    }, headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }

    assert_response :unprocessable_entity
    assert_equal before, appointment.reload.attributes
    assert_select "turbo-frame##{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}"
    assert_select "[data-testid='app-shell']", count: 0
    assert_select "h2", text: "July 2030"
    assert_select "[data-testid='appointment-edit-dependent'] option[selected][value='#{dependents(:noah).id}']"
    assert_select "[data-testid='appointment-edit-scheduled-at'][value='2030-08-05T09:15']"
    assert_select "textarea[data-testid='appointment-edit-description']", text: ""
    assert_select "[data-testid='appointment-edit-errors']", text: /Description can.t be blank/
    assert_select "form[data-testid='appointment-form'][action='#{appointments_path(calendar_context_id: context.id, panel: 1)}'][method='post']" do
      assert_select "input[name='_method']", count: 0
      assert_select "[data-testid='appointment-dependent'] option[selected][value='#{context.id}']"
    end
  end

  test "deletes an adjacent-month appointment while retaining the viewed month" do
    appointment = create_appointment(scheduled_at: Time.zone.local(2030, 6, 30, 9, 0))
    sign_in users(:family_admin)

    assert_difference -> { Appointment.count }, -1 do
      delete appointment_path(appointment), params: { month: "2030-07" }
    end

    assert_response :see_other
    assert_redirected_to calendar_path(month: "2030-07")
    assert_equal "Appointment deleted.", flash[:notice]
    follow_redirect!
    assert_select "h2", text: "July 2030"
    assert_select "[data-testid='appointment-#{appointment.id}']", count: 0
    assert_select "[data-testid='agenda-appointment-#{appointment.id}']", count: 0
  end

  test "an account member can delete an appointment while retaining the calendar panel" do
    appointment = create_appointment(dependent: dependents(:noah))
    context = dependents(:emma)
    sign_in users(:account_member)

    assert_difference -> { Appointment.count }, -1 do
      delete appointment_path(appointment, calendar_context_id: context.id, panel: 1),
        params: { month: "2030-07" },
        headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }
    end

    assert_response :see_other
    assert_redirected_to calendar_path(month: "2030-07", calendar_context_id: context.id, panel: 1)
    follow_redirect! headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }
    assert_select "turbo-frame##{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}"
    assert_select "[data-testid='app-shell']", count: 0
    assert_select "[data-testid='family-calendar-notice']", text: "Appointment deleted."
    assert_select "[data-testid='appointment-#{appointment.id}']", count: 0
  end

  private

    def create_appointment(dependent: dependents(:emma), scheduled_at: Time.zone.local(2030, 7, 22, 14, 30))
      dependent.appointments.create!(scheduled_at: scheduled_at, description: "Original appointment")
    end

    def valid_edit_attributes
      {
        dependent_id: dependents(:noah).id,
        scheduled_at: "2030-08-05T09:15",
        description: "Rescheduled occupational therapy"
      }
    end
end
