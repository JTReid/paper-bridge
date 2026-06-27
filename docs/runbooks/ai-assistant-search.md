# AI Assistant Search Runbook

This runbook protects the dependent-scoped AI assistant and vector-search
lifecycle.

## Contract

- `GET /dependents/:dependent_id/ai-assistant` is authenticated.
- Blank search queries render without creating a `PipelineRun` or calling an LLM
  provider.
- Nonblank search queries create a `PipelineRun` for the current account and
  selected dependent.
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
- If retrieval returns no chunks, answer synthesis is skipped without making a
  chat completion call.
- Retrieval is constrained by account before results are ranked.
- Retrieval is constrained by `Documents::SearchAccessProfile` labels before
  results are ranked.
- Search results expose answer text, citations, limitations, chunk text, label,
  document title, page number, distance, and similarity.
- Pipeline logs, activity entries, and LLM telemetry are recorded on the
  `PipelineRun`.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/paper_bridge_harness.rb access
```
