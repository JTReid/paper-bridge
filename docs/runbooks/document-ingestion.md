# Document Ingestion Runbook

This runbook protects the current upload-to-ingestion lifecycle for PaperBridge
documents.

## Contract

- `Document` is the first-class domain record for uploads and processing state.
- Each `Document` belongs to an `Account`, a `Dependent`, and a `User`.
- Each `Document` has one Active Storage attachment named `file`.
- Active Storage upload completion is followed by `Document.after_create_commit`.
- The callback marks the document `queued` and enqueues `ProcessDocumentJob`.
- Development and production use Solid Queue for Active Job-backed document
  processing. Development queue records live in `paper_bridge_development_queue`.
- `ProcessDocumentJob` prepares the document before running the ingestion
  pipeline.
- Current deterministic preparation supports text-like uploads and PDFs:
  `application/json`, `text/csv`, `text/markdown`, `text/plain`, and
  `application/pdf`.
- Text uploads are normalized into `documents.prepared_payload`.
- PDF uploads are prepared through `Documents::PreparePdf`.
- PDF preparation renders every page at 300 DPI, OCRs every page, extracts
  embedded text for every page, and stores page-level artifacts in
  `DocumentPage` records.
- `DocumentPage` stores page number, embedded text, OCR text, metadata, status,
  and a page image attachment.
- `ProcessDocumentJob` creates a `PipelineRun` for the document subject.
- `Agentic::DocumentIngestionPipeline` executes `Agents::DocumentChunker`,
  `Agents::DocumentSummarizer`, `Agents::DocumentEmbedder`, and
  `Agents::TimelineEventExtractor`.
- The chunker processes prepared pages with previous/current/next page context,
  sends page text and screenshots through the provider abstraction, and creates
  labeled `DocumentChunk` records.
- Each chunk belongs to the document page where the chunk starts.
- `DocumentEmbedding` stores generated pgvector embeddings for chunks using
  provider/model strings, dimensions, distance metric, and the vector value.
- `TimelineEvent` stores source-grounded timeline events extracted from chunks.
- Pipeline logs, activity entries, and LLM telemetry are recorded on the
  `PipelineRun`.
- Successful processing marks the document `processed`; failures mark it
  `failed`.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/agentic_pipeline_harness.rb queue
```

For local PDF binary availability:

```bash
ruby scripts/agentic_pipeline_harness.rb pdf-tools
```
