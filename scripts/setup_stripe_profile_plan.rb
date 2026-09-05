# This opt-in task only creates/reuses test-mode catalog/configuration objects.
# It never changes existing subscriptions or the default Customer Portal.
unless ARGV == [ "--confirm-test-mode" ]
  abort "Usage: bin/rails runner scripts/setup_stripe_profile_plan.rb --confirm-test-mode (test-mode Stripe key required)"
end

begin
  result = Billing::ProfilePlanSetup.new.call(confirm_test_mode: true)
  puts "Stripe test-mode profile plan is ready. Configure these values for local/test use:"
  puts "STRIPE_PROFILE_PRICE_ID=#{result.fetch(:price_id)}"
  puts "STRIPE_PROFILE_PORTAL_CONFIGURATION_ID=#{result.fetch(:portal_configuration_id)}"
rescue Billing::ProfilePlanSetup::ConfigurationError => error
  abort error.message
rescue Stripe::StripeError => error
  # Never echo request objects, credentials, or remote error messages.
  abort "Stripe test setup failed (#{error.class.name}). Check test-mode permissions and the Stripe request log."
end
