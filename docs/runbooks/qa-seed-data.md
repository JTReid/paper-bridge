# QA Seed Data Runbook

The QA seed corpus is synthetic data for browser QA, bug hunting, and
troubleshooting. It mirrors the current processed-document shape observed in
development, then adds lifecycle edge cases without copying private uploaded
document text into the repository.

## Command

```bash
ruby scripts/paper_bridge_qa_harness.rb seed
```

The command runs `bin/rails db:prepare`, loads normal Rails seeds, then loads
`db/seeds/qa_harness.rb` with `PAPER_BRIDGE_SEED_QA=1`.

The browser harness also loads this seed into `RAILS_ENV=test` during
`ruby scripts/paper_bridge_qa_harness.rb db`, so Playwright can assert seeded
edge states without depending on local development data.

Sign in with:

```text
qa-family-admin@example.test / password
```

## Seeded Shape

- Account: `PaperBridge QA Harness`
- Billing: active synthetic `BillingSubscription` so global subscription gates
  do not block seeded product workflows
- Dependent: `Avery Morgan`
- Care team: one active teacher and one invited therapist
- Documents: 11 synthetic PDF records
- Baseline documents: 4 processed records matching the observed development
  corpus shape
- Edge documents: uploaded, queued, processing, failed preparation, processed
  without embeddings, processed with partial embeddings, and processed without a
  summary
- Pages: 25 pages with Active Storage page images for seeded prepared or
  processing pages
- Chunks: 71 page-aware chunks across medical, education, therapy, behavior,
  general, and legal labels
- Embeddings: 67 deterministic `text-embedding-3-large` pgvector rows
- Timeline events: 54 source-grounded synthetic events
- Pipeline runs: 8 total, including completed, failed, pending, and processing
  states
- Share events: pending, sent, and failed share history records

The seed temporarily routes Active Storage writes to disk-backed services so a
development QA corpus does not require S3 credentials. Development uses the
local disk service; test uses the test disk service.

## Safety

The seed is idempotent for the `PaperBridge QA Harness` account. Re-running it
removes and recreates only records under that QA account. It is guarded to run
only in development or test.
