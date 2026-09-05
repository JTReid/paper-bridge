# Billing Runbook

This runbook defines PaperBridge's hosted Stripe subscription flow and managed
profile allowance.

## Managed Profile Plan

- USD $25/month includes up to five managed profiles. Each profile beyond five
  adds $5/month: five costs $25, six $30, seven $35, and ten $50.
- This is one licensed recurring Price with graduated tiers: a $25 flat first
  tier through quantity five, then $5 per unit above five. Account logins and
  care team members are not billing units.
- Hosted Checkout starts at five (or the current profile count, if higher) and
  lets customers adjust quantity there. No custom plan-selection/payment page
  is added. Quantity has a minimum of five because the base plan always buys
  five slots; the 999,999 maximum is Stripe's technical quantity bound, not the
  separate 50-file upload-batch limit.
- A dedicated hosted Customer Portal configuration permits quantity updates,
  immediately invoices prorated increases, and schedules decreases for the end
  of the current billing period. Cancellation also takes effect at period end.
  While a downgrade is scheduled, Stripe's hosted flow offers cancellation of
  the scheduled change before making a different change. Users keep their
  current allowance until the schedule applies.
- Stripe's current subscription item is the allowance authority. Pending
  updates and future schedule quantities are not applied early. Webhook
  quantities are saved to `BillingSubscription#profile_limit` and must be
  positive integers; quantities below five still include five slots.
  A failed upgrade invoice does not itself revoke the existing paid plan;
  subscription lifecycle events decide the resulting status and quantity.
- Only profile creation is limited. At/over capacity the app blocks adding
  another profile, including simultaneous requests, but existing profiles,
  documents, profile editing, and deletion remain available under the normal
  paid-access gate. No automatic deletion, archiving, or reassignment occurs.
- A nullable allowance distinguishes legacy subscriptions, which retain their
  existing behavior. There is no data backfill or automatic Stripe subscription
  migration. New Checkout uses separate profile-price settings, and legacy
  subscriptions continue to use the existing default Portal configuration.

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
- `/billing` shows the current account's billing state, managed-profile usage,
  and the new plan's pricing where applicable. Checkout requires the new profile
  price and dedicated Portal configuration. Existing nonterminal subscriptions
  are directed to management instead of allowing a second subscription.
- Successful Checkout returns to `/dashboard?checkout=success`. Until Stripe
  reports a decisive subscription result, the route renders a locked activation
  state with no product data and subscribes to an account-scoped Turbo stream.
  The waiting page does not poll.
- Starting Checkout records a temporary pending marker in the existing billing
  metadata. A decisive subscription lifecycle or failed-invoice webhook clears
  that marker and broadcasts a Turbo page refresh. Stripe's provisional
  `incomplete` state keeps waiting; active or trialing accounts enter the
  dashboard with a confirmation, while terminal non-active results return to
  `/billing` with an actionable message. The query parameter and Turbo broadcast
  never grant access themselves.
- Checkout attempts are serialized on the account and keep their selected
  price, starting quantity, and idempotency token across uncertain API errors.
  Repeated requests reuse the open hosted session; completed sessions wait for
  the signed subscription result, and expired sessions can be replaced.
- Canceled Checkout returns to `/billing`, clears the temporary pending marker,
  and confirms that the subscription did not change.
- `/billing/portal_session` starts Stripe's hosted Customer Portal when the
  account has a Stripe customer ID.
- `/stripe/webhooks` is mounted through StripeEvent. Webhook requests require a
  Stripe signing secret before they can be verified.
- `Billing::StripeWebhookHandler` syncs checkout completion, subscription
  lifecycle events, and failed invoice payment state back to
  `BillingSubscription`. Checkout completion only links identity; it cannot
  overwrite a lifecycle webhook's price, allowance, or access status. Older
  timestamped entitlement events and events for a replaced subscription are
  ignored. Profile creations and entitlement writes serialize on the account
  row, and activation broadcasts happen after the write transaction exits.
  Stripe event timestamps have second-level precision; conflicting snapshots
  within the same second trigger a targeted current-subscription lookup instead
  of guessing their order. Ordinary webhooks do not fetch Stripe. A failed
  conflict lookup leaves the saved state intact and lets Stripe retry.
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
  profile_price: price_...
  profile_portal_configuration: bpc_...
```

Checkout is unavailable until `secret_key`, `profile_price`, and
`profile_portal_configuration` are present. Environment overrides are
`STRIPE_PROFILE_PRICE_ID` and `STRIPE_PROFILE_PORTAL_CONFIGURATION_ID`.
The old `standard_price` / `price_id` / `STRIPE_PRICE_ID` remains available for
legacy integration compatibility; do not point the new setting at that old
flat Price. Webhooks cannot verify requests until `webhook_secret` is present.
The Stripe Ruby SDK is updated independently of the explicitly pinned
`2026-06-24.dahlia` request version. This does not change the account's default
API version or any existing webhook endpoint version.

## Local Setup And Rollout

1. Run `bin/rails db:migrate`. The migration adds nullable allowance and event
   timestamp columns plus a minimum-five constraint; it does not rewrite rows.
2. Using the existing Stripe test credentials, run:

   ```bash
   bin/rails runner scripts/setup_stripe_profile_plan.rb --confirm-test-mode
   ```

   Prefer a restricted test key with the required catalog and Portal permissions.
   The script rejects live/missing/unrecognized keys and requires explicit
   confirmation. It creates or reuses tagged test objects, verifies the pricing
   and Portal rules, and prints only nonsecret configuration IDs. Reruns do not
   modify existing objects, subscriptions, or the default Portal.
3. Supply the returned IDs as local environment overrides or encrypted
   development credentials and restart the local app. Keep test IDs and keys
   out of committed configuration. Configure signed test webhook forwarding
   separately when testing the full hosted return/activation workflow.
   `bin/dev` loads ignored `.env` settings through Foreman; plain `bin/rails`
   commands require the overrides to be exported in their shell.
4. Before production rollout, create and verify the equivalent live Price and
   dedicated Portal configuration, deploy the schema/code, and supply the live
   IDs. The test setup script deliberately cannot do this. Do not migrate
   existing paying subscriptions without a separately approved rollout.

The Price uses explicit `tax_behavior: exclusive` because the Portal rejects
quantity changes for unspecified tax behavior. This does not enable Stripe Tax,
add registrations, or change existing tax-collection settings. Tax registration
and collection choices remain a separate production setup decision.

Official configuration references: [graduated pricing](https://docs.stripe.com/subscriptions/pricing-models/tiered-pricing),
[Portal quantity/proration/schedule settings](https://docs.stripe.com/api/customer_portal/configurations/create),
and [Portal limitations](https://docs.stripe.com/customer-management).

## Validation

Run the billing harness command:

```bash
ruby scripts/paper_bridge_harness.rb billing
```

For the browser-visible pending, success, failure, and cancellation states, run:

```bash
ruby scripts/paper_bridge_qa_harness.rb workflow billing
```

The browser harness server uses dummy Stripe credentials/configuration and
cannot charge the configured Stripe account. The workflow uses synthetic
subscription records and a synthetic Turbo refresh. It also exercises the
profile allowance boundary, a simulated upgrade,
and retained access after a simulated renewal-time decrease. It does not call
Stripe or prove hosted payment collection or live webhook-to-WebSocket delivery.

Before broader product-shape changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
