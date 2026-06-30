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
  product-shape boot, auth, navigation, and surface-reachability confidence.
- `browser` prepares the test app and runs the full Chromium Playwright suite.
- `mailpit` and `bughunt` extend browser execution with email capture or
  always-on diagnostic artifacts.

## Product Shape Smoke Contract

`smoke` is Phase 2 of the QA harness, after `doctor`. It prepares the same
test app used by browser QA: database prep, fixtures, synthetic QA seed data,
the small QA fixture attachment setup, generated Tailwind assets, and a Rails
test server at `QA_BASE_URL`. It then runs only the Chromium specs under
`tests/e2e/smoke`.

Smoke is a fast product-shape sentinel, not a workflow suite. It covers the
minimum browser-visible surface that should fail quickly if the app cannot boot,
route, authenticate, or render the implemented signed-in workspace:

- The public home page renders the PaperBridge entry surface, including primary
  and secondary entry actions, the hero action, key copy, and an axe check.
- A fixture admin can sign in and reach the dashboard, including the current
  calendar empty state and an axe check.
- An invalid sign-in stays on the sign-in page and shows the Devise alert.
- An active account can reach the dashboard, dependent workspace, documents
  index, document detail, document upload form, document share modal, care-team
  index, care-team invite form, AI assistant page, and billing page.
- Smoke only checks that these surfaces render and expose their primary
  affordances; it does not submit product forms or verify side effects.
- Shared browser diagnostics still apply: uncaught page errors, console errors,
  failed requests, and HTTP responses with status `>= 500` fail the run.

Hard boundaries:

- Deeper workflow coverage belongs to the product-shape harness
  (`ruby scripts/paper_bridge_harness.rb foundation`, `access`, `sharing`,
  `billing`, or `product`) and to the richer Playwright product specs run by
  `browser`. Smoke should not prove dependent CRUD, document create/update/delete,
  document sharing delivery, care-team invitation persistence, billing status
  transitions, AI answer generation, or seeded edge-state workflows.
- Negative and error-state probes belong in focused product, Mailpit, or
  regression specs. Smoke may keep the shallow invalid sign-in sentinel, but it
  should not become the matrix for blank forms, malformed recipients, duplicate
  invites, mobile validation, failed processing states, or no-email assertions.
- `browser` is the full Chromium Playwright suite. Use it when a change needs
  confidence across browser-visible product workflows, negative probes, billing
  forms, seeded QA states, and smoke together.
- `bughunt BUG_ID [path...]` is for reproducing or verifying a named
  browser-visible defect with screenshots, traces, and videos always on. Use it
  for targeted debugging or regression evidence, not as the default fast smoke
  gate.
- `mailpit` owns real SMTP capture and Mailpit API assertions. Smoke must not
  require a Mailpit process.

Use `smoke` after `doctor` passes when the browser harness, app boot path,
authentication surface, home page, app shell, current signed-in navigation, or
asset pipeline changes. It is also a quick gate before `browser`, `bughunt`, or
`review`. Passing smoke does not prove broader product workflows, negative
states, email delivery, Stripe Checkout/webhooks, AI answer generation, mobile,
or live-provider behavior.

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

Use `smoke` for fast confidence that the browser harness can boot the app,
render the public entry surface, authenticate into the dashboard, and reach the
main signed-in product surfaces.

## Initial Browser Surface

- Smoke verifies the public home page entry actions.
- Smoke verifies a fixture admin can sign in and reach the dashboard.
- Smoke verifies invalid sign-in feedback.
- Smoke verifies a dependent workspace opens.
- Smoke verifies the documents page, document detail, upload form, and share
  modal can be opened without submitting document workflows.
- Smoke verifies the care-team index and invite form can be opened without
  submitting an invitation.
- Smoke verifies the AI assistant page opens without submitting a query.
- Smoke verifies the billing page renders the active subscription state.
- Document sharing can submit to a care team recipient.
- Mailpit mode verifies document sharing sends an email with the expected
  recipient, subject, body, and attachment count.
- Browser-native upload form validation guards missing files.
- Document metadata can be edited.
- A care team member can be invited with category permissions.
- Billing gates inactive accounts to `/billing`, hides product navigation,
  verifies active accounts keep product access, and checks Stripe Checkout and
  Customer Portal forms use full-page navigation instead of Turbo fetches.
