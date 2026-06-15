# Agent Harness

This document describes how to make agent-assisted development effective in
PaperBridge. The goal is to keep useful context inside the repository, make
local validation easy to run, and turn recurring review feedback into durable
checks.

This follows the harness-engineering pattern described by OpenAI: keep the
agent entry point short, put durable context in repo-local docs, and prefer
executable feedback loops over prose-only instructions:
https://openai.com/index/harness-engineering/

## Context Loading Order

Use this order when starting a task:

1. Read `AGENTS.md` for the short repo map.
2. Read the relevant entry in `docs/README.md`.
3. Inspect the code and tests closest to the requested behavior.
4. Check `docs/validation.md` for the smallest meaningful validation command.

Avoid loading every doc by default. Use the index to pull only the context that
matters for the task.

## Harness Workflow

Harness docs and scripts are tracked repo assets. Treat changes to them like
product code: keep them scoped, validate them, and commit them only when the
harness contract or durable workflow intentionally changed. Local environment
state, generated artifacts, logs, and secrets should remain local.

For each new feature:

1. Review the feature requirements against the relevant runbook.
2. Update the local harness only when the new work exposes a real gap.
3. Implement the feature.
4. Run a targeted validation command.
5. Broaden validation if the change touches shared behavior, security,
   persistence, migrations, background jobs, or asset compilation.
6. Update docs when durable behavior, commands, or architecture changed.

The document ingestion pipeline is now encoded in the agentic harness as a
feature-specific command:

```bash
ruby scripts/agentic_pipeline_harness.rb documents
```

Use that command when changing document upload callbacks, `ProcessDocumentJob`,
`Agentic::DocumentIngestionPipeline`, `Agents::DocumentChunker`,
`Agents::DocumentEmbedder`, `Agents::TimelineEventExtractor`, prompt/schema
seeds, chunk persistence, embedding persistence, or chunk-sourced timeline event
persistence. The same command also covers the first search pipeline:
`GET /search`, `Agentic::DocumentSearchPipeline`, `Agents::QueryEmbedder`,
`Agents::VectorRetriever`, `Agents::SearchAnswerGenerator`, account-scoped
vector retrieval, role-derived chunk-label filtering, structured answer
synthesis with citations, and the read-only `GET /timeline` view.

Keep the harness mostly measurement and guidance. If a harness change alters
production app behavior, treat that as suspicious and ask whether it belongs in
the product change instead.

## What To Encode

Encode durable knowledge in the repo when it affects future work:

- Product behavior that is not obvious from the UI.
- Architecture boundaries or ownership rules.
- Non-obvious commands, setup, or validation workflows.
- Repeated review feedback.
- Known limitations that should shape future implementation.

Prefer enforceable checks when possible. A script, test, lint, or CI step is
more reliable than prose when the rule is objective.
