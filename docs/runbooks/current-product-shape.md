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
- Document upload, listing, show, edit, update, and destroy paths.
- Document processing status, summary, page, chunk, and file-detail rendering.
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
ruby scripts/paper_bridge_harness.rb product
```

Before broader product-shape or runbook changes:

```bash
ruby scripts/paper_bridge_harness.rb review
```
