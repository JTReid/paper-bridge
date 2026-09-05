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
  preserves any active trial, immediately invoices prorated increases after the
  trial, and schedules decreases for the end of the current billing period.
  Cancellation also takes effect at period end.
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

## Launch Trial

- The opt-in launch offer gives a new family account 90 days free for its entire
  selected profile allowance, including profiles above five. This is 90 days
  from subscription creation, not three calendar months or a shared launch-end
  date. The existing paid Price stays unchanged; there is no coupon, separate
  free Price, or manual discount-removal job.
- Hosted Checkout requests `subscription_data.trial_period_days: 90` and
  `payment_method_collection: always`. Customers provide card details before
  access starts and Stripe charges the normal monthly amount after the trial
  unless they cancel. A dedicated company-account Payment Method Configuration
  enables only cards and card-backed Apple Pay/Google Pay; Checkout receives its
  ID through `payment_method_configuration`. The company default configuration
  is not changed. The app does not hardcode `payment_method_types` or handle
  card data.
  If the payment method is missing when the trial ends, Stripe cancels the
  subscription rather than leaving an unpaid, indefinitely usable trial.
- The offer is once per family account, not once per login or managed profile.
  Eligibility requires a new subscription with no recorded subscription/price,
  billing period, cancellation, or trial history. Existing paying or previously
  subscribed accounts do not receive a new trial. This is account-level
  eligibility, not cross-account identity or card-fingerprint abuse detection.
- `BillingSubscription#launch_trial_used_at` is set only when an accepted,
  signature-verified subscription lifecycle webhook establishes trial history.
  Merely opening, abandoning, or returning from Checkout does not consume the
  offer or grant access. The durable marker prevents later lifecycle updates
  that clear `trial_end` from restoring eligibility.
- Each Checkout attempt pins its trial offer and Payment Method Configuration
  ID alongside price, quantity, and idempotency token. Retrying that attempt
  keeps the same terms even if the configured IDs or launch flag change.
  Attempts created before trial support, without these pinned settings, retain
  their original paid parameters. Expired sessions can be replaced with a fresh
  attempt under the then-current eligibility and offer settings.
- Billing displays the free period, first-payment date when available, and
  normal recurring amount for the saved profile allowance. Active trials use
  the same webhook-controlled access and profile limits as paid subscriptions.
- The dedicated Portal must explicitly return
  `features.subscription_update.trial_update_behavior: continue_trial`; Stripe's
  default can end a trial when the customer changes quantity. Setup uses a
  separate Portal version and idempotency key while retaining the existing
  Price lookup. It never silently reuses or edits the earlier Portal policy.

### Trial-End Reminder Setup

In the company Stripe Dashboard's **Subscriptions and emails** settings, enable
the reminder seven days before a free trial ends and configure a Stripe-hosted
management/payment-details link. Verify customer-facing trial terms, regular
pricing, and cancellation information before launch. This is Stripe account
configuration, not a PaperBridge reminder job or an automatically applied
setting from the setup script. Manual confirmation of this Dashboard setting
remains a launch prerequisite; local trial setup does not establish it is on.

