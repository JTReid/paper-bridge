# Negative Error-State Probes

This note captures recommended QA harness probes for intentionally exercising
invalid, empty, failed, or edge-case product states. These are candidates for a
future Playwright/QA pass, not current product commitments.

## TODO

- Decide whether zero-permission care team invites should be valid.
- Decide whether unsupported document upload file types should be restricted.
- Add deeper AI no-evidence browser coverage once the QA harness has a
  deterministic fake LLM/vector-search path.

## Implemented First Pass

- Sharing Mailpit QA verifies successful document sharing sends an email with
  expected recipient, subject, body text, and attachment count.
- Sharing Mailpit QA verifies no email is sent when no documents are selected.
- Sharing Mailpit QA verifies blank recipient submission stays in browser-native
  validation and sends no email.
- Sharing Mailpit QA verifies malformed recipient is rejected server-side and
  sends no email.
- Care team QA verifies blank email, malformed email, and duplicate invite
  behavior.
- Document QA verifies blank title edits show a validation error instead of
  silently restoring the filename.
- Mobile QA verifies blank recipient sharing and blank-email care team invites
  on a narrow viewport.
- Controller coverage verifies AI assistant pipeline failures render the
  intended fallback UI.

## Recommendation

Start with targeted negative probes where browser-level behavior adds value
beyond existing model and controller tests:

1. Sharing validation and failure states.
2. Care team invitation validation.
3. AI assistant failure and no-evidence states.
4. Mobile viewport sweeps around the same workflows.

Do not build a broad negative suite until these prove useful. The current app
already has Rails-level guardrails for several cases, so the QA harness should
focus on user-visible behavior: clear errors, no crashes, no unwanted records,
no emails sent on failed submissions, and no console/network surprises.

## High-Value Probes

### Sharing

Current surface:

- `ShareEventsController#create` handles no selected documents, oversized
  attachments, invalid records, and delivery failures.
- `ShareEvent` currently validates recipient presence but not recipient email
  format at the model level.
- The browser form uses an email input, which helps but should not be the only
  validation boundary.

Recommended probes:

- Submit share modal with no selected document.
- Submit with a blank recipient.
- Submit with malformed recipient email.
- Submit after choosing no care team recipient.
- Confirm no `ShareEvent`, `SharedDocument`, or email is created when validation
  fails.
- Confirm the user sees a specific alert and remains in the document workspace.

Likely product improvement:

- Add server-side recipient email format validation to `ShareEvent`.

### Care Team Invites

Current surface:

- `CareTeamMembership` validates name, email, role, status, uniqueness by
  dependent/user, account ownership, and inviter permissions.
- Controller coverage is strongest on successful invite flows.

Recommended probes:

- Submit blank name.
- Submit blank email.
- Submit malformed email.
- Submit a duplicate invite for the same dependent.
- Submit with no permissions selected, once the intended product behavior is
  decided.
- Confirm failed submissions do not create users or memberships.

Open product question:

- Should a care team member be allowed to have zero category permissions, or is
  that an invalid invite?

### Documents

Current surface:

- Upload requires an attached file.
- Edit updates metadata only.
- Controller tests already cover missing file and cross-account access.

Recommended probes:

- Edit a document with a blank title.
- Upload without a file through the browser and verify the user-visible error.
- Try unsupported file types only if the product decides to restrict file types.

Lower priority:

- Cross-account document access is already covered well at the Rails level. Add
  browser coverage only if the product needs a polished 404/session experience.

### AI Assistant

Current surface:

- Blank query does not create a pipeline run.
- `Agentic::Error` is rescued and rendered as a search error.

Recommended probes:

- Submit a query that returns no evidence.
- Simulate `Agentic::Error` and verify the UI shows a useful fallback message.
- Simulate pipeline/LLM failure and confirm the page does not crash.
- Confirm no partial answer is displayed when the failure path runs.

Implementation note:

- These probes may need a test-only stub, fixture, or controllable pipeline
  failure mode. Avoid live model calls in default QA harness runs.

## Mobile Sweeps

Add mobile viewport coverage after the first negative probes exist. Start with
the same workflows rather than a separate mobile-only suite:

- Auth sign in and invalid sign in.
- Document list and share modal.
- Care team invite form.
- AI assistant empty and error states.
- Public home navigation and primary CTAs.

Recommended command shape:

```bash
ruby scripts/paper_bridge_qa_harness.rb bughunt mobile-negative tests/e2e/regressions
```

The exact folder can change, but the run should write named artifacts under
`tmp/qa-artifacts/bugs/<bug-id>/`.

## Prioritization

Recommended first pass:

1. Sharing no-document and blank/malformed-recipient probes.
2. Care team blank/malformed/duplicate invite probes.
3. AI assistant simulated failure probe.
4. Mobile viewport sweep for auth, sharing, and care team forms.

Defer:

- Role-based admin versus care-team behavior until the product defines what care
  team members can do differently.
- Cross-browser expansion beyond Chromium.
- Unsupported upload-type probes until file type restrictions are a product
  requirement.
