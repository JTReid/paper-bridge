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
| [Current Product Shape](runbooks/current-product-shape.md) | Implemented first-run guidance, profile, family calendar, document selection/deletion, access, sharing, and billing behavior plus focused harness commands. |
| [Profile Management](runbooks/profile-management.md) | Split names, matching creation/edit fields, preserved legacy school details, profile deletion, and the separate existing-name backfill script. |
| [Agentic Pipeline Framework](runbooks/agentic-pipeline.md) | Generic `Agentic::Pipeline` contract, AI setup/check Rake tasks, and the distinction between test and deployed configuration checks. |
| [Billing](runbooks/billing.md) | Hosted profile pricing, opt-in card-required 90-day trial, trial-preserving Portal, Checkout recovery, allowance enforcement, reminder setup, safe company-test webhooks, and rollout boundaries. |
| [Document Ingestion](runbooks/document-ingestion.md) | Upload, preparation, independent summary/search readiness, full processing retries, and interrupted-worker lifecycle. |
| [Document Uploads](runbooks/document-uploads.md) | File-only upload, live list updates, retry from the saved original, duplicate protection, metadata generation, and release-time AI setup. |
| [AI Assistant Search](runbooks/ai-assistant-search.md) | Durable asynchronous questions, streamed drafts, dependent-scoped retrieval, citations, and direct email of one completed answer without source documents. |
| [Saved Answers And Meeting Preparation](runbooks/saved-answers.md) | Private answer snapshots, library search, reusable meeting collections, responsive batch selection with separate live search, and in-place meeting changes that preserve browsing state. |
| [Care Team Contacts](runbooks/care-team-access.md) | Profile-scoped contact details, email-sharing recipients, and account access boundaries. |
| [Document Sharing](runbooks/document-sharing.md) | Current email-attachment sharing behavior and validation surface. |
| [QA Troubleshooting](runbooks/qa-troubleshooting.md) | Local QA harness for browser bug reproduction, artifacts, password reset, document sharing and answer email SMTP checks, and verification. |
| [Browser QA](runbooks/browser-qa.md) | Playwright folder structure, environment, and direct iteration commands. |
| [QA Seed Data](runbooks/qa-seed-data.md) | Synthetic processed-document corpus for development QA and bug hunting. |
| [Negative Error-State Probes](runbooks/negative-error-state-probes.md) | Recommended future QA probes for invalid, empty, failed, and edge-case product states. |

## Product References

The product PDFs in this directory are source material for PaperBridge/KeepSafe
strategy and requirements. Keep derived implementation decisions in Markdown
docs so they can be indexed and validated.

Local planning notes stored beside this checkout:
[Meeting Preparation Ideas](../../paper-bridge-to-dos/meeting-preparation-ideas.md)
records five proposed additions and suggested priorities for parent meeting
preparation. It is a brainstorm for future work, not an implementation plan.

## Maintenance

Run this before opening documentation or harness changes:

```bash
ruby scripts/check_docs_index.rb
```
