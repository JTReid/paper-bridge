require "test_helper"

class Documents::SearchAccessProfileTest < ActiveSupport::TestCase
  test "family admin can search every chunk label" do
    profile = Documents::SearchAccessProfile.for(users(:family_admin), account: accounts(:greenfield))

    assert_equal DocumentChunk::LABELS, profile.allowed_chunk_labels
    assert_equal Document.categories.keys, profile.allowed_document_categories
  end

  test "account members can search every chunk label and document category" do
    profile = Documents::SearchAccessProfile.for(
      users(:account_member),
      account: accounts(:greenfield),
      dependent: dependents(:emma)
    )

    assert_equal "member", profile.role
    assert_equal DocumentChunk::LABELS, profile.allowed_chunk_labels
    assert_equal Document.categories.keys, profile.allowed_document_categories
  end

  test "care team contacts do not grant search access to a user with the same email" do
    assert_equal care_team_memberships(:emma_therapist).email, users(:therapist).email

    profile = Documents::SearchAccessProfile.for(
      users(:therapist),
      account: accounts(:greenfield),
      dependent: dependents(:emma)
    )

    assert_empty profile.allowed_chunk_labels
    assert_empty profile.allowed_document_categories
  end

  test "care team contacts do not grant search access without a dependent" do
    profile = Documents::SearchAccessProfile.for(users(:therapist))

    assert_empty profile.allowed_chunk_labels
    assert_empty profile.allowed_document_categories
  end

  test "an admin from another account has no search access" do
    profile = Documents::SearchAccessProfile.for(users(:other_user), account: accounts(:greenfield))

    assert_empty profile.allowed_chunk_labels
    assert_empty profile.allowed_document_categories
  end

  test "dependent scopes account membership when no account is provided" do
    profile = Documents::SearchAccessProfile.for(users(:other_user), dependent: dependents(:emma))

    assert_empty profile.allowed_chunk_labels
    assert_empty profile.allowed_document_categories
  end

  test "a missing actor has no search access" do
    profile = Documents::SearchAccessProfile.for(nil, account: accounts(:greenfield))

    assert_empty profile.allowed_chunk_labels
    assert_empty profile.allowed_document_categories
  end

  test "teacher role is limited to school-relevant labels" do
    profile = Documents::SearchAccessProfile.new(role: "teacher")

    assert_equal %w[education behavior general], profile.allowed_chunk_labels
    assert_equal %w[educational general], profile.allowed_document_categories
    assert profile.allows_label?("education")
    assert_not profile.allows_label?("medical")
  end

  test "unknown roles default to general chunks only" do
    profile = Documents::SearchAccessProfile.new(role: "unknown")

    assert_equal %w[general], profile.allowed_chunk_labels
    assert_equal %w[general], profile.allowed_document_categories
  end
end
