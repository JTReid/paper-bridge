require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  VIDEO_URL = "https://paper-bridge-public-media.s3.us-east-1.amazonaws.com/marketing/meet-paperbridge-v1.mp4".freeze

  test "shows public entry actions" do
    get root_path

    assert_response :success
    assert_select "a[href='#{root_path}'][aria-label='PaperBridge home'] img[alt='PaperBridge']"
    %w[nav mobile].each do |location|
      assert_select "a[data-testid='home-#{location}-secondary'][href='#{new_user_session_path}']", text: "Sign In"
      assert_select "a[data-testid='home-#{location}-primary'][href='#{new_user_registration_path}']", text: "Get Started"
    end
    assert_select "a[data-testid='home-hero-primary'][href='#{new_user_registration_path}']", text: /Get Started/
    assert_select "a[href='#{new_user_registration_path}']", text: /Start with PaperBridge/
    assert_select "a[href='#{dashboard_path}']", count: 0
    assert_select "a[data-marketing-video-target='trigger'][href='#{VIDEO_URL}'][aria-haspopup='dialog'][data-turbo='false']", text: /Meet PaperBridge/
    assert_select "#how-it-works"
  end

  test "describes the product and its approved privacy boundaries" do
    get root_path

    assert_response :success
    [ "Document Library", "PaperBridge Summaries", "Care Team" ].each do |feature|
      assert_select "#features h3", text: feature
    end
    assert_select "#privacy" do
      assert_select "h3", text: "Your family’s own space"
      assert_select "h3", text: "Answers stay with the right Profile"
      assert_select "h3", text: "Protected connection"
      assert_select "h3", text: "Privacy-first design"
      assert_select "p", text: "Your records stay behind sign-in and separate from other families’ accounts."
      assert_select "p", text: "Ask PaperBridge searches only the records belonging to the Profile you’re viewing."
      assert_select "p", text: "PaperBridge requires a secure HTTPS connection while you use the app."
      assert_select "h3", text: "Parent-controlled sharing", count: 0
      assert_select "h3", text: "Read-only access", count: 0
      assert_select "h3", text: "Choose which records to share", count: 0
    end
  end

  test "shows workspace actions for signed in users" do
    sign_in users(:family_admin)

    get root_path

    assert_response :success
    %w[nav mobile].each do |location|
      assert_select "a[data-testid='home-#{location}-primary'][href='#{dashboard_path}']", text: "Dashboard"
      assert_select "[data-testid='home-#{location}-secondary']", count: 0
    end
    assert_select "a[href='#{dashboard_path}']", text: /Start with PaperBridge/
    assert_select "[data-testid='home-hero-primary']", count: 0
    assert_select "a[href='#{new_user_session_path}'], a[href='#{new_user_registration_path}']", count: 0
    assert_select "a[data-marketing-video-target='trigger'][href='#{VIDEO_URL}']", text: /Meet PaperBridge/
  end
end
