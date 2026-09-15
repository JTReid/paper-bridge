require "test_helper"

class AccountTest < ActiveSupport::TestCase
  test "new accounts require billing by default" do
    account = Account.create!(name: "New Family")

    assert_not account.non_billable?
    assert_not account.product_access?
    assert_nil account.billing_subscription
  end

  test "non billable access can be granted and revoked without a subscription" do
    account = Account.create!(name: "Complimentary Family", non_billable: true)

    assert account.product_access?
    assert_not account.subscription_active?
    assert_nil account.billing_subscription

    account.update!(non_billable: false)

    assert_not account.product_access?
    assert_nil account.reload.billing_subscription
  end

  test "billable product access continues to follow subscription state" do
    account = accounts(:greenfield)

    assert account.product_access?
    account.billing_subscription.update!(status: :canceled)
    assert_not account.product_access?
    account.billing_subscription.update!(status: :trialing, trial_end: 1.day.from_now)
    assert account.product_access?
  end

  test "non billable accounts can create profiles beyond a saved subscription allowance" do
    account = accounts(:greenfield)
    subscription = account.billing_subscription
    subscription.update!(status: :canceled, profile_limit: 5)
    account.update!(non_billable: true)

    assert_nil account.profile_limit
    assert_not account.profile_limit_reached?
    assert_difference -> { account.dependents.count }, 4 do
      4.times { |index| account.dependents.create!(first_name: "Profile #{index}", last_name: "Complimentary") }
    end
    assert_equal 6, account.dependents.count
    assert_equal 5, subscription.reload.profile_limit

    account.update!(non_billable: false)

    assert_equal 5, account.profile_limit
    assert account.profile_limit_reached?
    assert_equal 6, account.dependents.count
  end

  test "requires a name" do
    account = Account.new

    assert_not account.valid?
    assert_includes account.errors[:name], "can't be blank"
  end

  test "destroys dependent workspace records without association ordering errors" do
    account = accounts(:greenfield)

    assert account.destroy
    assert_empty Document.where(account: account)
    assert_empty Dependent.where(account: account)
    assert_empty CareTeamMembership.where(account: account)
  end

  test "legacy subscriptions and accounts without subscriptions have no profile limit" do
    assert_nil accounts(:greenfield).profile_limit
    assert_not accounts(:greenfield).profile_limit_reached?
    assert_nil accounts(:other).profile_limit
    assert_not accounts(:other).profile_limit_reached?
  end

  test "profile allowance counts managed profiles and not account or care team members" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(profile_limit: 5)
    2.times { |index| account.dependents.create!(first_name: "Profile #{index}", last_name: "Allowance") }

    assert_equal 5, account.profile_limit
    assert_equal 4, account.dependents.count
    assert_equal 2, account.account_memberships.count
    assert_equal 1, account.care_team_memberships.count
    assert_not account.profile_limit_reached?

    account.dependents.create!(first_name: "Fifth", last_name: "Allowance")

    assert account.profile_limit_reached?
  end
end
