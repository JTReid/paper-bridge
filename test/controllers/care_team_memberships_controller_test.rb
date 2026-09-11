require "test_helper"

class CareTeamMembershipsControllerTest < ActionDispatch::IntegrationTest
  test "requires authentication" do
    get dependent_care_team_memberships_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "renders saved contact details inside the selected profile" do
    sign_in users(:family_admin)

    get dependent_care_team_memberships_path(dependents(:emma))

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependents(:emma).name
    assert_includes response.body, "Care Team"
    assert_includes response.body, "Add Member"
    assert_includes response.body, "therapist@example.test"
    assert_includes response.body, "850-555-0100"
    assert_not_includes response.body, "Invitation pending"
    assert_not_includes response.body, "Can access"
  end

  test "new and edit forms collect only contact details" do
    sign_in users(:family_admin)
    membership = care_team_memberships(:emma_therapist)

    [ new_dependent_care_team_membership_path(dependents(:emma)),
      edit_dependent_care_team_membership_path(dependents(:emma), membership) ].each do |path|
      get path

      assert_response :success
      assert_select "input[name='care_team_membership[name]']"
      assert_select "input[type='email'][name='care_team_membership[email]']"
      assert_select "select[name='care_team_membership[role]']"
      assert_select "input[type='tel'][name='care_team_membership[phone_number]']"
      assert_select "select[name='care_team_membership[status]']", count: 0
      assert_select "input[type='checkbox']", count: 0
    end
  end

  test "adds a contact without creating a login account membership or email" do
    sign_in users(:family_admin)

    assert_no_difference [ -> { User.count }, -> { AccountMembership.count }, -> { ActionMailer::Base.deliveries.size } ] do
      assert_no_enqueued_emails do
        assert_difference -> { CareTeamMembership.count }, 1 do
          post dependent_care_team_memberships_path(dependents(:emma)), params: { care_team_membership: contact_attributes }
        end
      end
    end

    membership = CareTeamMembership.order(:created_at).last
    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
    assert_equal "Care team member added.", flash[:notice]
    assert_equal users(:family_admin), membership.invited_by
    assert_equal dependents(:emma), membership.dependent
    assert_equal "new-therapist@example.test", membership.email
    assert_equal "850-555-0101", membership.phone_number
  end

  test "a contact matching a login email never changes that user" do
    sign_in users(:family_admin)
    user = users(:account_member)
    original_identity = user.attributes

    assert_no_difference -> { User.count } do
      post dependent_care_team_memberships_path(dependents(:emma)), params: {
        care_team_membership: contact_attributes.merge(name: "Contact Name", email: user.email)
      }
    end

    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
    assert_equal original_identity, user.reload.attributes
    assert_equal "Contact Name", CareTeamMembership.order(:created_at).last.name
  end

  test "invalid contact details do not create records" do
    sign_in users(:family_admin)

    [ { name: "" }, { email: "" }, { email: "not-an-email" }, { email: "THERAPIST@example.test" } ].each do |invalid|
      assert_no_difference [ -> { User.count }, -> { CareTeamMembership.count } ] do
        post dependent_care_team_memberships_path(dependents(:emma)), params: {
          care_team_membership: contact_attributes.merge(invalid)
        }
      end

      assert_response :unprocessable_entity
      assert_select "input[name='care_team_membership[phone_number]'][value='850-555-0101']"
    end
  end

  test "updates contact details and recalls the updated email for document sharing" do
    sign_in users(:family_admin)
    membership = care_team_memberships(:emma_therapist)

    assert_no_difference -> { User.count } do
      patch dependent_care_team_membership_path(dependents(:emma), membership), params: {
        care_team_membership: contact_attributes.merge(name: "Updated Therapist", email: "updated@example.test")
      }
    end

    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
    assert_equal "850-555-0101", membership.reload.phone_number
    assert_equal "Updated Therapist", membership.name

    get dependent_documents_path(dependents(:emma))

    assert_response :success
    assert_select "select[name='care_team_recipient'] option[value='updated@example.test']", text: "Updated Therapist (updated@example.test)"
  end

  test "ignores submitted login and permission settings" do
    sign_in users(:family_admin)

    assert_no_difference -> { User.count } do
      post dependent_care_team_memberships_path(dependents(:emma)), params: {
        care_team_membership: contact_attributes.merge(
          user_id: users(:other_user).id, account_id: accounts(:other).id,
          invited_by_id: users(:other_user).id, status: "active", permissions: { medical: true }
        )
      }
    end

    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
    membership = CareTeamMembership.order(:created_at).last
    assert_equal accounts(:greenfield), membership.account
    assert_equal users(:family_admin), membership.invited_by
    legacy = CareTeamMembership.connection.select_one("SELECT user_id, status, permissions FROM care_team_memberships WHERE id = #{membership.id}")
    assert_nil legacy["user_id"]
    assert_nil legacy["status"]
    assert_equal "{}", legacy["permissions"]
  end

  test "removes only the contact" do
    sign_in users(:family_admin)

    assert_no_difference -> { User.count } do
      assert_difference -> { CareTeamMembership.count }, -1 do
        delete dependent_care_team_membership_path(dependents(:emma), care_team_memberships(:emma_therapist))
      end
    end

    assert_redirected_to dependent_care_team_memberships_path(dependents(:emma))
  end

  test "only account managers can add edit or remove contacts" do
    sign_in users(:account_member)
    dependent = dependents(:emma)
    membership = care_team_memberships(:emma_therapist)

    get new_dependent_care_team_membership_path(dependent)
    assert_response :forbidden
    get edit_dependent_care_team_membership_path(dependent, membership)
    assert_response :forbidden

    assert_no_difference -> { CareTeamMembership.count } do
      post dependent_care_team_memberships_path(dependent), params: { care_team_membership: contact_attributes }
      assert_response :forbidden
      patch dependent_care_team_membership_path(dependent, membership), params: { care_team_membership: contact_attributes }
      assert_response :forbidden
      delete dependent_care_team_membership_path(dependent, membership)
      assert_response :forbidden
    end
    assert_equal "Therapist User", membership.reload.name
  end

  test "cannot access another account's contacts" do
    sign_in users(:family_admin)

    get dependent_care_team_memberships_path(dependents(:other_dependent))
    assert_response :not_found

    sign_in users(:family_admin)
    patch dependent_care_team_membership_path(dependents(:other_dependent), care_team_memberships(:emma_therapist)), params: {
      care_team_membership: contact_attributes
    }
    assert_response :not_found
  end

  test "a legacy care-team-only login cannot access contact management" do
    sign_in users(:therapist)

    get dependent_care_team_memberships_path(dependents(:emma))

    assert_redirected_to root_path
  end

  private

    def contact_attributes
      { name: "New Therapist", email: "new-therapist@example.test", role: "therapist", phone_number: "850-555-0101" }
    end
end
