# Encrypted Credentials

PaperBridge can select encrypted credentials independently of `RAILS_ENV`.
Heroku staging and production apps should both use `RAILS_ENV=production`;
`CREDENTIALS_ENV` chooses which secrets each app loads.

The existing shared credentials and master key have been moved to
`config/credentials/production.yml.enc` and `config/credentials/production.key`.
Their contents and decryption key are unchanged, so existing production
deployments can keep the same `RAILS_MASTER_KEY` value. Those values were also
copied into `config/credentials/development.yml.enc`, encrypted with a separate
`development.key`. Both sets currently contain development service settings;
the production set still needs to be updated with production values. Staging
has not been created yet.

## File Selection

| `CREDENTIALS_ENV` | Encrypted file | Local decryption key |
| --- | --- | --- |
| `development` | `config/credentials/development.yml.enc` | `config/credentials/development.key` |
| `staging` | `config/credentials/staging.yml.enc` | `config/credentials/staging.key` |
| `production` | `config/credentials/production.yml.enc` | `config/credentials/production.key` |

The selector is applied in `config/application.rb`, before environment settings
and initializers read credentials. Application code continues to use
`Rails.application.credentials`.

If `CREDENTIALS_ENV` is unset or blank, Rails keeps its default behavior: use
`config/credentials/<RAILS_ENV>.yml.enc` if it exists, otherwise use
`config/credentials.yml.enc`. Existing deployments can keep using the shared
file until their separate credentials are ready.

An explicit selector does not fall back to the shared file. Each selected file
must contain its environment's complete credentials; Rails 8.1 does not merge
it with the shared file. Keep the same setting names inside each file, without
a `development:`, `staging:`, or `production:` wrapper.

## Create Or Edit Each Set

Run these locally with your editor configured, for example
`export EDITOR="code --wait"`:

```bash
env -u RAILS_MASTER_KEY RAILS_ENV=development CREDENTIALS_ENV=development bin/rails credentials:edit
env -u RAILS_MASTER_KEY RAILS_ENV=development CREDENTIALS_ENV=staging bin/rails credentials:edit
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

After populating and deploying the encrypted files, set these config vars in
each Heroku app's settings:

| Setting | Staging app | Production app |
| --- | --- | --- |
| `RAILS_ENV` | `production` | `production` |
| `CREDENTIALS_ENV` | `staging` | `production` |
| `RAILS_MASTER_KEY` | Contents of `config/credentials/staging.key` | Contents of `config/credentials/production.key` |
| `APP_HOST` | Staging hostname | Production hostname |

Use a different decryption key for each environment. `RAILS_MASTER_KEY`
decrypts the file chosen by `CREDENTIALS_ENV`; the key does not select the file.
Heroku workers use the same app config vars as web dynos. Existing per-service
environment overrides still apply where the app supports them.
