# Document Sharing Runbook

This runbook protects the document sharing behavior implemented in the Rails app
today.

Important: current sharing sends selected files as email attachments. The
product requirements also describe tokenized, revocable, time-limited external
links. That link-based model is not implemented yet, so it belongs in future
product scope rather than this operational harness contract.

## Contract

- Sharing requires authentication.
- A share can include one or more selected documents from the current account.
- Document IDs outside the current account are ignored by the controller scope.
- A share requires at least one selected account document.
- Selected email attachments are capped by `ShareEventsController`.
- `ShareEvent` stores account, sender, recipient email, subject, message,
  status, sent timestamp, and error message.
- `SharedDocument` joins a share event to documents and requires the document to
  belong to the share account.
- `DocumentShareMailer` sends the selected documents as attachments.
- Duplicate attachment filenames are made unique.
- Successful delivery marks the share event `sent`.
- Delivery failures mark the share event `failed` when a persisted share event
  exists.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb sharing
```
