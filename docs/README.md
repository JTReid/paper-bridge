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
| [Current Product Shape](runbooks/current-product-shape.md) | Implemented product surface that product-level harness commands should cover. |
| [Agentic Pipeline Framework](runbooks/agentic-pipeline.md) | Generic `Agentic::Pipeline` framework contract. |
| [Billing](runbooks/billing.md) | Stripe Checkout, Customer Portal, subscription gate, webhook sync, and super-admin billing overview. |
| [Document Ingestion](runbooks/document-ingestion.md) | Upload, preparation, page, chunk, summary, embedding, and timeline lifecycle. |
| [AI Assistant Search](runbooks/ai-assistant-search.md) | Dependent-scoped query embedding, vector retrieval, access filtering, and answer synthesis. |
| [Care Team Access](runbooks/care-team-access.md) | Account, dependent, care team invitation, and category-permission behavior. |
| [Document Sharing](runbooks/document-sharing.md) | Current email-attachment sharing behavior and validation surface. |
| [QA Troubleshooting](runbooks/qa-troubleshooting.md) | Local QA harness for browser bug reproduction, artifacts, and verification. |
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
