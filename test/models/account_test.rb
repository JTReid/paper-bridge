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
end