Sandbox email delivery is limited and is not proof of production delivery.
Stripe's customer-email documentation permits some sandbox notifications only
to verified-domain or active-team-member addresses; its Checkout trial guide
also warns that sandbox trial reminders are not sent. Confirm the production
reminder setting and delivery separately; a passing local billing test cannot
verify it. See [Stripe-hosted Checkout trials](https://docs.stripe.com/payments/checkout/free-trials?payment-ui=stripe-hosted),
[trial-ending reminders](https://docs.stripe.com/billing/revenue-recovery/customer-emails#trial-ending-reminders),
and [trial disclosure and reminder requirements](https://docs.stripe.com/billing/subscriptions/trials/manage-trial-compliance).

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
  price, starting quantity, trial terms, and idempotency token across uncertain
  API errors.
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
  secret_key: rk_test_...
  publishable_key: pk_test_...
  webhook_secret: whsec_...
  standard_price: price_...
  profile_price: price_...
  profile_portal_configuration: bpc_...
  payment_method_configuration: pmc_...
  launch_trial_enabled: false
```

Checkout is unavailable until `secret_key`, `profile_price`, and
`profile_portal_configuration` are present. Environment overrides are
`STRIPE_PROFILE_PRICE_ID` and `STRIPE_PROFILE_PORTAL_CONFIGURATION_ID`.
When the launch flag is enabled, Checkout also requires
`payment_method_configuration`, overridden by
`STRIPE_PAYMENT_METHOD_CONFIGURATION_ID`. It must identify the separately
verified card-only configuration in the same company account and environment.
The old `standard_price` / `price_id` / `STRIPE_PRICE_ID` remains available for
legacy integration compatibility; do not point the new setting at that old
flat Price. Webhooks cannot verify requests until `webhook_secret` is present.
`launch_trial_enabled` defaults to false and is overridden by
`STRIPE_LAUNCH_TRIAL_ENABLED`; only an explicit true value enables new trial
offers. Enable it separately for each intended environment after configuring
the trial-preserving Portal, card-only payment methods, and reminders. Turning
it off does not terminate existing trials or alter an already-pinned Checkout
attempt.
The Stripe Ruby SDK is updated independently of the explicitly pinned
`2026-06-24.dahlia` request version. This does not change the account's default
API version or any existing webhook endpoint version.

## Local Setup And Rollout

1. Run `bin/rails db:migrate`. The earlier profile-plan migration adds nullable
   allowance and event timestamp columns plus a minimum-five constraint. The
   launch-trial migration adds nullable `launch_trial_used_at`. Both are
   schema-only changes: no data backfill, remote Stripe mutation, or migration
   of existing subscriptions is performed.
2. Using the intended company's Stripe test credentials, run:

   ```bash
   bin/rails runner scripts/setup_stripe_profile_plan.rb --confirm-test-mode
   ```

   Prefer a restricted test key with the required catalog and Portal permissions.
   The script rejects live/missing/unrecognized keys and requires explicit
   confirmation. It creates or reuses tagged test objects, verifies the pricing
   and Portal rules, and prints only nonsecret configuration IDs. Reruns do not
   modify existing objects, subscriptions, or the default Portal. The existing
   `paperbridge_managed_profiles_monthly_v1` Price is reused when it matches;
   the separate `paperbridge_managed_profiles_trial_v2` Portal configuration
   must preserve trials. Legacy Portal configurations are left untouched, and
   mismatched or duplicate current-version dedicated configurations are refused.
   In an empty Stripe account, Stripe makes the first created Portal the default.
   Setup leaves that new default untouched and creates a second, dedicated
   configuration with a distinct idempotency key. Reruns ignore default Portals;
   the returned runtime configuration must always be nondefault.
3. Separately create and verify a dedicated card-only Payment Method
   Configuration in the company test account. Enable `card`, `apple_pay`, and
   `google_pay`, and disable other methods in that dedicated configuration;
   leave the account default unchanged. The profile-plan setup script does not
   create this configuration. Supply its ID as `payment_method_configuration`
   along with the returned Price/Portal IDs in local environment overrides or
   encrypted development credentials, then restart the local app. Keep test IDs
   and keys out of committed plaintext configuration. Configure signed test
   webhook forwarding separately when testing the full hosted
   return/activation workflow.
   `bin/dev` loads ignored `.env` settings through Foreman; plain `bin/rails`
   commands require the overrides to be exported in their shell.
   Set the launch flag explicitly when testing the free offer. Use the new
   trial-preserving Portal ID, not the prior configuration ID.
4. Before production rollout, create and verify the equivalent live Price and
   dedicated Portal and card-only Payment Method Configurations, deploy the
   schema/code, and supply the live IDs. Confirm the reminder settings in that
   live account, then explicitly enable the launch flag. The test setup script
   deliberately cannot perform live setup. Do not migrate existing paying
   subscriptions without a separately approved rollout.

### Company-Test Webhook Forwarding

Start the development app and run the listener in a separate terminal. Replace
`acct_COMPANYTEST` with the intended company's test-account ID:

```bash
RAILS_ENV=development bin/rails runner scripts/stripe_test_webhooks.rb --confirm-test-mode --account acct_COMPANYTEST
```

The default target is `http://127.0.0.1:3000/stripe/webhooks`; add `--port 3001`
if the local app uses that port. This command requires the Stripe CLI and only
supports local development with a test-mode restricted/secret key.

The runner uses the same effective `Billing::StripeConfig` credentials as the
app, including any environment overrides. It verifies the configured key's
Stripe account matches the explicit `--account`, passes that key to the CLI
through the child process environment rather than command-line arguments, and
checks the listener's signing secret matches the app before forwarding. Keys
and `whsec_...` values are redacted from listener output. If the signing secret
differs, update encrypted development credentials through the secure local
workflow and restart the app; do not paste secrets into chat or tracked files.

Do not use the Stripe CLI's personal/default login for this workflow. The
explicit company-account check prevents silently forwarding events from the
wrong Stripe account. The listener forwards the five event types handled in
the Stripe initializer; it does not create a Checkout payment, enable reminder
emails, or establish a production webhook endpoint.

### Switching Stripe Accounts Or Environments

API keys, catalog IDs, Portal and Payment Method Configuration IDs, and webhook
signing secrets must belong to the same intended Stripe account and test/live
environment. Replacing keys
does not migrate existing `stripe_customer_id`, `stripe_subscription_id`, or
cached Checkout session IDs in PaperBridge. IDs from the previous account can
therefore fail under the new key. Use a fresh family account for a new-company
test signup; any existing-account reconciliation needs a separately scoped
decision. Do not clear billing records or grant a replacement trial as an
automatic side effect of swapping credentials.

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

For a focused Portal setup check without Stripe calls:

```bash
bin/rails test test/services/billing/profile_plan_setup_test.rb
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

Before rollout, separately verify an actual company-test hosted signup with
payment details, signed subscription webhooks, trial access and allowance,
quantity changes without an early charge, cancellation before trial end, and
the first paid renewal. Local stubbed API tests and simulated browser states
do not establish that this full remote round trip or reminder delivery passed.

Before broader product-shape changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
