# PaperBridge Knowledge Base

This directory is the repo-local system of record for product, architecture,
and implementation notes that should be discoverable by humans and agents.

When adding a tracked Markdown doc under `docs/`, add it to this index. The docs
check enforces that every tracked, non-ignored Markdown file is linked here.

## Core Maps

| Doc | Purpose |
| --- | --- |
| [Agent Instructions](../AGENTS.md) | Short repo entry point for AI-assisted work. |
| [Agent Harness](agent-harness.md) | Operating loop for agent-assisted development in this repo. |
| [Architecture Map](architecture-map.md) | High-level map of the Rails app, domain areas, and code ownership landmarks. |
| [Validation](validation.md) | Local and CI validation commands, plus when to use each one. |
| [Agentic Pipeline Runbook](agentic-pipeline-runbook.md) | Legacy entry point for focused agentic runbooks. |

## Runbooks

| Doc | Purpose |
| --- | --- |
| [Encrypted Credentials](runbooks/credentials.md) | Separate development, staging, and production credentials, independent keys, and Heroku configuration. |
| [Current Product Shape](runbooks/current-product-shape.md) | Implemented first-run guidance, profile, interruption-free family calendar, document, access, sharing, and billing behavior plus focused harness commands. |
| [Profile Management](runbooks/profile-management.md) | Split names, creation/edit fields, profile deletion, and the separate existing-name backfill script. |
| [Agentic Pipeline Framework](runbooks/agentic-pipeline.md) | Generic `Agentic::Pipeline` framework contract. |
| [Billing](runbooks/billing.md) | Hosted profile-quantity pricing, prorated increases and renewal-time decreases, safe test setup, profile allowance enforcement, legacy rollout boundary, and webhook-synchronized Turbo activation. |
| [Document Ingestion](runbooks/document-ingestion.md) | Upload, preparation, page, chunk, summary, embedding, and timeline lifecycle. |
| [Document Uploads](runbooks/document-uploads.md) | File-only upload, 50-file batches, profile-scoped duplicate protection, storage-only files, one-time metadata generation, and deployment. |
| [AI Assistant Search](runbooks/ai-assistant-search.md) | Durable asynchronous questions, streamed answer drafts, dependent-scoped retrieval, source validation, page-linked citations, access filtering, and answer synthesis. |
| [Care Team Access](runbooks/care-team-access.md) | Account, dependent, care team invitation, and category-permission behavior. |
| [Document Sharing](runbooks/document-sharing.md) | Current email-attachment sharing behavior and validation surface. |
| [QA Troubleshooting](runbooks/qa-troubleshooting.md) | Local QA harness for browser bug reproduction, artifacts, password reset and document sharing SMTP checks, and verification. |
| [Browser QA](runbooks/browser-qa.md) | Playwright folder structure, environment, and direct iteration commands. |
| [QA Seed Data](runbooks/qa-seed-data.md) | Synthetic processed-document corpus for development QA and bug hunting. |
| [Negative Error-State Probes](runbooks/negative-error-state-probes.md) | Recommended future QA probes for invalid, empty, failed, and edge-case product states. |

## Product References

The product PDFs in this directory are source material for PaperBridge/KeepSafe
strategy and requirements. Keep derived implementation decisions in Markdown
docs so they can be indexed and validated.

## Maintenance

Run this before opening documentation or harness changes:

```bash
ruby scripts/check_docs_index.rb
```
