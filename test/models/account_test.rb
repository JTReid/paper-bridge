require "test_helper"

class AccountTest < ActiveSupport::TestCase
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
    2.times { |index| account.dependents.create!(first_name: "Profile #{index}") }

    assert_equal 5, account.profile_limit
    assert_equal 4, account.dependents.count
    assert_equal 2, account.account_memberships.count
    assert_equal 1, account.care_team_memberships.count
    assert_not account.profile_limit_reached?

    account.dependents.create!(first_name: "Fifth")

    assert account.profile_limit_reached?
  end
end
