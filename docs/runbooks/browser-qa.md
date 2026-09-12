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
They allow `net::ERR_ABORTED` for identified Turbo prefetches and document-list
background refreshes, which navigation intentionally cancels. Other failed
requests and server errors still fail the test.

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

Mutable workflows should use test-owned records with fixture teardown. Do not
rename shared seed documents or leave uploaded bytes, profiles, contacts, or
appointments for later tests to encounter. A test should pass when repeated
against the same prepared database, including after a failed attempt. Keep
shared seed records for read-only scenarios and use the existing scenario
helpers when they already own their records.

The shared `family` fixture creates a private copy of the familiar Emma/Noah
family, including separate original-file blobs, and deletes that account and
user during teardown. Request it with `async ({ page, family })` and use
`family.openDependentWorkspace(page)` or `family.signIn(page)`. Backend helpers
should receive `family.accountName` instead of the shared fixture account name.
Before a test deletes documents in the browser, call `family.rememberBlobs()`
so teardown can also purge originals whose attachment rows were already removed.

To check repeatability through the harness:

```bash
ruby scripts/paper_bridge_qa_harness.rb bughunt repeatability tests/e2e/product/document_management.spec.js --repeat-each=2 --workers=1
```

When a QA server is already running, a single spec can be run directly:

```bash
QA_BASE_URL=http://127.0.0.1:3100 npx playwright test tests/e2e/product/document_sharing.spec.js --project=chromium
```

For bug recording:

```bash
QA_ARTIFACT_MODE=always QA_ARTIFACT_DIR=tmp/qa-artifacts/bugs/share-modal QA_BASE_URL=http://127.0.0.1:3100 npx playwright test --project=chromium
```

## Continuous Integration

The `system-test` job in `.github/workflows/ci.yml` runs the full Chromium suite
through the QA harness on pull requests and pushes to `main`, followed by the
Mailpit email checks.
It installs locked npm dependencies and Chromium using the
[Playwright CI setup](https://playwright.dev/docs/ci-intro), supplies PostgreSQL
with pgvector plus the native PDF/image tools, and captures email locally.
The workflow retains separate browser and email reports plus failure evidence
under the `browser-results` artifact. Firefox and WebKit remain separate local
checks; they are not part of this CI job.

`bin/ci` also runs the Chromium suite. Local Mailpit checks remain opt-in and
require a running inbox as described above.
