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
  upcoming-appointments calendar summary and an axe check.
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
  (`ruby scripts/paper_bridge_harness.rb foundation`, `calendar`, `access`,
  `sharing`, `billing`, or `product`) and to the richer Playwright product specs
  run by `browser`. Smoke should not prove dependent CRUD, appointment creation,
  document create/update/delete, document sharing delivery, care-team invitation
  persistence, billing status transitions, AI answer generation, or seeded
  edge-state workflows.
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

## Workflow Scenarios Contract

`workflow` is the intended Phase 3 command for named browser product scenarios.
It should prepare the same deterministic `RAILS_ENV=test` app as `browser`:
database prep, fixtures, QA seed data, fixture attachment setup, generated
Tailwind assets, a Rails test server at `QA_BASE_URL`, Chromium Playwright, the
shared browser diagnostics, and targeted axe checks where the scenario owns
them.

The command shape is:

```bash
ruby scripts/paper_bridge_qa_harness.rb workflow MODE
```

`MODE` is required. Unknown modes should fail before database or server prep and
print the supported mode names. `workflow` is not a free-form Playwright path
runner; use `bughunt BUG_ID [path...]` or direct Playwright iteration for
one-off paths.

Named workflow modes:

| Mode | Coverage |
| --- | --- |
| `all` | Runs every deterministic workflow mode in this table. It does not run `negative`, `mailpit`, seeded edge-state modes, or live-service probes. |
| `billing` | Verifies inactive-account billing gating, hidden product navigation, Checkout form full-page navigation, the locked post-Checkout dashboard state, Turbo-driven active and non-active outcomes, cancellation feedback, active-account product access, and Customer Portal form full-page navigation with synthetic Stripe records. |
| `sharing` | Opens the share modal, selects a care team recipient, submits a document share, and verifies the browser success path without SMTP capture. |
| `documents` | Exercises original-filename search, category-card and chip filtering, filter-aware upload defaults, successful multi-document upload, and document metadata editing. Required-file and blank-title validation live in `negative documents`. |
| `care-team` | Verifies the care-team list, active member permissions, invite form, and successful invite creation with category permissions. |
| `ai` | Opens the dependent-scoped AI assistant, submits a synthetic question, verifies immediate and queued states without leaving the profile, and runs an axe check. |
| `calendar` | Opens a profile edit page, leaves work unfinished, opens the family calendar panel without changing pages, creates and emails a profile-owned appointment, closes the panel, and verifies the unfinished edit remains. It also covers the full-page account calendar, Central Time rendering, read-only details, and previous/next month navigation. |

Boundaries:

- `smoke` remains the fast boot, auth, navigation, and surface-reachability
  sentinel. It should not submit product forms or prove side effects.
- `workflow` is narrower than `browser`: it runs named product scenarios but
  does not imply every smoke, product, regression, negative, or Mailpit spec.
- `browser` remains the full Chromium Playwright suite. Use it when a change
  needs broad browser-visible confidence across smoke, product workflows,
  negative probes, seeded states, and regression specs together.
- `negative` should own focused invalid, empty, failed, and mobile error-state
  probes. Workflow modes may include small validation checks that are part of a
  scenario, but they should not grow into the complete negative matrix.
- `mailpit` owns local SMTP capture and Mailpit API assertions, including email
  delivery and no-email checks. `workflow sharing` must not require Mailpit.
- `bughunt` owns named reproduction or verification runs with screenshots,
  traces, and videos always on. Use it for defect evidence, then use the
  relevant workflow mode when the fix should become a stable scenario.

Live-service caveats:

- Billing workflow coverage uses synthetic subscription records, form
  attributes, and a browser-delivered synthetic Turbo refresh. It does not call
  live Stripe Checkout, the Customer Portal, Stripe webhooks, the Stripe CLI, or
  prove live webhook-to-WebSocket delivery.
- AI assistant workflow coverage submits and persists a queued question through
  the test adapter. It does not run a worker, call a live LLM, generate
  embeddings, prove vector retrieval, or wait for a final answer.
