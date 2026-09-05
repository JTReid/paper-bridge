require "test_helper"

class DependentsControllerTest < ActionDispatch::IntegrationTest
  test "shows allowance and billing link without accepting another profile at the limit" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(profile_limit: 5)
    3.times { |index| account.dependents.create!(first_name: "Profile #{index}") }
    sign_in users(:family_admin)

    get dependents_path

    assert_response :success
    assert_select "[data-testid='profile-allowance']", text: /5 of 5 managed profiles in use/
    assert_select "a[data-testid='profile-allowance-billing-link'][href='#{billing_path}']"

    get new_dependent_path

    assert_response :success
    assert_select "[data-testid='profile-limit-reached']", text: /Your existing profiles and documents stay available/
    assert_select "input[data-testid='profile-create-submit'][disabled]"

    assert_no_difference "Dependent.count" do
      post dependents_path, params: { dependent: { first_name: "Sixth" } }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Your managed profile allowance is full."
    assert_select "a[data-testid='profile-allowance-billing-link'][href='#{billing_path}']"
  end

  test "over-limit accounts can still view and edit all existing profiles" do
    account = accounts(:greenfield)
    4.times { |index| account.dependents.create!(first_name: "Profile #{index}") }
    account.billing_subscription.update!(profile_limit: 5)
    sign_in users(:family_admin)

    get dependents_path

    assert_response :success
    assert_select "[data-testid='profile-allowance']", text: /6 of 5 managed profiles in use/
    assert_select "[data-testid='profile-limit-reached']", text: /You're over your current profile allowance/

    get dependent_path(dependents(:emma))

    assert_response :success

    get edit_dependent_path(dependents(:emma))

    assert_response :success
    assert_select "input[data-testid='profile-save-submit'][disabled]", count: 0

    patch dependent_path(dependents(:emma)), params: { dependent: { first_name: "Emilia" } }

    assert_redirected_to dependent_path(dependents(:emma))
    assert_equal "Emilia", dependents(:emma).reload.first_name
    assert_equal 6, account.dependents.count
  end

  test "requires authentication" do
    get dependents_path

    assert_redirected_to new_user_session_path
  end

  test "renders account dependents" do
    dependent = dependents(:emma)
    attach_avatar(dependent)
    sign_in users(:family_admin)

    get dependents_path

    assert_response :success
    assert_includes response.body, "Profiles"
    assert_includes response.body, dependent.name
    assert_not_includes response.body, dependents(:other_dependent).name
    assert_select "img[data-testid='dependent-avatar-index-#{dependent.id}'][src='#{avatar_dependent_path(dependent)}']"
  end

  test "renders selected dependent workspace navigation" do
    dependent = dependents(:emma)
    attach_avatar(dependent)
    sign_in users(:family_admin)

    get dependent_path(dependent)

    assert_response :success
    assert_includes response.body, "All Profiles"
    assert_includes response.body, dependent.name
    assert_includes response.body, "Overview"
    assert_includes response.body, "Documents"
    assert_includes response.body, "Calendar"
    assert_includes response.body, "Ask PaperBridge"
    assert_includes response.body, "Care Team"
    assert_select "img[data-testid='dependent-avatar-profile'][src='#{avatar_dependent_path(dependent)}']"
    assert_select "img[data-testid='dependent-avatar-sidebar'][src='#{avatar_dependent_path(dependent)}']"
    assert_select "img[data-testid='dependent-avatar-mobile-menu'][src='#{avatar_dependent_path(dependent)}']"
    assert_select "a[data-testid='nav-calendar'][href='#{calendar_path(calendar_context_id: dependent.id, panel: 1)}'][data-turbo-frame='#{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}'][aria-haspopup='dialog'][aria-expanded='false']", text: "Calendar"
    assert_select "dialog[data-testid='family-calendar-dialog'][aria-labelledby='family-calendar-title']"
    assert_select "turbo-frame##{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}[data-testid='family-calendar-frame']"
    assert_select "a[data-testid='dependent-documents-link'][data-tour='open-documents'][data-action='product-tour#advance'][data-product-tour-from-phase-param='open_documents'][data-product-tour-next-phase-param='add_documents']"
    Document.categories.each_key do |category|
      assert_select "a[data-testid='dependent-category-#{category}'][href='#{dependent_documents_path(dependent, category: category)}']"
    end
  end

  test "renders the create profile tour hook only on the new form" do
    sign_in users(:family_admin)

    get new_dependent_path

    assert_response :success
    assert_select "form[data-testid='profile-create-form'][data-tour='profile-form'][data-action='input->product-tour#pause turbo:submit-end->product-tour#advanceAfterSubmit'][data-product-tour-from-phase-param='profile_form'][data-product-tour-next-phase-param='open_documents']"
    assert_select "input[data-testid='profile-create-submit']"
    assert_select "input[name='dependent[first_name]'][required]"
    assert_select "input[name='dependent[last_name]']"
    assert_select "input[name='dependent[last_name]'][required]", count: 0
    assert_select "input[name='dependent[name]']", count: 0
    assert_select "input[name='dependent[grade]']", count: 0
    assert_select "input[name='dependent[school]']", count: 0
    assert_select "[data-testid='profile-delete-button']", count: 0

    get edit_dependent_path(dependents(:emma))

    assert_response :success
    assert_select "form[data-tour='profile-form']", count: 0
    assert_select "input[data-testid='profile-save-submit']"
    assert_select "input[name='dependent[first_name]'][value='Emma']"
    assert_select "input[name='dependent[last_name]'][value='Greenfield']"
    assert_select "input[name='dependent[grade]'][value='3rd Grade']"
    assert_select "input[name='dependent[school]'][value='Maplewood Elementary']"
    assert_select "form[action='#{dependent_path(dependents(:emma))}'][method='post']" do
      assert_select "input[name='_method'][value='delete']"
      assert_select "button[data-testid='profile-delete-button']", text: "Delete profile"
    end
    assert_select "[data-turbo-confirm]"
  end

  test "renders initials when the selected dependent has no avatar" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get dependent_path(dependent)

    assert_response :success
    assert_select "span[data-testid='dependent-avatar-profile'][role='img']", text: "EG"
    assert_select "span[data-testid='dependent-avatar-sidebar'][role='img']", text: "EG"
    assert_select "span[data-testid='dependent-avatar-mobile-menu'][role='img']", text: "EG"
  end

  test "creates a profile with an uploaded avatar" do
    sign_in users(:family_admin)

    assert_difference -> { Dependent.count } do
      post dependents_path, params: {
        dependent: {
          first_name: "Jackie",
          last_name: "Gibbson",
          account_id: accounts(:other).id,
          grade: "4th",
          school: "Walton County Middle School",
          date_of_birth: "2017-04-12",
          notes: "Prefers morning appointments.",
          avatar: uploaded_avatar
        }
      }
    end

    dependent = Dependent.order(:created_at).last
    assert_redirected_to dependent_path(dependent)
    assert_equal users(:family_admin).account, dependent.account
    assert_equal "Jackie Gibbson", dependent.name
    assert_nil dependent.grade
    assert_nil dependent.school
    assert_equal Date.new(2017, 4, 12), dependent.date_of_birth
    assert_equal "Prefers morning appointments.", dependent.notes
    assert dependent.avatar.attached?
    assert_equal "icon.png", dependent.avatar.filename.to_s
    assert_equal "image/png", dependent.avatar.content_type
  end

  test "renders a failed create with separate names and without initial school fields" do
    sign_in users(:family_admin)

    assert_no_difference -> { Dependent.count } do
      post dependents_path, params: { dependent: { first_name: " ", last_name: "Greenfield" } }
    end

    assert_response :unprocessable_entity
    assert_select "[role='alert']", text: /First name can't be blank/
    assert_select "input[name='dependent[last_name]'][value='Greenfield']"
    assert_select "input[name='dependent[grade]']", count: 0
    assert_select "input[name='dependent[school]']", count: 0
  end

  test "updates separate names and optional profile details within the current account" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    patch dependent_path(dependent), params: {
      dependent: {
        first_name: "  Emilia  ",
        last_name: "  de la Cruz  ",
        account_id: accounts(:other).id,
        grade: "4th Grade",
        school: "New Elementary",
        date_of_birth: "2016-04-13",
        notes: "Updated support needs."
      }
    }

    assert_redirected_to dependent_path(dependent)
    dependent.reload
    assert_equal accounts(:greenfield), dependent.account
    assert_equal "Emilia", dependent.first_name
    assert_equal "de la Cruz", dependent.last_name
    assert_equal "Emilia de la Cruz", dependent.name
    assert_equal "4th Grade", dependent.grade
    assert_equal "New Elementary", dependent.school
    assert_equal Date.new(2016, 4, 13), dependent.date_of_birth
    assert_equal "Updated support needs.", dependent.notes
  end

  test "cannot edit another account's profile" do
    dependent = dependents(:other_dependent)
    sign_in users(:family_admin)

    get edit_dependent_path(dependent)

    assert_response :not_found
  end

  test "cannot update another account's profile" do
    dependent = dependents(:other_dependent)
    sign_in users(:family_admin)

    patch dependent_path(dependent), params: { dependent: { first_name: "Changed" } }

    assert_response :not_found
    assert_equal "Other", dependent.reload.first_name
  end

  test "profile deletion requires authentication" do
    dependent = dependents(:noah)

    assert_no_difference -> { Dependent.count } do
      delete dependent_path(dependent)
    end

    assert_redirected_to new_user_session_path
    assert dependent.reload.persisted?
  end

  test "cannot delete another account's profile" do
    sign_in users(:family_admin)

    assert_no_difference -> { Dependent.count } do
      delete dependent_path(dependents(:other_dependent))
    end

    assert_response :not_found
  end

  test "deletes a profile without documents and its dependent-owned records" do
    dependent = dependents(:noah)
    appointment = appointments(:noah_checkup)
    membership = dependent.care_team_memberships.create!(
      account: accounts(:greenfield),
      user: users(:therapist),
      invited_by: users(:family_admin),
      role: :therapist,
      status: :active
    )
    query = create_query(dependent)
    sign_in users(:family_admin)

    assert_difference -> { Dependent.count }, -1 do
      delete dependent_path(dependent)
    end

    assert_response :see_other
    assert_redirected_to dependents_path
    assert_equal "Profile deleted.", flash[:notice]
    assert_not Dependent.exists?(dependent.id)
    assert_not Appointment.exists?(appointment.id)
    assert_not CareTeamMembership.exists?(membership.id)
    assert_not AiAssistantQuery.exists?(query.id)
    assert User.exists?(users(:therapist).id)
    assert Dependent.exists?(dependents(:emma).id)
  end

  test "refuses to delete a profile with documents and preserves its related records" do
    dependent = dependents(:emma)
    document = documents(:advance_directive)
    appointment = appointments(:emma_therapy)
    membership = care_team_memberships(:emma_therapist)
    query = create_query(dependent)
    sign_in users(:family_admin)

    assert_no_difference -> { Dependent.count } do
      delete dependent_path(dependent)
    end

    assert_response :see_other
    assert_redirected_to edit_dependent_path(dependent)
    assert_equal "Remove this profile’s documents before deleting the profile.", flash[:alert]
    assert dependent.reload.persisted?
    assert_equal dependent.id, document.reload.dependent_id
    assert_equal dependent.id, appointment.reload.dependent_id
    assert_equal dependent.id, membership.reload.dependent_id
    assert_equal dependent.id, query.reload.dependent_id
  end

  test "edit form accepts and updates a profile avatar" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get edit_dependent_path(dependent)

    assert_response :success
    assert_select "form[enctype='multipart/form-data'] input[type='file'][name='dependent[avatar]'][accept='image/jpeg,image/png,image/webp']"
    assert_select "a[data-testid='nav-calendar'][data-turbo-frame='#{CalendarWorkspace::FAMILY_CALENDAR_FRAME_ID}']", text: "Calendar"
    assert_select "a[href='#{dependent_path(dependent)}']", text: "Cancel"

    patch dependent_path(dependent), params: { dependent: { avatar: uploaded_avatar } }

    assert_redirected_to dependent_path(dependent)
    assert dependent.reload.avatar.attached?
    assert_equal "image/png", dependent.avatar.content_type
  end

  test "avatar requires authentication" do
    get avatar_dependent_path(dependents(:emma))

    assert_redirected_to new_user_session_path
  end

  test "redirects an authorized avatar request to a processed service URL" do
    dependent = dependents(:emma)
    attach_avatar(dependent)
    sign_in users(:family_admin)

    get avatar_dependent_path(dependent)

    assert_response :redirect
    assert_includes response.location, "/rails/active_storage/disk/"

    follow_redirect!

    assert_response :success
    assert_equal "image/png", response.media_type
  end

  test "does not expose an avatar from another account" do
    sign_in users(:family_admin)

    get avatar_dependent_path(dependents(:other_dependent))

    assert_response :not_found
  end

  test "returns not found when the dependent has no avatar" do
    sign_in users(:family_admin)

    get avatar_dependent_path(dependents(:emma))

    assert_response :not_found
  end

  private

    def create_query(dependent)
      dependent.ai_assistant_queries.create!(
        account: accounts(:greenfield),
        user: users(:family_admin),
        question: "What support is documented?"
      )
    end

    def attach_avatar(dependent)
      dependent.avatar.attach(
        io: Rails.root.join("public/icon.png").open,
        filename: "icon.png",
        content_type: "image/png"
      )
    end

    def uploaded_avatar
      Rack::Test::UploadedFile.new(Rails.root.join("public/icon.png"), "image/png")
    end
end
