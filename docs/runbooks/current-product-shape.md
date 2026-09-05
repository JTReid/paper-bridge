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
- A six-step first-run setup tour for new account admins. It starts on the first
  empty Dashboard reached after subscription activation, then guides Profile
  creation, Documents, upload, and the first Ask PaperBridge question without
  changing or gating those workflows.
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
  with a required first name and optional last name, grade/school fields on edit
  only, and confirmed deletion from the edit page. Profiles with documents must
  have those documents removed first. Includes optional JPEG, PNG, or WebP
  avatar uploads up to 5 MB, initials fallbacks, and account-scoped display
  through temporary storage URLs. See [Profile Management](profile-management.md)
  for the separate legacy-name backfill and deletion behavior.
- Document upload, listing, case-insensitive original-filename search, category
  filtering, file-only upload, show, edit, update, and destroy
  paths. Processing supports text-like files, PDFs, and one JPEG, PNG, WebP, HEIC,
  HEIF, or TIFF image per document; HEIC/HEIF and TIFF uploads are converted to
  JPEG before Active Storage persistence.
- Upload selection supports individual removal, Clear selection, and a 50-file
  per-batch limit enforced in both browser and server. Duplicate contents in the
  same profile are rejected without overwrites; unique files still upload.
  Single and batch uploads return to the profile's Documents list. Category and
  description are generated once during initial processing and editable
  afterward; retries preserve them. Other file types, including Word, are saved
  as Stored—not processed, downloadable with immediately editable metadata,
  without entering the AI pipeline. See [Document Uploads](document-uploads.md).
- Document processing status, summary, readiness, file-detail rendering, and a
  prominent original-file action that opens PDFs in a new tab and downloads
  other formats.
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
  subscription sync, a locked post-Checkout dashboard state that refreshes from
  an account-scoped Turbo broadcast, signed-in account subscription enforcement,
  a reusable `require_subscription!` controller gate, and a super-admin account
  billing overview.
- Managed-profile subscription pricing: $25 USD/month includes five profiles,
  plus $5/month each beyond five, selected in hosted Checkout. Dedicated hosted
  Portal configuration handles prorated increases and renewal-time decreases.
  Webhook-synchronized allowances block only new profile creation at capacity;
  legacy subscriptions and existing over-limit data are preserved. See
  [Billing](billing.md) for test setup and the separate production rollout.

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

## First-Run Setup Tour

The setup tour is browser guidance, not a second onboarding workflow. Driver.js
highlights the existing Rails controls, and each link or form continues to use
its normal Turbo request. Link milestones advance when the user follows the
highlighted link. Profile creation, document upload, and question submission
advance only after the real form succeeds, so validation errors stay on the
same milestone.

The tour has six customer-facing milestones:

1. Create a Profile.
2. Open that Profile's Documents.
3. Open Add Documents.
4. Choose and upload one or more files.
5. Open Ask PaperBridge from Documents after either a single or batch upload.
6. Submit a suggested or custom question.

Only an active account admin with no Profiles is eligible for automatic start.
Progress is stored as a version, status, and phase in account-scoped browser
`localStorage`; it never stores Profile names, file names, or question text.
Closing or pressing Escape stores `dismissed` in that browser. Completion stores
`completed`. **Replay setup tour** in the account menu resets progress and starts
from Dashboard; when a Profile already exists, replay starts by opening it
instead of prompting for a duplicate.

The tour may tell customers to wait for a document to say **Ready** before
asking for the best answer, but it does not block early access to Ask
PaperBridge. Missing targets leave progress unchanged, unrelated pages stay
quiet, and Turbo page caching removes any active overlay before caching.

## Not Current Harness Scope

These areas are product requirements or future shape, but they are not current
operational harness contracts because the app does not implement them yet:

- Additional pricing plans, multi-plan entitlements, invoice history
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
ruby scripts/paper_bridge_qa_harness.rb workflow profiles
ruby scripts/paper_bridge_qa_harness.rb workflow onboarding
```

Before broader product-shape or runbook changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
