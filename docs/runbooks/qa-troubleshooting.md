# QA Troubleshooting Runbook

This runbook defines the local QA harness used to reproduce, diagnose, and
verify browser-facing bugs in PaperBridge.

The QA harness is separate from the development/product-shape harness. The
development harness answers "did this change preserve the current product
contract?" The QA harness answers "can we reproduce the bug, collect useful
artifacts, and prove the fix?"

## Scope

- The QA harness runs against `RAILS_ENV=test`.
- The harness can prepare the test database and load deterministic fixtures.
- The harness applies a small QA data setup after fixtures, including attaching
  a sample file to the fixture document used by browser workflows.
- The harness can start and stop a local Rails test server.
- Browser tests use Playwright and target Chromium by default for fast local
  troubleshooting.
- Browser tests surface console errors, uncaught page errors, failed requests,
  and server responses with status `>= 500`.
- Browser tests run automated axe accessibility checks on key pages and modals.
- The `mailpit` command is an opt-in mode that routes the Rails test server's
  Action Mailer delivery through local Mailpit SMTP and verifies captured email
  through the Mailpit API.
- QA artifacts are local-only and are not committed.

## Environment Doctor Contract

`doctor` is the Environment Doctor phase. It is a local preflight for tools and
state that the QA harness needs before browser troubleshooting starts. It can
boot Rails in `RAILS_ENV=test`, query the test database, and launch a Chromium
browser, but it does not mutate the database or run product workflows.

Required checks:

- Ruby and Bundler are available.
- Rails boots under `RAILS_ENV=test`.
- The test database accepts a simple connection query.
- The pgvector extension is enabled in the test database.
- Node and npm are available.
- The Playwright CLI can be resolved from project dependencies.
- `@axe-core/playwright` is installed at the project root.
- Chromium can launch through Playwright.
- The QA harness static file inventory passes.

Warning-only checks:

- Mailpit API reachability at `QA_MAILPIT_API_URL`, because SMTP capture is only
  required for `mailpit` mode.
- Stripe CLI availability, because it is only required for future live Stripe
  webhook or Checkout QA.
- Stripe Checkout configuration in the test environment, because it is only
  required for live Stripe Checkout QA.
- An existing Rails QA server responding at `QA_BASE_URL`, because browser modes
  will reuse it and the operator may need to stop it if that is not intentional.

`doctor` reports each check as `PASS`, `WARN`, or `FAIL`, then prints a summary.
Any failed required check is a hard failure and makes `doctor` exit non-zero.
Warnings do not change the exit status; they are for optional, mode-specific
capabilities or local state worth noticing. If a warning-only prerequisite is
actually needed, that mode owns the hard failure. For example, `mailpit` mode
fails if Mailpit is unavailable and prints the startup command.

`doctor` does not prepare Rails, modify the database, load fixtures, seed QA
data, build assets, start a server, run Playwright specs, or write artifacts.
Those actions belong to the browser execution modes:

- `smoke` prepares the test app and runs only `tests/e2e/smoke` for fast
  boot/navigation confidence.
- `browser` prepares the test app and runs the full Chromium Playwright suite.
- `mailpit` and `bughunt` extend browser execution with email capture or
  always-on diagnostic artifacts.

## Commands

```bash
ruby scripts/paper_bridge_qa_harness.rb doctor
ruby scripts/paper_bridge_qa_harness.rb db
ruby scripts/paper_bridge_qa_harness.rb assets
ruby scripts/paper_bridge_qa_harness.rb smoke
ruby scripts/paper_bridge_qa_harness.rb browser
ruby scripts/paper_bridge_qa_harness.rb mailpit
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal
ruby scripts/paper_bridge_qa_harness.rb review
```

The Mailpit command requires a local Mailpit process:

```bash
mailpit --smtp 127.0.0.1:1025 --listen 127.0.0.1:8025
ruby scripts/paper_bridge_qa_harness.rb mailpit
```

## Artifact Policy

Playwright writes screenshots, videos, traces, reports, and logs under
`tmp/qa-artifacts/`. These files are generated diagnostics and should remain
local.

Use `bughunt` when reproducing or verifying a specific defect. It records
screenshots, traces, and videos even when the test passes. Named bug hunts write
to `tmp/qa-artifacts/bugs/<bug-id>/`.

Examples:

```bash
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal tests/e2e/product/document_sharing.spec.js
```

Use `smoke` for fast confidence that the browser harness can boot the app and
exercise the core workflow.

## Initial Browser Surface

- Public home page loads with entry actions.
- Sign-in page loads.
- A fixture admin can sign in and reach the dashboard.
- A dependent workspace opens.
- The documents page opens and the share modal can be opened.
- Document sharing can submit to a care team recipient.
- Mailpit mode verifies document sharing sends an email with the expected
  recipient, subject, body, and attachment count.
- Browser-native upload form validation guards missing files.
- Document metadata can be edited.
- The care team page opens.
- A care team member can be invited with category permissions.
- The AI assistant page opens without submitting a query.
- Billing gates inactive accounts to `/billing`, hides product navigation,
  verifies active accounts keep product access, and checks Stripe Checkout and
  Customer Portal forms use full-page navigation instead of Turbo fetches.
