# Validation

Use the smallest check that gives meaningful confidence, then broaden based on
the risk of the change.

## Documentation And Harness Changes

```bash
ruby scripts/check_docs_index.rb
```

This verifies that required agent-facing docs exist and that Markdown files in
`docs/` are linked from `docs/README.md`.

## Current Product Shape Harness

```bash
ruby scripts/paper_bridge_harness.rb static
ruby scripts/paper_bridge_harness.rb assets
ruby scripts/paper_bridge_harness.rb foundation
ruby scripts/paper_bridge_harness.rb access
ruby scripts/paper_bridge_harness.rb sharing
ruby scripts/paper_bridge_harness.rb billing
ruby scripts/paper_bridge_harness.rb product
ruby scripts/paper_bridge_harness.rb review
```

This product-level harness covers behavior implemented in the Rails app today:
public/auth entry points, registration-created accounts, dashboard and
dependent workspace navigation, dependent profile access, care team invitations,
category permissions, search-access mapping, email-attachment document sharing,
and the Stripe billing foundation.

Future product requirements that are not implemented yet, such as calendar
persistence, in-app notifications, audit-log exports, tokenized sharing links,
document version history, multi-plan billing entitlements beyond
`stripe.standard_price`, invoice history screens, and mobile behavior, are
intentionally not product harness contracts yet.

## QA Troubleshooting Harness

```bash
ruby scripts/paper_bridge_qa_harness.rb doctor
ruby scripts/paper_bridge_qa_harness.rb static
ruby scripts/paper_bridge_qa_harness.rb seed
ruby scripts/paper_bridge_qa_harness.rb db
ruby scripts/paper_bridge_qa_harness.rb assets
ruby scripts/paper_bridge_qa_harness.rb smoke
ruby scripts/paper_bridge_qa_harness.rb browser
ruby scripts/paper_bridge_qa_harness.rb mailpit
ruby scripts/paper_bridge_qa_harness.rb bughunt BUG_ID [path...]
ruby scripts/paper_bridge_qa_harness.rb rubocop
ruby scripts/paper_bridge_qa_harness.rb review
```

This harness runs against `RAILS_ENV=test`, prepares the test DB, loads
fixtures and synthetic QA seed data, builds Tailwind, starts a local Rails test
server, and runs Playwright browser checks against `http://127.0.0.1:3100` by
default.

Use `seed` when development needs the synthetic processed-document and edge-case
corpus. This loads 11 documents, 25 pages, 71 chunks, 67 embeddings, 54 timeline
events, care-team recipients, share history, and representative pipeline records
under the `PaperBridge QA Harness` account.

Use `smoke` for Product Shape Smoke: a fast Chromium check that prepares the
test app, runs only `tests/e2e/smoke`, and verifies the public entry surface,
fixture-admin sign-in, dashboard, main signed-in product surface reachability,
invalid sign-in feedback, shared browser diagnostics, and targeted axe checks.
It is not proof of form side effects, document sharing delivery, persisted
care-team invitations, Stripe Checkout/webhooks, AI answer generation, email,
mobile, or broader negative workflows.

The intended Phase 3 workflow selector is
`ruby scripts/paper_bridge_qa_harness.rb workflow MODE`. Use it for named,
deterministic product scenarios such as `billing`, `sharing`, `documents`,
`care-team`, `ai`, or `all`. Workflow modes sit between `smoke` and `browser`:
they submit real browser workflows in `RAILS_ENV=test`, but they do not imply
the full Chromium suite, Mailpit SMTP capture, bughunt artifacts, live Stripe,
live AI, document ingestion, seeded edge-state scenarios, or the complete
negative/error-state matrix. The detailed contract is in
`docs/runbooks/qa-troubleshooting.md`.

The Phase 4 negative/error-state selector contract is
`ruby scripts/paper_bridge_qa_harness.rb negative MODE`. The deterministic
modes are `all`, `care-team`, `documents`, `mobile`, and `edge-states`. Use
these modes for invalid, empty, failed, seeded lifecycle, and mobile
error-state coverage; keep successful product workflows in `workflow`. Invalid
sign-in stays in `smoke` until the auth negative assertion is split into its own
spec.

