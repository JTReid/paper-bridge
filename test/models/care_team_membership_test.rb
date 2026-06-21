require "test_helper"

class CareTeamMembershipTest < ActiveSupport::TestCase
  test "normalizes category permissions and copies user identity" do
    user = User.create!(
      name: "New Therapist",
      email: "new-therapist@example.test",
      password: "password",
      password_confirmation: "password"
    )
    membership = CareTeamMembership.create!(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: user,
      invited_by: users(:family_admin),
      role: :therapist,
      permissions: {
        "educational" => "0",
        "medical" => "1",
        "therapy" => true
      }
    )

    assert_equal "New Therapist", membership.name
    assert_equal "new-therapist@example.test", membership.email
    assert_equal %w[medical therapy], membership.allowed_document_categories.sort
    assert_equal false, membership.permissions.fetch("general")
  end

  test "requires account to match dependent" do
    membership = CareTeamMembership.new(
      account: accounts(:other),
      dependent: dependents(:emma),
      user: users(:therapist),
      invited_by: users(:other_user),
      name: "Therapist User",
      email: "therapist@example.test",
      role: :therapist
    )

    assert_not membership.valid?
    assert_includes membership.errors[:account], "must match the dependent"
  end

  test "normalizes symbol keyed category permissions" do
    user = User.create!(
      name: "Symbol Therapist",
      email: "symbol-therapist@example.test",
      password: "password",
      password_confirmation: "password"
    )
    membership = CareTeamMembership.new(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: user,
      invited_by: users(:family_admin),
      role: :therapist,
      permissions: {
        educational: "1",
        medical: "0",
        therapy: true
      }
    )

    assert membership.valid?
    assert_equal %w[educational therapy], membership.allowed_document_categories.sort
  end

  test "requires inviter to manage the account" do
    membership = CareTeamMembership.new(
      account: accounts(:greenfield),
      dependent: dependents(:emma),
      user: users(:therapist),
      invited_by: users(:account_member),
      name: "Therapist User",
      email: "therapist@example.test",
      role: :therapist
    )

    assert_not membership.valid?
    assert_includes membership.errors[:invited_by], "must be able to manage the account"
  end
end
