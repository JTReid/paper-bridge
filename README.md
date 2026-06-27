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

Document sharing uses ActionMailer. Production is configured for Amazon SES
through SMTP. Store the SES SMTP username and password in encrypted Rails
credentials:

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