Use `browser` when a change needs the full Chromium Playwright suite, including
smoke, product workflow, seeded edge-state, regression, and negative probes. Use
`mailpit` for SMTP capture and no-email assertions, because `negative` should
not require a local Mailpit process.

Use Bughunt Evidence Mode when reproducing or verifying one browser-visible
defect:

```bash
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal-repro tests/e2e/product/document_sharing.spec.js
ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal-verify tests/e2e/product/document_sharing.spec.js
```

Bughunt records screenshots, traces, videos, reports, command output, and a
manifest even when the selected tests pass. Named bug cases write to
`tmp/qa-artifacts/bugs/<bug-id>/`. The case is indexed by `index.html`, and
each execution writes a timestamped `runs/<run-id>/` directory containing
`manifest.json`, `summary.md`, `command.log`, `playwright-report/index.html`,
`test-results/`, and a copied Rails test-server log when available.

Recommended loop: reproduce with the narrowest useful Playwright path, inspect
the evidence index plus trace/video/screenshot/server log, fix the issue,
iterate with the smallest stable check that owns the behavior, then run a second
bughunt verification if before/after evidence needs to be kept. Move durable
assertions into `workflow`, `negative`, `mailpit`, or a regression spec after
the defect is understood. Bughunt does not start Mailpit and is not a
replacement for `browser` when full-suite coverage is needed. Browser specs also
surface console errors, uncaught page errors, failed requests, server responses
with status `>= 500`, and axe accessibility violations.

Use `mailpit` when an email workflow needs real SMTP capture. Start Mailpit
first:

```bash
mailpit --smtp 127.0.0.1:1025 --listen 127.0.0.1:8025
ruby scripts/paper_bridge_qa_harness.rb mailpit
```

## Agentic Pipeline Harness

```bash
ruby scripts/agentic_pipeline_harness.rb static
ruby scripts/agentic_pipeline_harness.rb assets
ruby scripts/agentic_pipeline_harness.rb doctor
ruby scripts/agentic_pipeline_harness.rb tests
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/agentic_pipeline_harness.rb pdf-tools
ruby scripts/agentic_pipeline_harness.rb queue
ruby scripts/agentic_pipeline_harness.rb rubocop
ruby scripts/agentic_pipeline_harness.rb review
```

This is a framework harness for agentic pipeline execution, provider wiring,
logging, telemetry, database-backed model/prompt/schema configuration, and
deterministic Minitest coverage. The `documents` command covers the current
document upload-to-ingestion lifecycle, timeline extraction, and the vector
search lifecycle, including callback enqueueing, job execution, PDF preparation,
page OCR/image artifacts, page-aware chunk creation, pgvector embedding
persistence, chunk-sourced timeline event persistence, account-scoped and
label-scoped retrieval, structured answer synthesis with citations, pipeline
records, and telemetry with fake PDF tooling and fake LLM/embedding calls. The
`pdf-tools` command checks local Poppler/Tesseract
availability for live PDF preparation; it is optional and not part of default
CI. The `queue` command checks the development Solid Queue adapter, queue
tables, and a throwaway enqueue path.

PDF ingestion coverage asserts the chunker sends extracted page text and
rendered page screenshots together in one multimodal OpenAI payload per page.

Live LLM checks are explicit opt-in checks:

```bash
AGENTIC_LIVE_PROVIDER=openai AGENTIC_LIVE_MODEL=gpt-5.4-nano ruby scripts/agentic_pipeline_harness.rb live
```

Do not add live checks to default CI without an explicit team decision.

## Rails Tests

```bash
bin/rails test
```

Prefer targeted tests while iterating:

```bash
bin/rails test test/services/agentic/pipeline_test.rb
```

## Ruby Style

```bash
bin/rubocop path/to/file.rb
```

Run full RuboCop when the change spans many Ruby files:

```bash
bin/rubocop
```

## Security

```bash
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
```

## Full Local CI

```bash
bin/ci
```

## Development Workers

Development document processing uses Solid Queue. Run workers in a second
terminal when testing uploads locally:

```bash
bin/jobs
```
