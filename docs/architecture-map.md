# Architecture Map

PaperBridge is currently a Rails 8.1 greenfield application. The first
foundation includes Devise authentication, account memberships, dependent-owned
documents, PDF preparation, and the shared agentic pipeline framework ported
from Scoutspace.

## Application Shape

- `User` is Devise-backed and is the single login identity for account members
  and care team members.
- `Account` is the tenant boundary. Users join accounts through
  `AccountMembership` records with `admin` or `member` roles.
- `Dependent` is the person whose care records are being managed. Dependents
  belong to an account and own documents plus care team access.
- `CareTeamMembership` links a login user to one dependent, records the care
  team role, tracks invite status, and stores document category permissions.
- `Document` is the first-class upload record. It owns processing state,
  category, dependent ownership, preparation state, prepared payload JSON, and one Active
  Storage file attachment.
- `ShareEvent` records current email-based document sharing attempts, including
  sender, recipient email, message metadata, status, sent timestamp, and errors.
- `SharedDocument` joins shared documents to a share event and enforces account
  ownership consistency.
- `DocumentShareMailer` sends the currently selected documents as email
  attachments. Tokenized external sharing links are not implemented yet.
- `BillingSubscription` stores account-level Stripe customer, subscription,
  price, status, period, cancellation, and latest webhook event state. Account
  access checks flow through `Account#subscription_active?`.
- `SubscriptionGate` exposes `require_subscription!` for controller-level paid
  access gates. It bypasses users with the platform-level `super_admin`
  `site_role`.
- `DocumentPage` is the first-class PDF page record. It stores embedded text,
  OCR text, preparation metadata, page status, and one rendered page image
  attachment.
- `DocumentChunk` is the first-class search unit. It stores chunk text, label,
  deterministic hash, document order, and the page where the chunk starts.
- `DocumentEmbedding` stores generated pgvector embeddings for chunks, including
  provider/model strings, dimensions, distance metric, and the vector value.
- `TimelineEvent` stores source-grounded care timeline events extracted from
  chunks. Each event belongs to one `DocumentChunk`, so attribution flows back
  through the chunk, document page, document, and account.
- `Documents::SearchAccessProfile` maps account membership roles or care team
  category permissions to allowed chunk labels. This is the current
  authorization seam for search.
- `Documents::VectorSearch` performs account-scoped, label-scoped pgvector
  retrieval with an optional dependent scope and returns chunks with document,
  page, distance, and similarity metadata.
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

- Public entry, authentication, account registration, accounts, dependents,
  account memberships, document uploads, document categories, care team
  memberships, current email-attachment document sharing, and document pages are
  real.
- Admin/member authorization lives on `AccountMembership`. Care team document
  search authorization is derived from dependent-scoped `CareTeamMembership`
  category permissions.
- Development Active Storage uses S3. Tests use the local test disk service.
- PDF preparation currently uses Poppler and Tesseract locally: embedded text
  extraction, 300 DPI page rendering, and OCR for every page.
- `ProcessDocumentJob` prepares uploads, creates a `PipelineRun`, runs
  `Agentic::DocumentIngestionPipeline`, creates page-aware labeled chunks,
  generates a source-grounded document summary, and persists OpenAI
  `text-embedding-3-large` embeddings in Postgres through pgvector. The same
  ingestion pipeline extracts chunk-sourced timeline events with
  `gpt-5.4-mini`.
- `GET /dependents/:dependent_id/ai-assistant` creates a `PipelineRun` for
  nonblank queries, runs `Agentic::DocumentSearchPipeline`, embeds the user
  query with `text-embedding-3-large`, retrieves matching chunks through
  pgvector, and synthesizes a structured answer with citations using
  `gpt-5.4-mini`.
- Search retrieval is constrained to the current account, optional dependent,
  and labels allowed by `Documents::SearchAccessProfile`.
- Development and production Active Job processing uses Solid Queue. In
  development, queue tables live in `paper_bridge_development_queue`, and
  workers are started with `bin/jobs`.
- Billing uses Stripe-hosted Checkout and Customer Portal sessions. Webhook
  verification and dispatch are mounted through `stripe_event` at
  `/stripe/webhooks`, with subscription state synchronized by
  `Billing::StripeWebhookHandler`.
- Live model checks are opt-in and should use fake or in-house test data for
  this spike.
