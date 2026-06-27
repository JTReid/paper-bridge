# QA Troubleshooting Runbook

This runbook defines the local QA harness used to reproduce, diagnose, and
verify browser-facing bugs in PaperBridge.

The QA harness is separate from the development/product-shape harness. The
development harness answers "did this change preserve the current product
contract?" The QA harness answers "can we reproduce the bug, collect useful
artifacts, and prove the fix?"

## Scope

- The QA harness runs against `RAILS_ENV=test`.
- The harness can prepare the test database and load deterministic fixtures.
- The harness can start and stop a local Rails test server.
- Browser tests use Playwright and target Chromium by default for fast local
  troubleshooting.
- QA artifacts are local-only and are not committed.

## Commands

```bash
ruby scripts/paper_bridge_qa_harness.rb doctor
ruby scripts/paper_bridge_qa_harness.rb db
ruby scripts/paper_bridge_qa_harness.rb assets
ruby scripts/paper_bridge_qa_harness.rb smoke
ruby scripts/paper_bridge_qa_harness.rb browser
ruby scripts/paper_bridge_qa_harness.rb bughunt
ruby scripts/paper_bridge_qa_harness.rb review
```

## Artifact Policy

Playwright writes screenshots, videos, traces, reports, and logs under
`tmp/qa-artifacts/`. These files are generated diagnostics and should remain
local.

Use `bughunt` when reproducing or verifying a specific defect. It records
screenshots, traces, and videos even when the test passes.

Use `smoke` for fast confidence that the browser harness can boot the app and
exercise the core workflow.

## Initial Browser Surface

- Public home page loads with entry actions.
- Sign-in page loads.
- A fixture admin can sign in and reach the dashboard.
- A dependent workspace opens.
- The documents page opens and the share modal can be opened.
- The care team page opens.
- The AI assistant page opens without submitting a query.
