# PaperBridge Agent Map

This file is the short entry point for AI-assisted work in PaperBridge. Keep it
small and link to deeper docs instead of turning it into a manual.

## Start Here

- Product and setup basics: `README.md`
- Knowledge base index: `docs/README.md`
- Agent operating loop: `docs/agent-harness.md`
- Architecture map: `docs/architecture-map.md`
- Validation commands: `docs/validation.md`
- Current product shape: `docs/runbooks/current-product-shape.md`
- Agentic pipeline harness: `docs/runbooks/agentic-pipeline.md`
- QA troubleshooting harness: `docs/runbooks/qa-troubleshooting.md`

## Repo Shape

PaperBridge is a Rails 8.1 app on Ruby 4.0. The frontend uses Hotwire,
Stimulus, Turbo, Propshaft, and server-rendered Rails views. Tests are
Minitest-based. Background work uses Solid Queue.

Important directories:

- `app/models` contains Active Record models and core domain relationships.
- `app/controllers`, `app/views`, and `app/javascript/controllers` contain
  request, rendering, and Stimulus behavior for user workflows.
- `app/services` contains business workflow objects and agentic pipeline code.
- `test` contains Minitest coverage for models, services, controllers, and
  system behavior.
- `docs` contains repo-local product, architecture, and implementation notes.
- `scripts` contains harness scripts and focused local validation tools.

## Working Rules

- Prefer existing Rails, service, and Stimulus patterns before adding new
  abstractions.
- Keep changes scoped to the requested behavior. Do not rewrite unrelated
  files.
- Use Devise for authenticated users unless a later product decision replaces
  it.
- Use the shared `Agentic::Pipeline` foundation for AI workflows.
- Keep live model checks explicit opt-in commands. Do not add live checks to
  default CI without a team decision.
- Do not commit secrets or local-only config.
- When adding or changing durable knowledge, update `docs/README.md`.
- When a repeated instruction can be enforced mechanically, prefer a script,
  test, lint, or CI check over another prose rule.

## Validation Expectations

Run the smallest meaningful check for the change first, then broaden when risk
justifies it. Common commands are documented in `docs/validation.md`.

For documentation or harness changes, run:

```bash
ruby scripts/check_docs_index.rb
```

For current product-shape work, start with:

```bash
ruby scripts/paper_bridge_harness.rb static
```

For browser QA or bug reproduction work, start with:

```bash
ruby scripts/paper_bridge_qa_harness.rb doctor
```

For agentic pipeline work, start with:

```bash
ruby scripts/agentic_pipeline_harness.rb static
```

Before committing broader product-shape changes, run:

```bash
ruby scripts/paper_bridge_harness.rb review
```

Before committing broader agentic changes, run:

```bash
ruby scripts/agentic_pipeline_harness.rb review
```
