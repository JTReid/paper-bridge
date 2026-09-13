# Encrypted Credentials

PaperBridge can select encrypted credentials independently of `RAILS_ENV`.
Use `RAILS_ENV=production` for both Heroku staging and production apps;
`CREDENTIALS_ENV` chooses which secrets each app loads.

The exact variable name includes the `S`: `CREDENTIAL_ENV` is not recognized.
The development and production encrypted files already exist, with separate
decryption keys. Configure `paper-bridge-staging` with development credentials
for Stripe test mode and `paper-bridge-production` with production credentials
for Stripe live mode. Local file contents do not establish which settings are
deployed; track rollout checks in the
[Stripe and Heroku Environment Checklist](../../../paper-bridge-to-dos/stripe-production-checklist.md).

## File Selection

| `CREDENTIALS_ENV` | Encrypted file | Local decryption key |
| --- | --- | --- |
| `development` | `config/credentials/development.yml.enc` | `config/credentials/development.key` |
| `production` | `config/credentials/production.yml.enc` | `config/credentials/production.key` |

The staging app uses the existing development file; it does not need a separate
`staging.yml.enc` file.

The selector is applied in `config/application.rb`, before environment settings
and initializers read credentials. Application code continues to use
`Rails.application.credentials`.

If `CREDENTIALS_ENV` is unset or blank, Rails keeps its default behavior: use
`config/credentials/<RAILS_ENV>.yml.enc` if it exists, otherwise use
`config/credentials.yml.enc`.

Set `CREDENTIALS_ENV=development` explicitly on `paper-bridge-staging`.
Without it, that app's `RAILS_ENV=production` selects the production credential
file, which could load live Stripe settings.

An explicit selector does not fall back to the shared file. Each selected file
must contain its environment's complete credentials; Rails 8.1 does not merge
it with the shared file. Keep the same setting names inside each file, without
a `development:`, `staging:`, or `production:` wrapper.

## Create Or Edit Each Set

Run these locally with your editor configured, for example
`export EDITOR="code --wait"`:

```bash
env -u RAILS_MASTER_KEY RAILS_ENV=development CREDENTIALS_ENV=development bin/rails credentials:edit
env -u RAILS_MASTER_KEY RAILS_ENV=development CREDENTIALS_ENV=production bin/rails credentials:edit
```

Keep `PAPER_BRIDGE_DEV_MAILER` unset while creating credentials. These commands
use development mode so creating or repairing production credentials does not
depend on the production email settings already being present. The explicit
`CREDENTIALS_ENV` chooses the file being edited; do not combine it with a
different `--environment` flag.

Unsetting `RAILS_MASTER_KEY` lets Rails generate a separate key for each new
file, or use its existing local key when editing. An inherited
`RAILS_MASTER_KEY` would take precedence over those local keys. Keep a private
backup of each key. Commit only the encrypted `.yml.enc` files; `.key` files
are already ignored by Git.

Populate each file with that environment's values. Production mode requires
`mailer_from`, `aws.ses_region` or `aws.region`, `aws.ses_access_key`, and
`aws.ses_secret_key` before boot. Include the S3, billing, and AI credentials
needed by the app, and retain the generated `secret_key_base` for each new
deployed environment. See [Production Email](../../README.md#production-email)
and [Billing](billing.md) for the existing setting names. When migrating an
existing deployment, preserve its effective `secret_key_base` to avoid
invalidating sessions; Heroku may already supply it as `SECRET_KEY_BASE`.

## Heroku Configuration

Populate the encrypted files and set these config vars in each Heroku app
before deploying:

| Setting | Staging app | Production app |
| --- | --- | --- |
| Heroku app | `paper-bridge-staging` | `paper-bridge-production` |
| `RAILS_ENV` | `production` | `production` |
| `CREDENTIALS_ENV` | `development` | `production` |
| `RAILS_MASTER_KEY` | Contents of `config/credentials/development.key` | Contents of `config/credentials/production.key` |
| `APP_HOST` | `paper-bridge-staging-13477c3cf41f.herokuapp.com` | `paperbridgeadvocacy.com` |
| Stripe mode | Test | Live |
| S3 bucket (`aws.bucket`) | `paper-bridge-development` | `paper-bridge-production` |

Use a different decryption key for each environment. `RAILS_MASTER_KEY`
decrypts the file chosen by `CREDENTIALS_ENV`; the key does not select the file.
Heroku workers use the same app config vars as web dynos. Existing per-service
environment overrides still apply where the app supports them.

Use separate database attachments and S3 buckets for the two apps. During the
initial split, staging received a verified copy of the existing dummy database;
it does not share the original database attachment. Production uses a fresh
database. Both S3 buckets are in `us-east-1`; staging keeps the original uploads
in `paper-bridge-development`, while production uses `paper-bridge-production`.
The checklist records which activation and deployment checks are complete.

Each Stripe mode needs its own hosted webhook endpoint and signing secret.
Store the hosted staging secret in development credentials; for local Stripe
CLI forwarding, use the listener's secret through a temporary
`STRIPE_WEBHOOK_SECRET` override in both the local Rails server and the
forwarding process. The CLI secret does not
belong in the Heroku app's configuration.

### Fresh Database With Shared Solid Storage

When primary, queue, cache, and cable share one physical Heroku database, use
Heroku-managed attachments for all four connection URLs so they follow database
credential changes together. Verify the running Rails roles resolve to the
intended database after promotion.

For a fresh shared database with no Solid tables, initialize `db/queue_schema.rb`,
`db/cache_schema.rb`, and `db/cable_schema.rb` once after application migrations
and before starting web and worker processes. Application migrations alone do
not create these schema-defined tables. This bootstrap created 11 queue tables,
one cache table, and one cable table in the fresh production database. Do not
reload these schemas over existing Solid data; this is initial database setup,
not a routine release step.
