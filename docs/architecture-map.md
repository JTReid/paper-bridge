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
  preparation state, prepared payload JSON, and one Active
  Storage file attachment.
- `DocumentPage` is the first-class PDF page record. It stores embedded text,
  OCR text, preparation metadata, page status, and one rendered page image
  attachment.
- `DocumentChunk` is the first-class search unit. It stores chunk text, label,
  deterministic hash, document order, and the page where the chunk starts.
- `DocumentEmbedding` stores generated pgvector embeddings for chunks, including
  provider/model strings, dimensions, distance metric, and the vector value.
- `Documents::SearchAccessProfile` maps the current actor role to allowed
  chunk labels. This is the current authorization seam for search.
- `Documents::VectorSearch` performs account-scoped, label-scoped pgvector
  retrieval and returns chunks with document, page, distance, and similarity
  metadata.
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
  extraction, 300 DPI page rendering, and OCR for every page.
- `ProcessDocumentJob` prepares uploads, creates a `PipelineRun`, runs
  `Agentic::DocumentIngestionPipeline`, creates page-aware labeled chunks, and
  persists OpenAI `text-embedding-3-large` embeddings in Postgres through
  pgvector.
- `GET /search` creates a `PipelineRun` for nonblank queries, runs
  `Agentic::DocumentSearchPipeline`, embeds the user query with
  `text-embedding-3-large`, retrieves matching chunks through pgvector, and
  synthesizes a structured answer with citations using `gpt-5.4-mini`.
- Search retrieval is constrained to the current account and to labels allowed
  by `Documents::SearchAccessProfile`.
- Development and production Active Job processing uses Solid Queue. In
  development, queue tables live in `paper_bridge_development_queue`, and
  workers are started with `bin/jobs`.
- Live model checks are opt-in and should use fake or in-house test data for
  this spike.