- Seeded edge-state workflow coverage is not part of Phase 3 yet. When added,
  it should use synthetic records and avoid live document ingestion, background
  workers, OCR, PDF tooling, embeddings, or summary generation.
- Email workflow coverage outside `mailpit` must not require an SMTP process or
  assert captured email contents.
- Any future live-provider workflow must stay explicit opt-in and outside
  default `workflow all`, `browser`, and `review` unless the team intentionally
  changes the CI contract.

## Negative/Error-State Contract

`negative` is the intended Phase 4 command for deterministic browser probes
that intentionally exercise invalid, empty, failed, or mobile error states. It
uses the same deterministic `RAILS_ENV=test` browser harness as `workflow`, but
keeps failure-state coverage separate from successful product paths.

The command shape is:

```bash
ruby scripts/paper_bridge_qa_harness.rb negative MODE
```

`MODE` is required. Unknown modes should fail before database or server prep and
print the supported mode names. Like `workflow`, `negative` should prepare the
same deterministic `RAILS_ENV=test` app as `browser`: database prep, fixtures,
QA seed data, fixture attachment setup, generated Tailwind assets, a Rails test
server at `QA_BASE_URL`, Chromium Playwright, shared browser diagnostics, and
targeted axe checks where the mode owns them.

Named negative modes:

| Mode | Coverage |
| --- | --- |
| `all` | Runs every deterministic negative mode in this table. It does not run `workflow`, `mailpit`, `bughunt`, live-service probes, or full responsive sweeps. |
| `care-team` | Verifies blank email, malformed email, and duplicate invite behavior, including clear user-visible errors and no successful invalid invite. Successful invite creation remains `workflow care-team`. |
| `documents` | Verifies browser required-file upload validation and blank-title edit validation. Successful multi-document upload and metadata edits remain `workflow documents`; ingestion, OCR, embeddings, and processing states remain agentic or seeded-state coverage. |
| `mobile` | Runs a narrow viewport pass over deterministic negative probes, currently blank-recipient sharing and blank-email care-team invite behavior. It is not a full mobile product or responsive-layout suite. |
| `edge-states` | Verifies synthetic uploaded, failed, missing-embedding, partial-embedding, and no-summary document lifecycle states render safely. It does not run live ingestion, OCR, embeddings, or background workers. |

Boundaries:

- `negative` owns user-visible failure behavior: clear validation feedback,
  staying on the correct page or modal, no unexpected successful side effects,
  and no console errors, uncaught page errors, failed requests, or server
  responses with status `>= 500`.
- `workflow` owns primary successful browser workflows. A workflow mode may keep
  a small validation check that is intrinsic to the scenario, but it should not
  grow into the negative matrix.
- `browser` owns the full Chromium Playwright suite. Use it when a change needs
  confidence across smoke, workflows, negative probes, seeded edge states,
  regression specs, and skipped-when-unconfigured optional specs together.
- `mailpit` owns real SMTP capture and Mailpit API assertions. `negative` should
  not require a Mailpit process, and no-email assertions that inspect the inbox
  belong in `mailpit`.
- `bughunt` owns named defect reproduction and verification with screenshots,
  traces, and videos always on. Use it for targeted evidence, then move stable
  deterministic assertions into the relevant `negative` mode.
- Invalid sign-in remains in `smoke` for now because the existing auth spec also
  includes a successful sign-in sentinel. Add a dedicated `negative auth` mode
  later only if the invalid-auth browser assertion is split into its own spec.
- `negative all` should stay deterministic and local. Do not add live Stripe,
  live AI, background worker, OCR, external email, or cross-browser coverage
  without an explicit team decision.

## Bughunt Evidence Mode

`bughunt` is the evidence capture mode for one named browser-visible defect. It
uses the same deterministic `RAILS_ENV=test` browser harness as `browser`,
including database prep, fixtures, QA seed data, fixture attachment setup,
generated Tailwind assets, the Rails test server, Chromium Playwright, shared
browser diagnostics, and targeted axe checks already owned by the selected
specs. Its difference is artifact policy: screenshots, traces, videos, and the
HTML report are recorded even when the selected tests pass.

