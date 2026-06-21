require "test_helper"

class CareTeamMembershipsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependent_care_team_memberships_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "renders care team inside selected dependent workspace" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_care_team_memberships_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "Care Team"
    assert_includes response.body, "Invite Member"
  end

  test "invites a care team member by creating a login and membership" do
    sign_in users(:family_admin)

    assert_difference -> { User.count }, 1 do
      assert_difference -> { CareTeamMembership.count }, 1 do
        assert_no_difference -> { AccountMembership.count } do
          post dependent_care_team_memberships_path(dependents(:emma)), params: {
            care_team_membership: {
              name: "New Therapist",
              email: "new-therapist@example.test",
              role: "therapist",
              permissions: {
                educational: "0",
                medical: "1",
                therapy: "1",
                insurance: "0",
                general: "1"
              }
            }
          }
        end
      end
    end

    membership = CareTeamMembership.order(:created_at).last

    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
    assert_equal users(:family_admin), membership.invited_by
    assert_equal dependents(:emma), membership.dependent
    assert_equal "new-therapist@example.test", membership.user.email
    assert_nil membership.user.account
    assert_equal %w[general medical therapy], membership.allowed_document_categories.sort
  end

  test "inviting an existing user does not overwrite their identity" do
    sign_in users(:family_admin)

    assert_no_difference -> { User.count } do
      assert_difference -> { CareTeamMembership.count }, 1 do
        post dependent_care_team_memberships_path(dependents(:emma)), params: {
          care_team_membership: {
            name: "Edited Display Name",
            email: users(:account_member).email,
            role: "advocate",
            permissions: {
              educational: "1",
              medical: "0",
              therapy: "0",
              insurance: "0",
              general: "1"
            }
          }
        }
      end
    end

    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
    assert_equal "Account Member", users(:account_member).reload.name
    assert_equal users(:account_member), CareTeamMembership.order(:created_at).last.user
  end
end
