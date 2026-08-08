require "test_helper"

class CalendarControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get calendar_path

    assert_redirected_to new_user_session_path
  end

  test "renders an account calendar with Sunday first month navigation and appointment details" do
    appointment = dependents(:emma).appointments.create!(
      scheduled_at: Time.zone.local(2030, 7, 22, 14, 30),
      description: "Speech therapy appointment"
    )
    sign_in users(:family_admin)

    get calendar_path(month: "2030-07")

    assert_response :success
    assert_select "[data-testid='calendar-page']"
    assert_select "h1", text: "Calendar"
    assert_select "h2", text: "July 2030"
    assert_select "a[data-testid='nav-calendar'][href='#{calendar_path}']", text: "Calendar"
    assert_select "a[data-testid='calendar-previous-month'][href='#{calendar_path(month: "2030-06")}']"
    assert_select "a[data-testid='calendar-next-month'][href='#{calendar_path(month: "2030-08")}']"
    assert_select "[data-testid='calendar-grid'] [data-calendar-date]", count: 35
    assert_select "[role='region'][aria-label='Monthly calendar grid'][tabindex='0']"
    assert_equal "2030-06-30", css_select("[data-testid='calendar-grid'] [data-calendar-date]").first["data-calendar-date"]
    assert_equal "2030-08-03", css_select("[data-testid='calendar-grid'] [data-calendar-date]").last["data-calendar-date"]
    assert_select "[data-calendar-date='2030-07-22'] [data-testid='appointment-#{appointment.id}']", text: /Emma Greenfield.*Speech therapy appointment/m
    assert_select "[data-testid='appointment-#{appointment.id}'][data-appointment-dialog-dependent-param='Emma Greenfield']"
    assert_select "[data-testid='appointment-dialog'][aria-labelledby='appointment-dialog-title']"
    assert_select "#appointment-dialog-title", text: "Appointment"
    assert_select "label[for='appointment_scheduled_at']", text: "When (Central Time)"
  end

  test "places an appointment on its Central Time date near UTC midnight" do
    appointment = dependents(:emma).appointments.create!(
      scheduled_at: Time.utc(2030, 7, 20, 4, 30),
      description: "Late evening appointment"
    )
    sign_in users(:family_admin)

    get calendar_path(month: "2030-07")

    assert_response :success
    assert_select "[data-calendar-date='2030-07-19'] [data-testid='appointment-#{appointment.id}']", text: /11:30 PM/
    assert_select "[data-calendar-date='2030-07-20'] [data-testid='appointment-#{appointment.id}']", count: 0
    assert_select "[data-testid='appointment-#{appointment.id}'][data-appointment-dialog-scheduled-at-param$='CDT']"
  end

  test "does not expose appointments from another account" do
    outside_appointment = dependents(:other_dependent).appointments.create!(
      scheduled_at: Time.zone.local(2030, 7, 22, 10, 0),
      description: "Outside account appointment"
    )
    sign_in users(:family_admin)

    get calendar_path(month: "2030-07")

    assert_response :success
    assert_select "[data-testid='appointment-#{outside_appointment.id}']", count: 0
    assert_not_includes response.body, outside_appointment.description
  end

  test "renders the family calendar panel in a dependent workspace with all account appointments" do
    dependent = dependents(:emma)
    sibling = dependents(:noah)
    emma_appointment = dependent.appointments.create!(
      scheduled_at: Time.zone.local(2030, 7, 22, 14, 30),
      description: "Emma speech therapy"
    )
    sibling_appointment = sibling.appointments.create!(
      scheduled_at: Time.zone.local(2030, 7, 23, 9, 0),
      description: "Noah dental checkup"
    )
    outside_appointment = dependents(:other_dependent).appointments.create!(
      scheduled_at: Time.zone.local(2030, 7, 24, 10, 0),
      description: "Outside account appointment"
    )
    sign_in users(:family_admin)

    get calendar_path(month: "2030-07", calendar_context_id: dependent.id, panel: 1),
      headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }

    assert_response :success
    assert_select "turbo-frame##{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}[data-testid='family-calendar-frame']"
    assert_select "[data-testid='app-shell']", count: 0
    assert_select "select[data-testid='appointment-dependent'] option[selected][value='#{dependent.id}']", text: dependent.name
    assert_select "[data-testid='appointment-#{emma_appointment.id}']", text: /Emma Greenfield.*Emma speech therapy/m
    assert_select "[data-testid='appointment-#{sibling_appointment.id}']", text: /Noah Greenfield.*Noah dental checkup/m
    assert_select "[data-testid='appointment-#{outside_appointment.id}']", count: 0
    assert_not_includes response.body, outside_appointment.description
    assert_select "a[data-testid='calendar-previous-month'][href='#{calendar_path(calendar_context_id: dependent.id, panel: 1, month: "2030-06")}']"
    assert_select "a[data-testid='calendar-today'][href='#{calendar_path(calendar_context_id: dependent.id, panel: 1)}']"
    assert_select "a[data-testid='calendar-next-month'][href='#{calendar_path(calendar_context_id: dependent.id, panel: 1, month: "2030-08")}']"
    assert_select "form[data-testid='appointment-form'][action='#{appointments_path(calendar_context_id: dependent.id, panel: 1)}']"
    assert_select "form[data-testid='appointment-email-form'][action='#{appointment_emails_path(calendar_context_id: dependent.id, panel: 1)}']"
  end

  test "does not open a family calendar panel for a dependent from another account" do
    sign_in users(:family_admin)

    get calendar_path(calendar_context_id: dependents(:other_dependent).id, panel: 1),
      headers: { "Turbo-Frame" => CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID }

    assert_response :not_found
  end

  test "counts only appointments in the requested month" do
    Appointment.delete_all

    in_month = dependents(:emma).appointments.create!(
      scheduled_at: Time.zone.local(2030, 7, 22, 14, 30),
      description: "July appointment"
    )
    adjacent_month = dependents(:emma).appointments.create!(
      scheduled_at: Time.zone.local(2030, 6, 30, 9, 0),
      description: "June appointment"
    )
    sign_in users(:family_admin)

    get calendar_path(month: "2030-07")

    assert_response :success
    assert_select "#calendar-month-heading + p", text: "1 appointment this month"
    assert_select "[data-testid='calendar-grid'] [data-testid='appointment-#{in_month.id}']"
    assert_select "[data-testid='calendar-grid'] [data-testid='appointment-#{adjacent_month.id}']"
    assert_select "[data-testid='calendar-agenda'] [data-testid='agenda-appointment-#{in_month.id}']"
    assert_select "[data-testid='calendar-agenda'] [data-testid='agenda-appointment-#{adjacent_month.id}']", count: 0
  end
end