The command shape is:

```bash
ruby scripts/paper_bridge_qa_harness.rb bughunt BUG_ID [path...]
```

`BUG_ID` should be a stable slug for the defect, ticket, or investigation. The
harness normalizes it for the filesystem and writes Playwright evidence under:

```text
tmp/qa-artifacts/bugs/<bug-id>/runs/<run-id>/
```

If the first argument starts with `tests/`, the harness treats every argument as
a Playwright path and generates a timestamped bug id. Prefer an explicit
`BUG_ID` for work that may be handed to another person.

Examples:

```bash
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal tests/e2e/product/document_sharing.spec.js
ruby scripts/paper_bridge_qa_harness.rb bughunt mobile-negative tests/e2e/product/mobile_negative.spec.js
```

### Evidence Artifacts

For named bug hunts, the primary evidence directory is
`tmp/qa-artifacts/bugs/<bug-id>/`. The bug-level `index.html` lists every run
newest-first. Each execution writes a new timestamped run directory under
`tmp/qa-artifacts/bugs/<bug-id>/runs/<run-id>/`, so rerunning the same `BUG_ID`
does not overwrite previous evidence.

Important artifacts:

- `index.html` at the bug root is the local evidence landing page. Open this
  first when reviewing a bug case with multiple reproduce or verify runs.
- `runs/<run-id>/manifest.json` is the machine-readable evidence manifest. It identifies
  the schema, bug id, command, selected paths, base URL, artifact mode,
  timestamps, exit status, and the relative paths for the rest of the evidence
  bundle.
- `runs/<run-id>/summary.md` is the human handoff note. It captures the bug id,
  exact command, branch or commit under test, observed result, selected paths,
  and the key artifact links.
- `runs/<run-id>/command.log` captures the Playwright command output for that
  evidence run.
- `runs/<run-id>/playwright-report/index.html` is the Playwright report. It lists the
  selected specs, status, retry state when relevant, and links to per-test
  attachments.
- `runs/<run-id>/test-results/` contains Playwright's per-test evidence, including
  screenshots, videos, and `trace.zip` files when the run reaches the browser
  stage.
- `runs/<run-id>/rails-test-server.log` is a copy of the Rails test-server log
  at the end of the run, when available. The canonical rolling log remains
  `tmp/qa-artifacts/logs/rails-test-server.log`.

Artifacts under `tmp/qa-artifacts/` are generated diagnostics and should remain
local unless they are intentionally attached to a bug tracker or PR discussion.

### Reproduce-Fix-Verify Loop

Use this loop for browser-visible defects:

1. Choose a bug id that can survive handoff, such as `share-modal-recipient`.
2. Reproduce with the narrowest useful path:

   ```bash
   ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal-recipient-repro tests/e2e/product/document_sharing.spec.js
   ```

3. Open `tmp/qa-artifacts/bugs/<bug-id>/index.html`, then read the run summary,
   Playwright report, trace, video, screenshot, command log, and Rails
   test-server log before editing code.
4. Fix the defect and run the smallest meaningful non-bughunt check while
   iterating, usually the relevant `workflow MODE`, `negative MODE`, targeted
   Rails test, or direct Playwright spec.
5. Verify with a second named evidence run:

   ```bash
   ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal-recipient-verify tests/e2e/product/document_sharing.spec.js
   ```

6. Move durable assertions into the stable suite that owns the behavior:
   `workflow` for successful product paths, `negative` for invalid or failed
   states, `mailpit` for SMTP and inbox assertions, or a focused regression spec
   when the defect does not fit an existing mode.

Use distinct `-repro` and `-verify` bug ids when they are separate bug-tracker
artifacts. Reusing the same `BUG_ID` is also safe because each execution writes
to a new `runs/<run-id>/` directory under the same case index.

### Boundaries

- `bughunt` is for evidence, not coverage design. It records richer artifacts
  for the selected Chromium specs, but it does not decide where a stable
  assertion belongs after the fix.
