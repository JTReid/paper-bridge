# Current Product Shape Runbook

This runbook defines the PaperBridge behavior that exists in the Rails app
today and should be reflected by local harness commands.

Use this runbook to decide whether a harness change belongs to the current
product surface. Future requirements from the product PDFs should not become
operational harness checks until matching implementation exists.

## Implemented Product Surface

- Public home page with signed-out entry actions and signed-in dashboard access.
- Devise email/password registration and sign-in.
- Registration-created family accounts with an admin `AccountMembership`.
- Account-scoped dashboard and dependent profile workspace navigation.
- Family calendar with persisted, profile-owned appointment creation, a
  Sunday-start desktop month grid, a phone-friendly monthly agenda,
  previous/next/today navigation, read-only appointment details, on-demand
  appointment-detail email delivery, and an upcoming-appointments dashboard
  list. The account navigation opens the calendar as a full page. Inside a
  profile workspace, the same calendar opens in a large panel without replacing
  the page underneath. It shows the whole family's appointments and starts the
  add form with the current profile selected while still allowing another
  profile to be chosen.
- Dependent profile listing, display, create, edit, update, and destroy paths,
  including optional JPEG, PNG, or WebP avatar uploads up to 5 MB, initials
  fallbacks, and account-scoped display through temporary storage URLs.
- Document upload, listing, case-insensitive original-filename search, category
  filtering, filter-aware upload defaults, show, edit, update, and destroy
  paths. Intake supports text-like files, PDFs, and one JPEG, PNG, WebP, HEIC,
  HEIF, or TIFF image per document; HEIC/HEIF and TIFF uploads are converted to
  JPEG before Active Storage persistence.
- Document processing status, summary, readiness, file-detail rendering, and an
  original-file link that opens PDFs in a new tab and downloads other formats.
- Separate GPT-backed image ingestion that extracts text, classifies the
  document, creates search chunks, and stores pgvector embeddings.
- Care team invitations for a dependent, backed by `CareTeamMembership`.
- Care team category permissions for educational, medical, prescriptions,
  therapy, insurance, and general document categories.
- Dependent-scoped AI assistant with durable question submission,
  queued/processing/completed/failed states, background execution, final Turbo
  replacement, progressive plain-text answer drafts, immediate progress,
  honest wait-time guidance, duplicate-submit locking, and reload-safe answers.
- Account-scoped and category-scoped vector search authorization.
- Email-based document sharing through `ShareEvent`, `SharedDocument`, and
  `DocumentShareMailer`.
- Account-level Stripe billing foundation with `BillingSubscription`, hosted
  Stripe Checkout and Customer Portal session endpoints, StripeEvent webhook
  subscription sync, signed-in account subscription enforcement, a reusable
  `require_subscription!` controller gate, and a super-admin account billing
  overview.

## Family-Facing Language

Customer pages use language intended for a parent or caregiver rather than
describing the implementation:

- People whose records are managed are called **Profiles**.
- The question-and-answer feature is called **Ask PaperBridge**. The page still
  explains that answers are AI-generated and should be verified.
- Supporting records shown with an answer are called **Sources**.
- Numbered sources open the original PDF at the cited page after PaperBridge
  rechecks access to the document.
- Document states are **Uploaded**, **Getting ready**, **Preparing**, **Ready**,
  and **Needs attention**.
- Internal concepts such as chunks, embeddings, retrieval, run identifiers,
  MIME types, and raw service errors are not shown on family-facing pages.
- Extracted document text remains internal; families open the original file
  instead of reviewing processing fragments.
- Internal failures are logged for diagnosis while the interface gives a short,
  actionable message.

## Not Current Harness Scope

These areas are product requirements or future shape, but they are not current
operational harness contracts because the app does not implement them yet:

- Product/package pricing strategy, multi-plan entitlements, invoice history
  screens, taxes, coupons, and dunning workflows beyond Stripe's hosted pages.
- Appointment editing, deletion, reminders, recurring events, and external
  calendar integrations.
- In-app notification persistence and notification preferences.
- Audit-log persistence, querying, and exports.
- Tokenized external document links with expiration, password protection,
  revocation, and access tracking.
- Document version history, soft-delete retention, restore, and purge.
- Mobile app behavior.
- Native DOC/DOCX, RTF, and XLS/XLSX processing.
- Image OCR and verification passes, handwriting-specific model routing,
  region-level citations, prescription-specific structured fields, multi-image
  documents, and timeline events extracted from image documents.

## Validation

For current product shape checks:

```bash
ruby scripts/paper_bridge_harness.rb static
ruby scripts/paper_bridge_harness.rb calendar
ruby scripts/paper_bridge_harness.rb document-ui
ruby scripts/paper_bridge_harness.rb product
```

Before broader product-shape or runbook changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
