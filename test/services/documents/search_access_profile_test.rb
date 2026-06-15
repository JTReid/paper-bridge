require "test_helper"

class Documents::SearchAccessProfileTest < ActiveSupport::TestCase
  test "family admin can search every chunk label" do
    profile = Documents::SearchAccessProfile.for(users(:family_admin))

    assert_equal DocumentChunk::LABELS, profile.allowed_chunk_labels
  end

  test "teacher role is limited to school-relevant labels" do
    profile = Documents::SearchAccessProfile.new(role: "teacher")

    assert_equal %w[education behavior general], profile.allowed_chunk_labels
    assert profile.allows_label?("education")
    assert_not profile.allows_label?("medical")
  end

  test "unknown roles default to general chunks only" do
    profile = Documents::SearchAccessProfile.new(role: "unknown")

    assert_equal %w[general], profile.allowed_chunk_labels
  end
end