- `workflow` owns named successful product scenarios. After a bug fix, prefer a
  workflow mode when the durable assertion is a successful user path.
- `negative` owns deterministic invalid, empty, failed, seeded lifecycle, and
  mobile error-state probes. Use it for durable error-state coverage after a
  bughunt proves the failure and fix.
- `browser` owns the full Chromium Playwright suite. Running `bughunt` without
  a path is useful only when the investigation needs full-suite evidence with
  artifacts always on.
- `mailpit` owns real SMTP capture and Mailpit API assertions. `bughunt` does
  not start Mailpit or set the Mailpit-specific Rails and Playwright
  environment, so email delivery and no-email inbox assertions belong in
  `mailpit`.
- Browser, workflow, negative, Mailpit, and bughunt modes all remain local,
  deterministic test-environment checks unless a future live-provider mode is
  added explicitly.

## Accessibility And Mobile Suite Contract

Phase 6 groups automated accessibility checks and narrow mobile viewport
coverage. These suites use the same deterministic `RAILS_ENV=test` browser
harness as `browser`: database prep, fixtures, QA seed data, fixture attachment
setup, generated Tailwind assets, a Rails test server at `QA_BASE_URL`,
Chromium Playwright, and shared browser diagnostics.

Accessibility commands:

```bash
ruby scripts/paper_bridge_qa_harness.rb accessibility MODE
```

Accessibility modes:

| Mode | Coverage |
| --- | --- |
| `surfaces` | Runs axe checks over public home, sign-in, dashboard, billing gate, workspace, documents, share modal, upload, care team, invite, AI assistant, and seeded document edge states. |
| `all` | Runs every accessibility mode above. Today this is the same path as `accessibility surfaces`. It does not run mobile viewport checks, Mailpit, or live-service probes. |

Mobile commands:

```bash
ruby scripts/paper_bridge_qa_harness.rb mobile MODE
```

Mobile modes:

| Mode | Coverage |
| --- | --- |
| `surfaces` | Runs successful `390x844` viewport navigation through public home, dashboard, billing, workspace, documents, share modal, care team, invite, and AI assistant surfaces. |
| `negative` | Runs narrow viewport negative workflow probes. |
| `all` | Runs every mobile mode above. |

Accessibility coverage uses `@axe-core/playwright` through the shared
`expectAccessible` helper. The helper runs axe against the current Chromium page
or modal at the point where the selected spec calls it, and any violation fails
the Playwright run with the affected selectors and axe help URL.

Mobile coverage currently has two specs at a `390x844` viewport.
`mobile surfaces` runs `tests/e2e/product/mobile_suite.spec.js` and verifies
successful narrow navigation through the public entry points, app shell,
billing page, workspace, documents, share modal, care-team invite, and AI
assistant. `mobile negative` runs `tests/e2e/product/mobile_negative.spec.js`
and verifies two user-visible failure states: blank-recipient document sharing
stays in the share modal with browser-native required-field validation, and a
blank-email care-team invite returns to the invite form with visible validation
errors.

What Phase 6 proves:

- `accessibility all` has zero automated axe violations on the accessibility
  suite's instrumented pages and modals at the exact tested states in Chromium.
- The same shared browser diagnostics still apply: uncaught page errors,
  console errors, failed requests, and server responses with status `>= 500`
  fail the run.
- `mobile surfaces` keeps successful mobile app-shell navigation reachable and
  user-visible at the `390x844` viewport.
- `mobile negative` keeps the current critical mobile validation states
  reachable and user-visible at the `390x844` viewport.
- `browser` proves the accessibility and mobile specs run together with the
  rest of the Chromium QA suite.

What Phase 6 does not prove:

- It is not a full WCAG audit, manual keyboard audit, screen-reader audit,
  usability review, or guarantee that every page has an accessible name, focus
  order, announcement, or contrast state beyond the automated axe rules that run
  on instrumented surfaces.
- It does not cover pages or interaction states that do not call
  `expectAccessible`, including every modal state, error variant, loading state,
  or submitted workflow result.
