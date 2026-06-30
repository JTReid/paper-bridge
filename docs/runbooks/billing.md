# Billing Runbook

This runbook defines the Stripe billing foundation that exists in PaperBridge
today.

## Implemented Surface

- Billing is account-level. `BillingSubscription` belongs to one `Account` and
  records Stripe customer, subscription, price, status, period end,
  cancellation, and latest webhook event state.
- `Account#subscription_active?` is the current paid-access predicate. Active
  and trialing subscriptions grant access.
- `SubscriptionGate` exposes `require_subscription!` for controller-level paid
  gates.
- Signed-in account users are globally redirected to `/billing` when their
  account is not active or trialing. Billing, Checkout, and Customer Portal
  routes are exempt so inactive users can subscribe.
- Super admins are platform users with `User#site_role` set to
  `super_admin`. They bypass subscription gates and can access the account
  billing overview.
- `/billing` shows the current account's billing state and starts hosted Stripe
  Checkout when `stripe.price_id` is configured.
- `/billing/portal_session` starts Stripe's hosted Customer Portal when the
  account has a Stripe customer ID.
- `/stripe/webhooks` is mounted through StripeEvent. Webhook requests require a
  Stripe signing secret before they can be verified.
- `Billing::StripeWebhookHandler` syncs checkout completion, subscription
  lifecycle events, and failed invoice payment state back to
  `BillingSubscription`.
- `/admin/accounts` lets super admins review billing status across accounts.

## Configuration

Stripe settings live in encrypted Rails credentials, with environment variables
available as deployment overrides:

```yaml
stripe:
  secret_key: sk_test_...
  publishable_key: pk_test_...
  webhook_secret: whsec_...
  standard_price: price_...
```

Checkout is unavailable until `secret_key` and a subscription price are present.
The app reads `stripe.standard_price`, with `stripe.price_id` and
`STRIPE_PRICE_ID` supported as aliases. Webhooks are mounted but cannot verify
incoming Stripe requests until `webhook_secret` is present.

## Validation

Run the billing harness command:

```bash
ruby scripts/paper_bridge_harness.rb billing
```

Before broader product-shape changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
