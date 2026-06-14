# Validation

Use the smallest check that gives meaningful confidence, then broaden based on
the risk of the change.

## Documentation And Harness Changes

```bash
ruby scripts/check_docs_index.rb
```

This verifies that required agent-facing docs exist and that Markdown files in
`docs/` are linked from `docs/README.md`.

## Agentic Pipeline Harness

```bash
ruby scripts/agentic_pipeline_harness.rb static
ruby scripts/agentic_pipeline_harness.rb doctor
ruby scripts/agentic_pipeline_harness.rb tests
ruby scripts/agentic_pipeline_harness.rb rubocop
ruby scripts/agentic_pipeline_harness.rb review
```

This is a framework harness for agentic pipeline execution, provider wiring,
logging, telemetry, database-backed model/prompt/schema configuration, and
deterministic Minitest coverage.

Live LLM checks are explicit opt-in checks:

```bash
AGENTIC_LIVE_PROVIDER=openai AGENTIC_LIVE_MODEL=gpt-5.4-nano ruby scripts/agentic_pipeline_harness.rb live
```

Do not add live checks to default CI without an explicit team decision.

## Rails Tests

```bash
bin/rails test
```

Prefer targeted tests while iterating:

```bash
bin/rails test test/services/agentic/pipeline_test.rb
```

## Ruby Style

```bash
bin/rubocop path/to/file.rb
```

Run full RuboCop when the change spans many Ruby files:

```bash
bin/rubocop
```

## Security

```bash
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
```

## Full Local CI

```bash
bin/ci
```
