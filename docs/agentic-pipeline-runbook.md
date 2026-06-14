# Agentic Pipeline Runbook

This runbook protects the shared agentic pipeline machinery, not the product
behavior of every pipeline that uses it.

Implementation-specific behavior belongs in the runbook and tests for that
feature. For example, a future document intake harness should prove upload,
OCR, categorization, summarization, persistence, and user-visible result
semantics. This generic harness only proves that the pipeline framework is
healthy.

## Critical Path Contract

The generic Agentic Pipeline harness protects these framework guarantees:

- Pipeline execution requires a resolvable `pipeline_run_gid`.
- Agents run in configured order.
- Current content and shared context move through the pipeline predictably.
- `after_execute` callbacks can add shared context for later steps.
- Validator agents can pass through current content and stop the pipeline when
  they return a non-approved status.
- Pipeline runs record started, completed, and failed states.
- Pipeline logs and activity entries are written through `PipelineRun`.
- `PipelineRun` is the durable workflow/job envelope.
- Sharing a `pipeline_run_gid` intentionally consolidates source context, logs,
  activity, and telemetry for the whole workflow.
- Configured `Llm` provider classes can be resolved and expose the expected
  provider interface.
- Structured model outputs are enforced through `JsonSchema` records.
- Live LLM checks are explicit opt-in checks, not default local or CI checks.

The generic harness does not protect:

- Prompt quality or exact model wording.
- Domain-specific extraction, mapping, validation, or persistence rules.
- Background job completion behavior.
- Every provider/model combination in production data.
- Cost ceilings beyond making provider/model drift visible.

## Validation Loop

For a quick file-shape check:

```bash
ruby scripts/agentic_pipeline_harness.rb static
```

For local provider/configuration sanity:

```bash
ruby scripts/agentic_pipeline_harness.rb doctor
```

For deterministic framework tests:

```bash
ruby scripts/agentic_pipeline_harness.rb tests
```

Before committing broader agentic framework changes:

```bash
ruby scripts/agentic_pipeline_harness.rb review
```

## Live LLM Smoke

Live model checks are useful, but they should be controlled and explicit. They
should assert provider reachability and parseable structured output only, not
exact wording or broad product behavior.

Run a live provider smoke only when intentionally validating provider access:

```bash
AGENTIC_LIVE_PROVIDER=openai AGENTIC_LIVE_MODEL=gpt-5.4-nano ruby scripts/agentic_pipeline_harness.rb live
```

Supported values for `AGENTIC_LIVE_PROVIDER` are currently `openai` and
`anthropic`. OpenAI credentials are read from `ENV["OPENAI_API_KEY"]`,
`credentials.openai.api_key`, `credentials.open_ai.api_key`,
`credentials.app.api_key`, or `credentials.api_key`. Anthropic credentials are read from
`ENV["ANTHROPIC_API_KEY"]`, `credentials.anthropic.api_key`,
`credentials.app.anthropic_api_key`, or `credentials.anthropic_api_key`.

Do not add the live command to default CI without an explicit team decision.
