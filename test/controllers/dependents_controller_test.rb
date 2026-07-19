require "test_helper"

class DependentsControllerTest < ActionDispatch::IntegrationTest
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
    assert_select "a[data-testid='nav-calendar'][href='#{calendar_path}']", text: "Calendar"
    Document.categories.each_key do |category|
      assert_select "a[data-testid='dependent-category-#{category}'][href='#{dependent_documents_path(dependent, category: category)}']"
    end
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
          name: "Jackie Gibbson",
          grade: "4th",
          school: "Walton County Middle School",
          avatar: uploaded_avatar
        }
      }
    end

    dependent = Dependent.order(:created_at).last
    assert_redirected_to dependent_path(dependent)
    assert_equal users(:family_admin).account, dependent.account
    assert dependent.avatar.attached?
    assert_equal "icon.png", dependent.avatar.filename.to_s
    assert_equal "image/png", dependent.avatar.content_type
  end

  test "edit form accepts and updates a profile avatar" do
    dependent = dependents(:emma)
    sign_in users(:family_admin)

    get edit_dependent_path(dependent)

    assert_response :success
    assert_select "form[enctype='multipart/form-data'] input[type='file'][name='dependent[avatar]'][accept='image/jpeg,image/png,image/webp']"

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