- It is not a full mobile product suite, responsive-layout matrix, touch-device
  certification, or cross-browser mobile pass. Current mobile coverage is one
  Chromium viewport tied to selected successful navigation and negative
  validation probes.
- It does not prove successful mobile document sharing submission, care-team
  invite submission, file upload, AI answer generation, or document processing.
- It does not call live Stripe, live AI providers, external SMTP, background
  workers, OCR, embeddings, or native device services.

Boundaries:

- `smoke` remains the fast boot, auth, navigation, surface-reachability, and
  selected smoke-owned axe sentinel. Use `accessibility` when the intent is the
  named accessibility suite; use `smoke` when the intent is fast product-shape
  reachability.
- `workflow` owns successful product paths. Accessibility assertions inside a
  workflow mode check the page state used by that scenario, but `accessibility`
  is the selector that groups axe-bearing product surfaces by quality concern.
- `negative` owns deterministic invalid, empty, failed, seeded lifecycle, and
  error-state probes. `negative mobile` and `mobile negative` currently run the
  same narrow validation spec; prefer `mobile negative` when the intent is
  Phase 6 mobile suite coverage.
- `bughunt` owns named defect evidence. Use it for mobile or accessibility
  reproduce/verify artifacts, then move durable assertions into the stable mode
  that owns the behavior.
- `mailpit` owns SMTP capture and inbox assertions. Phase 6 mobile and
  accessibility checks must not require a Mailpit process.

## Commands

```bash
ruby scripts/paper_bridge_qa_harness.rb doctor
ruby scripts/paper_bridge_qa_harness.rb db
ruby scripts/paper_bridge_qa_harness.rb assets
ruby scripts/paper_bridge_qa_harness.rb smoke
ruby scripts/paper_bridge_qa_harness.rb browser
ruby scripts/paper_bridge_qa_harness.rb workflow billing
ruby scripts/paper_bridge_qa_harness.rb workflow all
ruby scripts/paper_bridge_qa_harness.rb negative documents
ruby scripts/paper_bridge_qa_harness.rb negative all
ruby scripts/paper_bridge_qa_harness.rb mailpit
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal
ruby scripts/paper_bridge_qa_harness.rb review
```

Phase 4 negative selector examples:

```bash
ruby scripts/paper_bridge_qa_harness.rb negative all
ruby scripts/paper_bridge_qa_harness.rb negative care-team
ruby scripts/paper_bridge_qa_harness.rb negative documents
ruby scripts/paper_bridge_qa_harness.rb negative edge-states
ruby scripts/paper_bridge_qa_harness.rb negative mobile
```

Phase 6 accessibility and mobile examples:

```bash
ruby scripts/paper_bridge_qa_harness.rb accessibility surfaces
ruby scripts/paper_bridge_qa_harness.rb accessibility all
ruby scripts/paper_bridge_qa_harness.rb mobile surfaces
ruby scripts/paper_bridge_qa_harness.rb mobile negative
ruby scripts/paper_bridge_qa_harness.rb mobile all
ruby scripts/paper_bridge_qa_harness.rb browser
ruby scripts/paper_bridge_qa_harness.rb bughunt mobile-negative tests/e2e/product/mobile_negative.spec.js
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

Use Bughunt Evidence Mode when reproducing or verifying a specific defect. It
records screenshots, traces, videos, a command log, a manifest, a summary, and
an HTML report even when the selected tests pass. Named bug hunts write to
`tmp/qa-artifacts/bugs/<bug-id>/`, with `index.html` as the bug-level evidence
index and each execution under `runs/<run-id>/`.

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
- Document negative coverage verifies blank-title validation.
- A care team member can be invited with category permissions.
- Care-team negative coverage verifies blank, malformed, and duplicate invite
  errors.
- Mobile negative coverage verifies blank-recipient sharing and blank-email care
  team invite behavior on a narrow viewport.
- Billing gates inactive accounts to `/billing`, hides product navigation,
  verifies active accounts keep product access, and checks Stripe Checkout and
  Customer Portal forms use full-page navigation instead of Turbo fetches.
