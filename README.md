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

Document sharing uses ActionMailer. Configure outbound SMTP with environment
variables:

```bash
APP_HOST=paperbridge.example.com
MAILER_FROM="PaperBridge <no-reply@paperbridge.example.com>"
SMTP_ADDRESS=smtp.example.com
SMTP_PORT=587
SMTP_DOMAIN=paperbridge.example.com
SMTP_USER_NAME=your-smtp-user
SMTP_PASSWORD=your-smtp-password
SMTP_AUTHENTICATION=plain
SMTP_ENABLE_STARTTLS_AUTO=true
```

On Heroku, set the same values with `heroku config:set`.
