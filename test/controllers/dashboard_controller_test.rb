require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "renders the signed in account dashboard with an empty appointment state" do
    dependent = dependents(:emma)
    Appointment.delete_all
    dependent.avatar.attach(
      io: Rails.root.join("public/icon.png").open,
      filename: "icon.png",
      content_type: "image/png"
    )
    sign_in users(:family_admin)

    get dashboard_path

    assert_response :success
    assert_includes response.body, "Your Family Hub"
    assert_includes response.body, "Family Calendar"
    assert_includes response.body, "No upcoming appointments"
    assert_includes response.body, "Profiles"
    assert_includes response.body, dependent.name
    assert_select "a[data-testid='dashboard-calendar-link'][href='#{calendar_path}']", text: /View calendar/
    assert_select "[data-testid='dashboard-calendar-empty-state']"
    assert_select "img[data-testid='dependent-avatar-dashboard-#{dependent.id}'][src='#{avatar_dependent_path(dependent)}']"
    assert_not_includes response.body, "Ask PaperBridge"
    assert_not_includes response.body, "All Profiles"
    assert_not_includes response.body, "AI Workspace"
    assert_not_includes response.body, "Recent Documents"
    assert_not_includes response.body, "Evidence chunks"
    assert_not_includes response.body, documents(:advance_directive).title
  end

  test "renders the next account appointments in scheduled order" do
    Appointment.delete_all
    dependent = dependents(:emma)
    first_appointment = Appointment.create!(
      dependent: dependent,
      scheduled_at: 2.days.from_now.change(usec: 0),
      description: "Speech therapy follow-up"
    )
    second_appointment = Appointment.create!(
      dependent: dependent,
      scheduled_at: 5.days.from_now.change(usec: 0),
      description: "Pediatric check-in"
    )
    Appointment.create!(
      dependent: dependent,
      scheduled_at: 1.day.ago,
      description: "Past appointment"
    )
    Appointment.create!(
      dependent: dependents(:other_dependent),
      scheduled_at: 1.day.from_now,
      description: "Other family appointment"
    )
    sign_in users(:family_admin)

    get dashboard_path

    assert_response :success
    assert_select "[data-testid='dashboard-upcoming-appointments']"
    assert_select "a[data-testid='dashboard-appointment-#{first_appointment.id}'][href='#{calendar_path(month: first_appointment.scheduled_at.in_time_zone.strftime("%Y-%m"))}']" do
      assert_select "time[datetime='#{first_appointment.scheduled_at.iso8601}']"
      assert_select "p", text: first_appointment.description
      assert_select "p", text: /#{Regexp.escape(dependent.name)}/
    end
    assert_select "a[data-testid='dashboard-appointment-#{second_appointment.id}']"
    assert_operator response.body.index(first_appointment.description), :<, response.body.index(second_appointment.description)
    assert_not_includes response.body, "Past appointment"
    assert_not_includes response.body, "Other family appointment"
    assert_select "[data-testid='dashboard-calendar-empty-state']", count: 0
  end

  test "redirects signed in inactive accounts to billing" do
    accounts(:greenfield).billing_subscription.update!(status: :canceled)
    sign_in users(:family_admin)

    get dashboard_path

    assert_redirected_to billing_path
    assert_equal "A subscription is required to continue.", flash[:alert]
  end

  test "renders a locked checkout confirmation while the subscription is inactive" do
    subscription = accounts(:greenfield).billing_subscription
    subscription.status = :incomplete
    subscription.mark_checkout_pending
    subscription.save!
    sign_in users(:family_admin)

    get dashboard_path(checkout: "success")

    assert_response :success
    assert_select "turbo-cable-stream-source"
    assert_select "[data-testid='checkout-pending-page']"
    assert_includes response.body, "Finishing your subscription"
    assert_includes response.body, accounts(:greenfield).name
    assert_not_includes response.body, "Your Family Hub"
    assert_not_includes response.body, dependents(:emma).name
  end

  test "returns a completed non-active checkout result to billing" do
    accounts(:greenfield).billing_subscription.update!(status: :incomplete)
    sign_in users(:family_admin)

    get dashboard_path(checkout: "success")

    assert_redirected_to billing_path(checkout: "failed")
  end

  test "completes a successful checkout return when the subscription is active" do
    sign_in users(:family_admin)

    get dashboard_path(checkout: "success")

    assert_redirected_to dashboard_path
    assert_equal "You’re all set. Your PaperBridge subscription is active.", flash[:notice]
  end

  test "completes a successful checkout return when the subscription is trialing" do
    accounts(:greenfield).billing_subscription.update!(status: :trialing)
    sign_in users(:family_admin)

    get dashboard_path(checkout: "success")

    assert_redirected_to dashboard_path
    assert_equal "You’re all set. Your PaperBridge subscription is active.", flash[:notice]
  end
end
