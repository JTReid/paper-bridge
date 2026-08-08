# AI Assistant Search Runbook

This runbook protects the dependent-scoped AI assistant and vector-search
lifecycle.

## Contract

- `GET /dependents/:dependent_id/ai-assistant` is authenticated and read-only.
  Query-string parameters never start AI work.
- `POST /dependents/:dependent_id/ai-assistant` strips and saves the question as
  a queued `AiAssistantQuery` owned by the current account, dependent, and user,
  then enqueues `AnswerAiAssistantQueryJob`.
- The job rechecks that the dependent belongs to the account and that the user
  still belongs to the account before making a provider call.
- The durable state flow is `queued` to `processing` to `completed`. Retryable
  provider errors return to `queued`; terminal or configuration errors become
  `failed` with a family-safe message.
- `AnswerAiAssistantQueryJob` creates a `PipelineRun` whose subject is the
  `AiAssistantQuery`. The stripped question is also stored in
  `PipelineRun.context["query"]` for reproduction and diagnosis.
- Turbo broadcasts replace the saved query result when its state changes. A
  final answer survives reload, and reloading the page does not run the query
  again.
- The product job opts the OpenAI search-answer call into server-sent event
  streaming. Other agents and retrieval calls keep their existing buffered
  provider behavior.
- The stream keeps strict structured JSON enabled and requests the final usage
  chunk. The provider rebuilds the normal response shape so final parsing,
  token telemetry, cost tracking, and citation normalization keep using the
  existing path.
- Only progressive plain text from the first top-level `answer` field is saved
  to `draft_answer`. Draft writes and Turbo replacements are batched, escaped as
  plain text, and never expose raw SSE events or incomplete JSON.
- The current structured schema orders `answer`, `citations`, and `limitations`.
  Draft extraction is anchored to that top-level order and fails closed if the
  contract changes.
- Drafts do not show source links. The completed update clears the draft and
  replaces it with the fully parsed answer after citations have been allowlisted
  and rebuilt from canonical document records.
- Missing completion markers, refusals, output-limit stops, content-filter
  stops, malformed events, and non-success HTTP responses cannot become
  completed answers. Retry and failure paths clear provisional text.
- Turbo delivery is best-effort. A Cable failure cannot turn a paid, persisted
  final answer into a failed query.
- `Agentic::DocumentSearchPipeline` can run retrieval-only for debugging, or
  retrieval plus answer synthesis for the product UI.
- In answer mode, it executes `Agents::QueryEmbedder`,
  `Agents::VectorRetriever`, and `Agents::SearchAnswerGenerator`.
- `Agents::QueryEmbedder` embeds the user query with the configured embedding
  model through the provider abstraction.
- `Agents::VectorRetriever` performs local pgvector retrieval against
  `DocumentEmbedding` records.
- `Agents::SearchAnswerGenerator` answers from retrieved chunks only and
  returns structured JSON with answer text, citations, and limitations.
- The model receives temporary, request-local source numbers rather than
  database chunk or document IDs.
- Returned citations are allowlisted against that request's retrieved results;
  titles, page numbers, and excerpts are rebuilt from canonical records.
- Duplicate citations from the same document page collapse into one numbered
  source, and unknown source numbers are discarded.
- Inline answer citations and source cards link through an authenticated
  document-original endpoint. PDFs open in a new tab at the cited physical page.
- The current source-opening workflow is a family-account surface. Extending it
  to accountless care-team logins requires a shared document-access scope and is
  not implied by this citation-link feature.
- If retrieval returns no chunks, answer synthesis is skipped without making a
  chat completion call. This is a completed query with no supported answer, not
  a failed job.
- Retrieval is constrained by account before results are ranked.
- Retrieval is constrained by both document category and
  `Documents::SearchAccessProfile` labels before results are ranked.
- Family-facing answers expose numbered sources, canonical document titles,
  page numbers, excerpts, and limitations without internal record IDs.
- Pipeline logs, activity entries, and LLM telemetry are recorded on the
  `PipelineRun`.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/paper_bridge_harness.rb access
```
