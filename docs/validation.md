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
ruby scripts/paper_bridge_qa_harness.rb bughunt
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

Use `smoke` for fast browser confidence. Use `bughunt BUG_ID` when reproducing
or verifying browser-visible defects; it records screenshots, traces, and videos
under `tmp/qa-artifacts/bugs/BUG_ID/`. Browser specs also surface console
errors, uncaught page errors, failed requests, server responses with status
`>= 500`, and axe accessibility violations.

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
