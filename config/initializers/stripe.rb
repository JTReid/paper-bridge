require Rails.root.join("app/services/billing/stripe_config").to_s
require Rails.root.join("app/services/billing/stripe_webhook_handler").to_s

Stripe.api_key = Billing::StripeConfig.secret_key
StripeEvent.signing_secret = Billing::StripeConfig.webhook_secret

StripeEvent.configure do |events|
  webhook_handler = Billing::StripeWebhookHandler.new

  events.subscribe "checkout.session.completed", webhook_handler
  events.subscribe "customer.subscription.created", webhook_handler
  events.subscribe "customer.subscription.updated", webhook_handler
  events.subscribe "customer.subscription.deleted", webhook_handler
  events.subscribe "invoice.payment_failed", webhook_handler
end
