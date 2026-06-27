# Agentic Pipeline Framework Runbook

This runbook protects the generic `Agentic::Pipeline` machinery. It should stay
separate from product lifecycle details such as document ingestion, search,
sharing, or care team access.

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

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb static
ruby scripts/agentic_pipeline_harness.rb doctor
ruby scripts/agentic_pipeline_harness.rb tests
```

Live provider smoke checks are opt-in:

```bash
AGENTIC_LIVE_PROVIDER=openai AGENTIC_LIVE_MODEL=gpt-5.4-nano ruby scripts/agentic_pipeline_harness.rb live
```
