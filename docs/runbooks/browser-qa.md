# Browser QA Runbook

This runbook covers Playwright-based browser checks.

## Structure

```text
tests/e2e/
  helpers/
  smoke/
  product/
  regressions/
```

- `helpers/` contains shared browser helpers such as sign-in.
- `smoke/` contains fast boot/navigation checks.
- `product/` contains current product workflow checks.
- `regressions/` is for focused bug reproduction specs that should remain after
  a fix.

## Environment

The QA harness sets:

- `RAILS_ENV=test`
- `QA_BASE_URL=http://127.0.0.1:3100` by default
- `QA_ARTIFACT_MODE=always` for `bughunt`
- `QA_ARTIFACT_DIR=tmp/qa-artifacts/bugs/<bug-id>` for named bug hunts
- `QA_MAILPIT=true` on the Rails test server only for Mailpit email QA runs
- `QA_MAILPIT_API_URL=http://127.0.0.1:8025` for Playwright Mailpit API checks

Specs should use `data-testid` anchors for controls that are likely to be
reused in QA scenarios. Prefer accessible roles and labels for user-facing
assertions, and use test IDs for disambiguating repeated links, form fields, and
workflow buttons.

Shared browser diagnostics fail tests on uncaught page errors, console errors,
failed browser requests, and HTTP responses with status `>= 500`.

Shared accessibility checks use `@axe-core/playwright`.

Mailpit email checks use the same Rails test database and browser server, but
temporarily route Action Mailer to local Mailpit SMTP. Start Mailpit before
running the mode:

```bash
mailpit --smtp 127.0.0.1:1025 --listen 127.0.0.1:8025
ruby scripts/paper_bridge_qa_harness.rb mailpit
```

Run Playwright through the QA harness unless you are iterating on a single spec.
The harness prepares the DB, loads fixtures, builds Tailwind, starts Rails, and
then runs Playwright.

The test DB prep also loads the synthetic QA seed corpus. Specs that need the
seeded account can sign in as `qa-family-admin@example.test / password` and use
the `Avery Morgan` workspace.

## Direct Playwright Iteration

When a QA server is already running, a single spec can be run directly:

```bash
QA_BASE_URL=http://127.0.0.1:3100 npx playwright test tests/e2e/product/document_sharing.spec.js --project=chromium
```

For bug recording:

```bash
QA_ARTIFACT_MODE=always QA_ARTIFACT_DIR=tmp/qa-artifacts/bugs/share-modal QA_BASE_URL=http://127.0.0.1:3100 npx playwright test --project=chromium
```
