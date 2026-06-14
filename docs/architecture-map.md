# Architecture Map

PaperBridge is currently a Rails 8.1 greenfield application. The first
foundation includes Devise authentication, account-scoped users, document
uploads, PDF preparation, and the shared agentic pipeline framework ported from
Scoutspace.

## Application Shape

- `User` is Devise-backed and currently carries the first authorization seam:
  `family_admin`, `profile_user`, and `platform_admin`.
- `Account` is the current tenant boundary. Users and documents belong to an
  account.
- `Document` is the first-class upload record. It owns processing state,
  preparation state, summary JSON, prepared payload JSON, and one Active
  Storage file attachment.
- `DocumentPage` is the first-class PDF page record. It stores embedded text,
  OCR text, preparation metadata, page status, and one rendered page image
  attachment.
- `Documents::Prepare` is the single entry point for deterministic document
  preparation. It routes text uploads to `Documents::PrepareText` and PDFs to
  `Documents::PreparePdf`.
- `Agentic::Pipeline` orchestrates ordered agent execution, shared pipeline
  context, validator pass-through behavior, progress tracking, and durable
  `PipelineRun` instrumentation.
- `PipelineRun` is the durable workflow envelope for agentic work. It owns
  state, source context, activity entries, logs, and telemetry summaries.
- `Llm`, `AgentType`, `Prompt`, and `JsonSchema` store provider/model/prompt
  configuration in the database.
- Provider classes under `Agentic::Providers` expose the common provider
  interface used by agents: `call`, `parse_response`, and
  `.default_operation_type`.

## Current Boundaries

- Authentication, accounts, document uploads, and document pages are real.
- Authorization is role-only until Family Unit and Profile models exist.
- Development Active Storage uses S3. Tests use the local test disk service.
- PDF preparation currently uses Poppler and Tesseract locally: embedded text
  extraction, 225 DPI page rendering, and OCR for every page.
- `ProcessDocumentJob` prepares uploads, creates a `PipelineRun`, runs
  `Agentic::DocumentSummaryPipeline`, sends PDF page text and screenshots
  through the same document summarizer agent, and persists structured summary
  output on `Document`.
- Development and production Active Job processing uses Solid Queue. In
  development, queue tables live in `paper_bridge_development_queue`, and
  workers are started with `bin/jobs`.
- Live model checks are opt-in and should use fake or in-house test data for
  this spike.
