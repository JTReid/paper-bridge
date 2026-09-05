# README

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## Production Email

Document sharing and password resets use ActionMailer with the same configured
`mailer_from` sender. Production is configured for Amazon SES through SMTP.
Store the SES SMTP username and password in encrypted Rails credentials:

```yaml
mailer_from: PaperBridge <no-reply@paperbridge.example.com>
aws:
  region: us-east-1
  ses_access_key: SES_SMTP_USERNAME
  ses_secret_key: SES_SMTP_PASSWORD
```

If SES uses a different region than S3, add `aws.ses_region`.

On Heroku, provide the Rails master key and app-facing mail settings:

```bash
APP_HOST=paperbridge.example.com
RAILS_MASTER_KEY=...
```

`production.rb` derives the SES SMTP endpoint from `aws.ses_region` or
`aws.region`. Production boot fails fast if `mailer_from`, the SES region, SMTP
username, or SMTP password is missing from encrypted credentials.

## Development Email

Development uses Mailpit by default. To send a live SES sandbox email from
development, start Rails with:

```bash
PAPER_BRIDGE_DEV_MAILER=ses bin/rails server
```

SES sandbox sends only work when both the configured `mailer_from` sender and
the recipient are verified SES identities in the configured region.

If SES returns `535 Authentication Credentials Invalid`, the app reached SES but
SMTP authentication failed. Confirm `aws.ses_access_key` is the SES SMTP
username and `aws.ses_secret_key` is the SES SMTP password from SES SMTP
settings in the same region, not the normal AWS access key and secret key used
for S3.

## Stripe Billing

PaperBridge uses the official `stripe` Ruby SDK and `stripe_event` for webhook
dispatch. Store Stripe settings in encrypted Rails credentials:

```yaml
stripe:
  secret_key: sk_test_...
  publishable_key: pk_test_...
  webhook_secret: whsec_...
  standard_price: price_...
  profile_price: price_...
  profile_portal_configuration: bpc_...
```

New subscriptions use hosted Checkout for managed-profile quantities: $25
USD/month includes five profiles, then $5/month per additional profile. Checkout
requires `profile_price` and `profile_portal_configuration`, with
`STRIPE_PROFILE_PRICE_ID` and `STRIPE_PROFILE_PORTAL_CONFIGURATION_ID` environment
overrides. Existing subscriptions are not automatically migrated.
Stripe webhooks require `webhook_secret` before StripeEvent can verify events.
`standard_price`, `stripe.price_id`, and `STRIPE_PRICE_ID` are retained for legacy
compatibility. See [Billing](docs/runbooks/billing.md) for the safe test-only
setup command, schema migration, and production rollout boundary.
