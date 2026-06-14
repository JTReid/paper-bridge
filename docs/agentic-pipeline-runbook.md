# Agentic Pipeline Runbook

This runbook protects the shared agentic pipeline machinery and the current
document-summary pipeline lifecycle.

Implementation-specific behavior belongs in targeted harness commands and
tests. The generic checks prove that the pipeline framework is healthy. The
document checks prove the upload-to-summary lifecycle that PaperBridge depends
on now.

## Critical Path Contract

The generic Agentic Pipeline harness protects these framework guarantees:

- Pipeline execution requires a resolvable `pipeline_run_gid`.
- Agents run in configured order.
- Current content and shared context move through the pipeline predictably.
- `after_execute` callbacks can add shared context for later steps.
- Validator agents can pass through current content and stop the pipeline when
  they return a non-approved status.
- Pipeline runs record started, completed, and failed states.
- Pipeline logs and activity entries are written through `PipelineRun`.
- `PipelineRun` is the durable workflow/job envelope.
- Sharing a `pipeline_run_gid` intentionally consolidates source context, logs,
  activity, and telemetry for the whole workflow.
- Configured `Llm` provider classes can be resolved and expose the expected
  provider interface.
- Structured model outputs are enforced through `JsonSchema` records.
- Live LLM checks are explicit opt-in checks, not default local or CI checks.

The generic harness does not protect:

- Prompt quality or exact model wording.
- Domain-specific extraction, mapping, validation, or persistence rules.
- Background job completion behavior.
- Every provider/model combination in production data.
- Cost ceilings beyond making provider/model drift visible.

## Document Summary Pipeline Contract

The document pipeline harness protects these product-level guarantees:

- `Document` is the first-class domain record for uploads and processing state.
- Each `Document` belongs to an `Account` and a `User`.
- Each `Document` has one Active Storage attachment named `file`.
- Active Storage upload completion is followed by `Document.after_create_commit`.
- The callback marks the document `queued` and enqueues `ProcessDocumentJob`.
- Development and production use Solid Queue for Active Job-backed document
  processing. Development stores queue records in `paper_bridge_development_queue`.
- `ProcessDocumentJob` prepares the document before running the summary
  pipeline.
- Text uploads are normalized into `documents.prepared_payload`.
- PDF uploads are prepared through `Documents::PreparePdf`.
- PDF preparation renders every page at 225 DPI, OCRs every page, extracts
  embedded text for every page, and stores page-level artifacts in
  `DocumentPage` records.
- `DocumentPage` stores page number, embedded text, OCR text, metadata, status,
  and a page image attachment.
- `ProcessDocumentJob` creates a `PipelineRun` for the document subject.
- `Agentic::DocumentSummaryPipeline` executes `Agents::DocumentSummarizer`.
- The summarizer consumes the prepared payload and, for PDFs, sends extracted
  page text plus rendered page screenshots to the configured LLM through the
  provider abstraction. It returns schema-enforced structured JSON.
- Pipeline logs, activity entries, and LLM telemetry are recorded on the
  `PipelineRun`.
- Deterministic preparation output is persisted to `documents.prepared_payload`.
- The structured model output is persisted to `documents.summary`.
- Successful processing marks the document `processed`; failures mark it
  `failed`.

The current document preparer supports:

- `text/plain`
- `text/markdown`
- `text/csv`
- `application/json`
- `application/pdf`

Live PDF preparation depends on Poppler and Tesseract binaries. Deterministic
tests use fake runners so CI does not depend on machine-level packages.

## Validation Loop

For a quick file-shape check:

```bash
ruby scripts/agentic_pipeline_harness.rb static
```

For local provider/configuration sanity:

```bash
ruby scripts/agentic_pipeline_harness.rb doctor
```

For deterministic framework tests:

```bash
ruby scripts/agentic_pipeline_harness.rb tests
```

For deterministic document lifecycle tests:

```bash
ruby scripts/agentic_pipeline_harness.rb documents
```

For local PDF preparation tool availability:

```bash
ruby scripts/agentic_pipeline_harness.rb pdf-tools
```

For development queue configuration and enqueue smoke:

```bash
ruby scripts/agentic_pipeline_harness.rb queue
```

Run development workers separately from the Rails server:

```bash
bin/jobs
```

Before committing broader agentic framework changes:

```bash
ruby scripts/agentic_pipeline_harness.rb review
```

## Live LLM Smoke

Live model checks are useful, but they should be controlled and explicit. They
should assert provider reachability and parseable structured output only, not
exact wording or broad product behavior.

Run a live provider smoke only when intentionally validating provider access:

```bash
AGENTIC_LIVE_PROVIDER=openai AGENTIC_LIVE_MODEL=gpt-5.4-nano ruby scripts/agentic_pipeline_harness.rb live
```

Supported values for `AGENTIC_LIVE_PROVIDER` are currently `openai` and
`anthropic`. OpenAI credentials are read from `ENV["OPENAI_API_KEY"]`,
`credentials.openai.api_key`, `credentials.open_ai.api_key`,
`credentials.app.api_key`, or `credentials.api_key`. Anthropic credentials are read from
`ENV["ANTHROPIC_API_KEY"]`, `credentials.anthropic.api_key`,
`credentials.app.anthropic_api_key`, or `credentials.anthropic_api_key`.

Do not add the live command to default CI without an explicit team decision.
