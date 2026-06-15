# Validation

Use the smallest check that gives meaningful confidence, then broaden based on
the risk of the change.

## Documentation And Harness Changes

```bash
ruby scripts/check_docs_index.rb
```

This verifies that required agent-facing docs exist and that Markdown files in
`docs/` are linked from `docs/README.md`.

## Agentic Pipeline Harness

```bash
ruby scripts/agentic_pipeline_harness.rb static
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
document upload-to-ingestion lifecycle and the vector search lifecycle,
including callback enqueueing, job execution, PDF preparation, page OCR/image
artifacts, page-aware chunk creation, pgvector embedding persistence,
account-scoped and label-scoped retrieval, pipeline records, and telemetry with
fake PDF tooling and fake LLM/embedding calls. The `pdf-tools` command checks
local Poppler/Tesseract availability for live PDF preparation; it is optional
and not part of default CI. The `queue` command checks the development Solid
Queue adapter, queue tables, and a throwaway enqueue path.

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
