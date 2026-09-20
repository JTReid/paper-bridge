# AI Assistant Search Runbook

This runbook protects the dependent-scoped AI assistant and vector-search
lifecycle.

## Contract

- `GET /profiles/:dependent_id/ai-assistant` is authenticated and read-only.
  Query-string parameters never start AI work.
- `POST /profiles/:dependent_id/ai-assistant` strips and saves the question as
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
- Each enqueued question records its Active Job UUID, which remains the same
  across automatic retries. Each pipeline run also records the attempt's Solid
  Queue ID. The recurring `ReconcileAiAssistantQueriesJob` checks confirmed
  worker failures every minute and marks interrupted questions failed so the
  user can ask again. It preserves running, queued, and scheduled retry attempts
  and completed answers; elapsed time alone never marks a question failed.
  Jobs queued before this tracking was added acquire their UUID when they start.
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
- The source-opening workflow is a family-account surface. Care Team stores
  contacts only; adding a contact grants no document or assistant access.
- A completed answer can be copied into the user's private saved research
  library. `SavedAnswer` owns that snapshot separately from query execution;
  library search and meeting preparation never enqueue an answer job. See
  [Saved Answers And Meeting Preparation](saved-answers.md).
- If retrieval returns no chunks, answer synthesis is skipped without making a
  chat completion call. This is a completed query with no supported answer, not
  a failed job.
- Retrieval is constrained by account before results are ranked.
- Retrieval requires a fully processed document with completed initial
  metadata. Failed documents and documents being retried contribute no chunks,
  even when an earlier attempt left embeddings behind. Saved answers remain
  unchanged snapshots during document retries.
- `Documents::SearchAccessProfile` requires membership in the requested account;
  a care team contact or membership in another account grants no search access.
- Retrieval is constrained by both document category and
  `Documents::SearchAccessProfile` labels before results are ranked.
- Family-facing answers expose numbered sources, canonical document titles,
  page numbers, excerpts, and limitations without internal record IDs.
- Pipeline logs, activity entries, and LLM telemetry are recorded on the
  `PipelineRun`.
- The local `gpt-5.6-luna` rate card prices input, including cached input, at
  $0.20 per million tokens and output at $1.20 per million tokens.

## Emailing One Answer

- A completed query with nonblank answer text offers **Email answer** beside
  **Save answer**. Emailing reads that existing `AiAssistantQuery`; it creates
  no saved answer, new model, or AI request.
- The dialog accepts one email address and an optional message. A Care Team
  contact from the current profile can fill the address as a shortcut. The
  family can type any address, including replacing a selected contact's email.
- `AiAssistantEmailsController` scopes both the dialog and send action to the
  current user, account, and profile, and only accepts completed answers with
  content. The server loads the answer from storage instead of accepting answer
  text from the browser.
- `AiAssistantQueryMailer` sends HTML and plain-text versions through the
  existing mail configuration. The email contains the original question, full
  answer, generation date, optional message, source numbers with document/page
  labels, and existing **Things to keep in mind** qualifications. Reply-To is
  the sender's email address.
- Source documents are excluded: no attachments, original-file contents,
  citation excerpts, or links to authenticated documents are added to the email.
  Sending an answer grants no account access or recipient login.
- Sending disables the submit button while the request runs. Success keeps the
  dialog open with the destination address and a Done button. Invalid recipients
  and delivery failures keep the address and message available for correction.
  Closing or Escape returns focus to the answer's Email answer action.
- Delivery is attempted in the request so a mail-server rejection can be shown
  immediately. Success means the configured mail transport accepted the message;
  it does not confirm delivery to the recipient's inbox.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/paper_bridge_harness.rb access
ruby scripts/paper_bridge_harness.rb sharing
ruby scripts/paper_bridge_qa_harness.rb workflow ai
```

The sharing Rails group covers answer ownership, recipient validation, delivery
failure handling, preserved question/answer content, and HTML/text mail without
attachments or private source links. The AI browser workflow uses one synthetic
completed answer and verifies the manual recipient and Care Team shortcut,
validation recovery, dialog focus, phone layout, and accessibility without
saving the answer or calling AI.

For real local SMTP capture, start Mailpit and run:

```bash
ruby scripts/paper_bridge_qa_harness.rb mailpit tests/e2e/product/ai_assistant_email_mailpit.spec.js
```

That check verifies the destination and Reply-To, original response content,
source labels and date, absence of source attachments/excerpts/private links,
and no message sent for an invalid address. It uses local SMTP and does not
verify external inbox delivery.
