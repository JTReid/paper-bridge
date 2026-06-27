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

Specs should use `data-testid` anchors for controls that are likely to be
reused in QA scenarios. Prefer accessible roles and labels for user-facing
assertions, and use test IDs for disambiguating repeated links, form fields, and
workflow buttons.

Shared browser diagnostics fail tests on uncaught page errors, console errors,
failed browser requests, and HTTP responses with status `>= 500`.

Shared accessibility checks use `@axe-core/playwright`.

Run Playwright through the QA harness unless you are iterating on a single spec.
The harness prepares the DB, loads fixtures, builds Tailwind, starts Rails, and
then runs Playwright.

## Direct Playwright Iteration

When a QA server is already running, a single spec can be run directly:

```bash
QA_BASE_URL=http://127.0.0.1:3100 npx playwright test tests/e2e/product/document_sharing.spec.js --project=chromium
```

For bug recording:

```bash
QA_ARTIFACT_MODE=always QA_ARTIFACT_DIR=tmp/qa-artifacts/bugs/share-modal QA_BASE_URL=http://127.0.0.1:3100 npx playwright test --project=chromium
```
