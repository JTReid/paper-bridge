require "test_helper"

class Documents::SearchAccessProfileTest < ActiveSupport::TestCase
  test "family admin can search every chunk label" do
    profile = Documents::SearchAccessProfile.for(users(:family_admin), account: accounts(:greenfield))

    assert_equal DocumentChunk::LABELS, profile.allowed_chunk_labels
    assert_equal Document.categories.keys, profile.allowed_document_categories
  end

  test "care team access is limited by category permissions" do
    profile = Documents::SearchAccessProfile.for(
      users(:therapist),
      account: accounts(:greenfield),
      dependent: dependents(:emma)
    )

    assert_equal %w[behavior general medical therapy], profile.allowed_chunk_labels.sort
    assert_equal %w[general medical therapy], profile.allowed_document_categories.sort
    assert profile.allows_label?("therapy")
    assert_not profile.allows_label?("education")
    assert profile.allows_category?("medical")
    assert_not profile.allows_category?("insurance")
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
