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
- Dependent profile listing, display, create, edit, update, and destroy paths.
- Document upload, listing, case-insensitive original-filename search, category
  filtering, filter-aware upload defaults, show, edit, update, and destroy
  paths.
- Document processing status, summary, readiness, file-detail rendering, and an
  original-file link that opens PDFs in a new tab and downloads other formats.
- Care team invitations for a dependent, backed by `CareTeamMembership`.
- Care team category permissions for education, medical, therapy, insurance,
  and general document categories.
- Dependent-scoped AI assistant entry point.
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
- Calendar event persistence and reminder workflows.
- In-app notification persistence and notification preferences.
- Audit-log persistence, querying, and exports.
- Tokenized external document links with expiration, password protection,
  revocation, and access tracking.
- Document version history, soft-delete retention, restore, and purge.
- Mobile app behavior.
- Native DOC/DOCX, RTF, image, HEIC/TIFF, and XLS/XLSX processing.

## Validation

For current product shape checks:

```bash
ruby scripts/paper_bridge_harness.rb static
ruby scripts/paper_bridge_harness.rb document-ui
ruby scripts/paper_bridge_harness.rb product
```

Before broader product-shape or runbook changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
