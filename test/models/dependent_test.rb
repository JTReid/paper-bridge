require "test_helper"

class DependentTest < ActiveSupport::TestCase
  test "accepts a supported profile avatar" do
    dependent = Dependent.new(account: accounts(:greenfield), name: "Avatar Profile")
    attach_avatar(dependent)

    assert dependent.valid?
    assert dependent.avatar.attached?
    assert dependent.avatar.variable?
  end

  test "defines a square display avatar variant" do
    variant = Dependent.attachment_reflections.fetch("avatar").named_variants.fetch(:display)

    assert_equal({ resize_to_fill: [ 256, 256 ] }, variant.transformations)
  end

  test "rejects unsupported profile avatar content types" do
    dependent = Dependent.new(account: accounts(:greenfield), name: "Avatar Profile")
    dependent.avatar.attach(
      io: StringIO.new("plain text"),
      filename: "avatar.txt",
      content_type: "text/plain"
    )

    assert_not dependent.valid?
    assert_includes dependent.errors[:avatar], "must be a JPEG, PNG, or WebP image"
  end

  test "rejects profile avatars larger than five megabytes" do
    dependent = Dependent.new(account: accounts(:greenfield), name: "Avatar Profile")
    dependent.avatar.attach(
      io: StringIO.new("a" * (Dependent::AVATAR_MAX_SIZE + 1)),
      filename: "large-avatar.png",
      content_type: "image/png"
    )

    assert_not dependent.valid?
    assert_includes dependent.errors[:avatar], "must be smaller than 5 MB"
  end

  private

    def attach_avatar(dependent)
      dependent.avatar.attach(
        io: Rails.root.join("public/icon.png").open,
        filename: "icon.png",
        content_type: "image/png"
      )
    end
end
