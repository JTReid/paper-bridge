# Architecture Map

PaperBridge is currently a Rails 8.1 greenfield application. The first
foundation includes Devise authentication, account memberships, dependent-owned
documents, PDF and image ingestion, and the shared agentic pipeline framework
ported from Scoutspace.

## Application Shape

- `User` is the Devise-backed login identity for account members.
- `Account` is the tenant boundary. Users join accounts through
  `AccountMembership` records with `admin` or `member` roles.
- `Dependent` is the person whose care records are being managed. Dependents
  belong to an account, own documents plus care team contacts, and may have one
  validated Active Storage avatar.
- `Appointment` belongs to one dependent and stores the scheduled time plus a
  family-facing description. Account calendar access is derived through the
  dependent so appointment queries stay inside the account tenant boundary.
- `CalendarWorkspace` loads the account-scoped month, appointments, profiles,
  and optional current-profile context used by both calendar entry points. The
  account entry renders a normal page; profile navigation targets a lazy Turbo
  Frame inside a native dialog so the profile page, scroll position, and
  unfinished form values remain in place underneath it.
- `AppointmentEmailsController` account-scopes the selected appointment,
  validates the recipient address, and sends its profile, Central Time, and
  description details through `AppointmentMailer` without creating sharing
  history or changing the appointment.
- `CareTeamMembership` stores one dependent's care team contact with a name,
  role, email, and optional phone number. It records the creating user through
  `invited_by` for provenance. Contacts do not create logins or grant access.
  Legacy login links, status, and permissions remain stored but unused.
- `Document` is the first-class upload record. It owns processing state,
  category, dependent ownership, preparation state, prepared payload JSON, and
  one Active Storage file attachment.
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
- `Documents::SearchAccessProfile` derives search access from membership in the
  requested account. Care team contacts and their roles grant no search access.
- `Documents::VectorSearch` performs account-scoped, label-scoped pgvector
  retrieval with an optional dependent scope and returns chunks with document,
  page, distance, and similarity metadata.
- `Documents::Prepare` is the single entry point for deterministic document
  preparation of text and PDF documents. It routes text uploads to
  `Documents::PrepareText` and PDFs to `Documents::PreparePdf`.
- `Documents::UploadNormalizer` validates image uploads and converts HEIC,
  HEIF, and TIFF sources to JPEG before they are attached to Active Storage.
  JPEG, PNG, and WebP uploads retain their browser-safe source formats.
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
  account memberships, appointment creation, full-page and in-profile family
  calendar display, on-demand detail emails, document uploads, document
  categories, care team memberships, current email-attachment document sharing,
  and document pages are real.
- Admin/member authorization lives on `AccountMembership`. Care team contacts
  supply contact details and suggested document-sharing recipients only.
- Development and production Active Storage use S3. Tests use the local test
  disk service. Profile avatars use a named 256-pixel square variant and an
  authenticated, account-scoped endpoint that redirects to a five-minute
  service URL; profiles without an avatar render initials.
- PDF preparation currently uses Poppler and Tesseract locally: embedded text
  extraction, 300 DPI page rendering, and OCR for every page.
- `ProcessDocumentJob` prepares uploads, creates a `PipelineRun`, runs
  `Agentic::DocumentIngestionPipeline`, creates page-aware labeled chunks,
  generates a source-grounded document summary, and persists OpenAI
  `text-embedding-3-large` embeddings in Postgres through pgvector. The same
  ingestion pipeline extracts chunk-sourced timeline events with
  `gpt-5.4-mini`.
- `ProcessImageDocumentJob` handles one JPEG, PNG, WebP, HEIC/HEIF, or TIFF
  upload as one document. It runs the separate
  `Agentic::ImageDocumentIngestionPipeline`: `Agents::ImageDocumentExtractor`
  makes one structured multimodal GPT request for extracted text, category,
  summary, key points, and search chunks, then `Agents::DocumentEmbedder`
  persists pgvector embeddings for those chunks. This first image path does not
  run the PDF preparation, document summarizer, or timeline-event extractor.
- `AiAssistantQuery` durably owns one account-, dependent-, and user-scoped
  question, its lifecycle state, and its final answer.
- `SavedAnswer` snapshots a completed query's question, answer, citations, and
  limitations, with separate generated and saved dates plus editable title and
  notes. It remains private to its user/account/profile and survives deletion
  of its originating query or source document.
- `MeetingPrep` names a private collection of saved answers.
  `MeetingPrepAnswer` gives each membership a position so one answer can be
  reused in multiple ordered meetings. Meeting deletion preserves saved answers.
  The meeting page preloads its answers and filters them locally. A searchable
  checklist supports batch addition; Turbo updates and Stimulus preserve browsing
  state when membership or order changes. The library performs literal text
  search over stored research. Neither path invokes AI.
- `GET /profiles/:dependent_id/ai-assistant` is read-only. `POST` saves a
  queued query. Turbo installs that result before an idempotent start request
  enqueues `AnswerAiAssistantQueryJob`, preventing fast worker broadcasts from
  racing ahead of the page. The job rechecks access, creates a `PipelineRun`
  with the query as its subject, runs
  `Agentic::DocumentSearchPipeline`, streams escaped answer drafts, and
  broadcasts state and the normalized final answer back to the dependent page
  through Turbo. An authenticated status endpoint reconciles active queries as
  a fallback when the browser misses a Cable replacement, and an ambiguous
  start response retries the same idempotent query instead of creating another
  run.
- The search pipeline embeds the user query with `text-embedding-3-large`,
  retrieves matching chunks through pgvector, and synthesizes a structured
  answer with citations using the configured search-answer LLM.
- Search retrieval is constrained to the current account, optional dependent,
  and labels allowed by `Documents::SearchAccessProfile`.
- Development and production Active Job processing uses Solid Queue. In
  development, queue tables live in `paper_bridge_development_queue`, and
  workers are started with `bin/jobs`. The dedicated `ai_assistant` queue is
  consumed by the current wildcard worker configuration.
- Billing uses Stripe-hosted Checkout and Customer Portal sessions. Webhook
  verification and dispatch are mounted through `stripe_event` at
  `/stripe/webhooks`, with subscription state synchronized by
  `Billing::StripeWebhookHandler`. Successful Checkout returns to a locked
  dashboard state; subscription-result webhooks clear its pending marker and
  broadcast an account-scoped Turbo refresh that re-runs the subscription gate.
- Live model checks are opt-in and should use fake or in-house test data for
  this spike.
