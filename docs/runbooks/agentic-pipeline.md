# Agentic Pipeline Framework Runbook

This runbook protects the generic `Agentic::Pipeline` machinery. It should stay
separate from product lifecycle details such as document ingestion, search,
sharing, or care team contacts.

## Contract

- Pipeline execution requires a resolvable `pipeline_run_gid`.
- Agents run in configured order.
- Current content and shared context move through the pipeline predictably.
- `after_execute` callbacks can add shared context for later steps.
- Validator agents can pass through current content and stop the pipeline when
  they return a non-approved status.
- Pipeline runs record started, completed, and failed states.
- Pipeline logs and activity entries are written through `PipelineRun`.
- `PipelineRun` is the durable workflow envelope for agentic work.
- Sharing a `pipeline_run_gid` intentionally consolidates source context, logs,
  activity, and telemetry for one workflow.
- Configured `Llm` provider classes can be resolved and expose the expected
  provider interface.
- Structured model outputs are enforced through `JsonSchema` records.
- Live LLM checks are explicit opt-in checks, not default local or CI checks.

## Out Of Scope

- Prompt quality or exact model wording.
- Product-specific extraction, mapping, validation, or persistence rules.
- Background job completion behavior.
- Every provider/model combination in production data.
- Cost ceilings beyond making provider/model drift visible.

## AI Setup

Use the same setup task locally and during deployment:

```bash
bundle exec rake db:migrate paper_bridge:setup_ai
```

`paper_bridge:setup_ai` creates missing defaults for three `Llm` records, nine
`AgentType` records and their active `Prompt` records, and updates fourteen
canonical `JsonSchema` records. Existing model/provider choices, agent model
assignments, and prompt content are preserved. Setup checks the resulting
configuration before committing; a failure rolls back its changes and exits
unsuccessfully. It does not call AI or process existing documents.

`db:seed` delegates to the same `Setup::AiConfiguration.call`, then retains the
existing optional QA-data seed guard. The Heroku release command runs
`bundle exec rake db:migrate paper_bridge:setup_ai`.

Setup definitions and validation live in `lib/setup/ai_definitions.rb`,
`ai_configuration.rb`, and `ai_configuration_check.rb`. They are loaded
explicitly by setup tasks and excluded from application autoloading. Runtime
agents read the persisted model, prompt, and schema records; the shared document
metadata instructions remain in `Documents::MetadataInstructions::TEXT`.

To validate stored configuration without modifying it:

```bash
bundle exec rake paper_bridge:check_ai
RAILS_ENV=production bundle exec rake paper_bridge:check_ai
```

`paper_bridge:check_ai` checks the current AI configuration without loading seeds
or calling a provider. It exits unsuccessfully when required records, model
bindings, provider operations, prompts, or schema contracts are invalid.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb static
ruby scripts/agentic_pipeline_harness.rb doctor
ruby scripts/agentic_pipeline_harness.rb tests
```

`doctor` runs the actual `paper_bridge:setup_ai` and `paper_bridge:check_ai` tasks
in the test database. It is a local setup check, not a check of deployed records.
The harness also provides a shortcut to inspect a selected environment:

```bash
ruby scripts/agentic_pipeline_harness.rb config-check
RAILS_ENV=production ruby scripts/agentic_pipeline_harness.rb config-check
```

`config-check` calls `paper_bridge:check_ai`, defaults to `development`, and
preserves a supplied `RAILS_ENV`. It is separate from `review`, which sets up and
validates test configuration. A passing `doctor` or `review` does not verify a
deployed environment.

Live provider smoke checks are opt-in:

```bash
AGENTIC_LIVE_PROVIDER=openai AGENTIC_LIVE_MODEL=gpt-5.4-nano ruby scripts/agentic_pipeline_harness.rb live
```
