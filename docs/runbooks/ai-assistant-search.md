# AI Assistant Search Runbook

This runbook protects the dependent-scoped AI assistant and vector-search
lifecycle.

## Contract

- `GET /dependents/:dependent_id/ai-assistant` is authenticated and read-only.
  Query-string parameters never start AI work.
- `POST /dependents/:dependent_id/ai-assistant` strips and saves the question as
  a queued `AiAssistantQuery` owned by the current account, dependent, and user.
  For Turbo submissions, the browser installs that durable result first and
  then calls the query's idempotent start endpoint to enqueue
  `AnswerAiAssistantQueryJob`. This keeps a fast worker update from arriving
  before its replaceable result exists. Plain HTML submissions enqueue before
  redirecting. The start marker is saved only after Active Job accepts the job,
  so an enqueue rejection remains retryable. If the browser cannot tell whether
  the start request succeeded, it stays locked and retries that same durable
  query with bounded backoff instead of creating another paid request.
- The job rechecks that the dependent belongs to the account and that the user
  still belongs to the account before making a provider call.
- The durable state flow is `queued` to `processing` to `completed`. Retryable
  provider errors return to `queued`; terminal or configuration errors become
  `failed` with a family-safe message.
- `AnswerAiAssistantQueryJob` creates a `PipelineRun` whose subject is the
  `AiAssistantQuery`. The stripped question is also stored in
  `PipelineRun.context["query"]` for reproduction and diagnosis.
- Turbo broadcasts replace the saved query result when its state changes. While
  a query is active, the browser also reconciles it through an authenticated,
  account-, dependent-, and user-scoped status endpoint. This repairs a missed
  Cable update or subscription race without starting the query again. A final
  answer survives reload.
- The product job opts the OpenAI search-answer call into server-sent event
  streaming. Other agents and retrieval calls keep their existing buffered
  provider behavior.
- The stream keeps strict structured JSON enabled and requests the final usage
  chunk. The provider rebuilds the normal response shape so final parsing,
  token telemetry, cost tracking, and citation normalization keep using the
  existing path. Usage received before a later disconnect is retained, and
  time spent synchronously persisting and broadcasting drafts is recorded
  separately from the provider request's wall-clock duration.
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
  completed answers. Temporary failures such as rate limits, server failures,
  malformed or interrupted streams remain retryable. Refusals, content filters,
  output limits, and non-transient client errors fail once without repeating
  the same paid request. Retry and failure paths clear provisional text.
- Turbo delivery is best-effort. A Cable failure cannot turn a paid, persisted
  final answer into a failed query.
- The dependent page gives immediate local feedback before the POST returns,
  then follows the saved query through queued, searching, drafting, completed,
  or failed UI phases.
- While one query is active, the composer and suggested-question buttons are
  locked in that browser tab. Concurrent submissions for the same user and
  dependent reuse the saved active query instead of creating another paid run.
  A visible timer starts at submission time, gives a short reassurance after
  ten seconds, and explains after thirty seconds that the user can leave while
  PaperBridge keeps working.
- The page says that most answers begin appearing within about 30 seconds. It
  does not promise a hard deadline.
- The result itself is not a live region because repeated draft replacements
  would make screen readers reread the growing answer. A separate polite status
  announcement reports phase changes and longer waits.
- Turbo page caching is disabled for this screen, so returning to it reloads the
  latest durable query instead of restoring a stale in-progress snapshot.
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
- The local `gpt-5.6-luna` rate card prices input, including cached input, at
  $0.20 per million tokens and output at $1.20 per million tokens.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/paper_bridge_harness.rb access
```
