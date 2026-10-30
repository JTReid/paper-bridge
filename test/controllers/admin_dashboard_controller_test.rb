require "test_helper"

class AdminDashboardControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get admin_dashboard_path

    assert_redirected_to new_user_session_path
  end

  test "rejects family admins" do
    sign_in users(:family_admin)

    get admin_dashboard_path

    assert_redirected_to dashboard_path
    assert_equal "You do not have access to that page.", flash[:alert]
  end

  test "links to the dashboard from the admin navigation" do
    sign_in users(:super_admin)

    get admin_dashboard_path

    assert_response :success
    assert_select "a[href=?]", admin_dashboard_path, text: /Admin Dashboard/
  end

  test "counts paying, trial and free accounts as families" do
    accounts(:other).update!(non_billable: true)
    Account.create!(name: "Trial Family").create_billing_subscription!(status: :trialing)
    Account.create!(name: "Lapsed Family").create_billing_subscription!(status: :canceled)
    Account.create!(name: "Never Subscribed Family")

    get_dashboard

    assert_stat "families", 3
  end

  test "leaves accounts with a super admin member out of every number" do
    founder_account = accounts(:other)
    founder_account.update!(non_billable: true)
    founder_account.account_memberships.first.update!(user: users(:super_admin))
    documents(:outside_account).update_columns(status: "failed")
    share_events(:two).update_columns(status: "sent", sent_at: 1.day.ago)

    get_dashboard

    assert_stat "families", 1
    assert_stat "profiles", 2
    assert_stat "documents", 1
    assert_stat "failed-documents", 0
    assert_stat "shared-documents", 0
  end

  test "counts recent activity from the last 30 days" do
    accounts(:other).update!(non_billable: true)
    accounts(:greenfield).update_columns(created_at: 31.days.ago)
    documents(:outside_account).update_columns(created_at: 31.days.ago)
    share_events(:one).update_columns(sent_at: 1.day.ago)
    ask_question
    ask_question(created_at: 31.days.ago)

    get_dashboard

    assert_stat "new-families", 1
    assert_stat "documents", 2
    assert_select "[data-testid='admin-stat-documents']", text: /1 uploaded in the last 30 days/
    assert_stat "questions", 1
    assert_stat "shared-documents", 1
  end

  test "only counts documents that were actually emailed as shared" do
    accounts(:other).update!(non_billable: true)
    share_events(:one).update_columns(sent_at: 31.days.ago)
    share_events(:two).update_columns(status: "pending", sent_at: nil)

    get_dashboard

    assert_stat "shared-documents", 0
  end

  test "counts a family as active after an upload or a question" do
    accounts(:other).update!(non_billable: true)
    documents(:outside_account).update_columns(created_at: 31.days.ago)
    documents(:advance_directive).update_columns(created_at: 31.days.ago)
    ask_question

    get_dashboard

    assert_stat "active-families", 1

    documents(:outside_account).update_columns(created_at: 1.day.ago)
    get admin_dashboard_path

    assert_stat "active-families", 2
  end

  test "counts failed documents and flags them" do
    documents(:advance_directive).update_columns(status: "failed")

    get_dashboard

    assert_stat "failed-documents", 1
    assert_select "[data-testid='admin-stat-failed-documents'].bg-amber-50"
  end

  test "shows signup spots left only when there is a cap" do
    with_max_accounts("5") do
      get_dashboard

      assert_stat "signup-spots", 3
    end

    with_max_accounts("1") do
      get admin_dashboard_path

      assert_stat "signup-spots", 0
    end

    with_max_accounts(nil) do
      get admin_dashboard_path

      assert_select "[data-testid='admin-stat-signup-spots']", count: 0
    end
  end

  test "never shows anything that could identify a family" do
    accounts(:other).update!(non_billable: true)
    ask_question

    get_dashboard

    [
      accounts(:greenfield).name,
      accounts(:other).name,
      dependents(:emma).first_name,
      dependents(:noah).first_name,
      users(:family_admin).email,
      documents(:advance_directive).title,
      documents(:advance_directive).original_filename,
      share_events(:one).recipient_email,
      "What changed this month?"
    ].each { |value| assert_not_includes response.body, value }
  end

  private

    def get_dashboard
      sign_in users(:super_admin)
      get admin_dashboard_path
      assert_response :success
    end

    def assert_stat(key, value)
      assert_select "[data-testid='admin-stat-#{key}-value']", text: value.to_s
    end

    def ask_question(created_at: Time.current)
      AiAssistantQuery.create!(
        account: accounts(:greenfield),
        dependent: dependents(:emma),
        user: users(:family_admin),
        question: "What changed this month?",
        created_at: created_at
      )
    end

    def with_max_accounts(value)
      original = ENV["MAX_ACCOUNTS"]
      ENV["MAX_ACCOUNTS"] = value
      yield
    ensure
      ENV["MAX_ACCOUNTS"] = original
    end
end
