# Architecture Map

PaperBridge is currently a Rails 8.1 greenfield application. The first
foundation includes Devise authentication, simple user roles, and the shared
agentic pipeline framework ported from Scoutspace.

## Application Shape

- `User` is Devise-backed and currently carries the first authorization seam:
  `family_admin`, `profile_user`, and `platform_admin`.
- `Agentic::Pipeline` orchestrates ordered agent execution, shared pipeline
  context, validator pass-through behavior, progress tracking, and durable
  `PipelineRun` instrumentation.
- `PipelineRun` is the durable workflow envelope for agentic work. It owns
  state, source context, activity entries, logs, and telemetry summaries.
- `Llm`, `AgentType`, `Prompt`, and `JsonSchema` store provider/model/prompt
  configuration in the database.
- Provider classes under `Agentic::Providers` expose the common provider
  interface used by agents: `call`, `parse_response`, and
  `.default_operation_type`.

## Current Boundaries

- Authentication is real; family/profile/document domain models are not created
  yet.
- Authorization is role-only until Family Unit and Profile models exist.
- Document upload, S3 storage, OCR, and document-processing pipelines are the
  expected next product slice.
- Live model checks are opt-in and should use fake or in-house test data for
  this spike.
