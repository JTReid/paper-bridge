require "test_helper"

class BillingPortalSessionsControllerTest < ActionDispatch::IntegrationTest
  test "requires an account admin" do
    sign_in users(:account_member)

    post billing_portal_session_path

    assert_redirected_to billing_path
    assert_equal "Only the person who manages billing can change this subscription.", flash[:alert]
  end

  test "redirects when portal is not available" do
    sign_in users(:family_admin)

    post billing_portal_session_path

    assert_redirected_to billing_path
    assert_equal "Billing settings aren’t available right now.", flash[:alert]
  end

  test "redirects super admins without an account before portal" do
    sign_in users(:super_admin)

    post billing_portal_session_path

    assert_redirected_to admin_accounts_path
    assert_equal "We couldn’t find a family account for this sign-in.", flash[:alert]
  end

  test "creates a stripe portal session" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(stripe_customer_id: "cus_test_123", status: :active)
    sign_in users(:family_admin)

    portal_session = lambda do |**params|
      assert_equal "cus_test_123", params[:customer]
      assert_equal billing_url, params[:return_url]
      assert_not_includes params, :configuration
      Struct.new(:url).new("https://billing.stripe.test/session")
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :portal_ready?, true) do
      with_stubbed_singleton_method(Stripe::BillingPortal::Session, :create, portal_session) do
        post billing_portal_session_path
      end
    end

    assert_redirected_to "https://billing.stripe.test/session"
  end

  test "profile plan subscribers use their dedicated portal configuration" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(stripe_customer_id: "cus_profile_123", profile_limit: 5)
    sign_in users(:family_admin)

    creator = lambda do |**params|
      assert_equal "cus_profile_123", params[:customer]
      assert_equal "bpc_profiles_123", params[:configuration]
      assert_equal billing_url, params[:return_url]
      Struct.new(:url).new("https://billing.stripe.test/profiles")
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :portal_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :profile_portal_configuration_id, "bpc_profiles_123") do
        with_stubbed_singleton_method(Stripe::BillingPortal::Session, :create, creator) do
          post billing_portal_session_path
        end
      end
    end

    assert_redirected_to "https://billing.stripe.test/profiles"
  end

  test "profile subscribers cannot fall back to the legacy portal when configuration is missing" do
    accounts(:greenfield).billing_subscription.update!(stripe_customer_id: "cus_profile_123", profile_limit: 5)
    sign_in users(:family_admin)

    with_stubbed_singleton_method(Billing::StripeConfig, :secret_key, "sk_test_placeholder") do
      with_stubbed_singleton_method(Billing::StripeConfig, :profile_portal_configuration_id, nil) do
        with_stubbed_singleton_method(Stripe::BillingPortal::Session, :create, ->(*) { flunk "Must not open the legacy portal" }) do
          post billing_portal_session_path
        end
      end
    end

    assert_redirected_to billing_path
    assert_equal "Billing settings aren’t available right now.", flash[:alert]
  end

  test "Stripe portal failures log their class without exposing the remote message" do
    account = accounts(:greenfield)
    account.billing_subscription.update!(stripe_customer_id: "cus_test_123")
    sign_in users(:family_admin)
    messages = []
    remote_message = "Invalid API Key provided: sensitive-credential-placeholder"
    failure = ->(*) { raise Stripe::AuthenticationError, remote_message }

    with_stubbed_singleton_method(Billing::StripeConfig, :portal_ready?, true) do
      with_stubbed_singleton_method(Stripe::BillingPortal::Session, :create, failure) do
        with_stubbed_singleton_method(Rails.logger, :error, ->(message) { messages << message }) do
          post billing_portal_session_path
        end
      end
    end

    assert_redirected_to billing_path
    assert_equal "We couldn’t open billing settings. Please try again.", flash[:alert]
    assert_equal [ "stripe_portal_failed account_id=#{account.id} error_class=Stripe::AuthenticationError" ], messages
    assert_not_includes response.body, remote_message
  end
end
