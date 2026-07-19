require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "renders an attached dependent avatar through the authenticated endpoint" do
    dependent = dependents(:emma)
    attach_avatar(dependent)

    html = dependent_avatar(
      dependent,
      class_name: "h-12 w-12 rounded-full",
      testid: "profile-avatar"
    )
    image = Nokogiri::HTML.fragment(html).at_css("img[data-testid='profile-avatar']")

    assert_equal avatar_dependent_path(dependent), image["src"]
    assert_equal "Emma Greenfield profile photo", image["alt"]
    assert_equal "128", image["width"]
    assert_equal "128", image["height"]
    assert_includes image["class"], "object-cover"
  end

  test "renders initials when a dependent has no avatar" do
    dependent = dependents(:emma)

    html = dependent_avatar(
      dependent,
      class_name: "h-12 w-12 rounded-full",
      fallback_class_name: "bg-blue-50 text-blue-700",
      testid: "profile-avatar"
    )
    placeholder = Nokogiri::HTML.fragment(html).at_css("span[data-testid='profile-avatar']")

    assert_equal "EG", placeholder.text
    assert_equal "img", placeholder["role"]
    assert_equal "Emma Greenfield photo placeholder", placeholder["aria-label"]
    assert_includes placeholder["class"], "bg-blue-50"
  end

  test "uses a stable fallback for a blank dependent name" do
    assert_equal "U", dependent_initials(Dependent.new)
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
