# Document Ingestion Runbook

This runbook protects the current upload-to-ingestion lifecycle for PaperBridge
documents.

## Contract

- `Document` is the first-class domain record for uploads and processing state.
- Each `Document` belongs to an `Account`, a `Dependent`, and a `User`.
- Each `Document` has one Active Storage attachment named `file`.
- Multi-file upload requests create one `Document` record per uploaded file;
  one image is always one document.
- Document intake accepts text-like uploads, PDFs, and JPEG, PNG, WebP, HEIC,
  HEIF, or TIFF images. Unsupported file types are rejected before enqueueing.
- `Documents::UploadNormalizer` decodes image uploads before document creation.
  HEIC, HEIF, and TIFF sources are converted to JPEG before the normalized file
  is attached to Active Storage, so those source formats are never served to a
  browser. JPEG, PNG, and WebP sources retain their browser-safe formats. Image
  byte size and decoded pixel count are bounded before persistence and GPT
  processing.
- Active Storage upload completion is followed by `Document.after_create_commit`.
- The callback marks the document `queued` and routes image documents to
  `ProcessImageDocumentJob`; PDFs and text-like documents continue through
  `ProcessDocumentJob`.
- Development and production use Solid Queue for Active Job-backed document
  processing. Development queue records live in `paper_bridge_development_queue`.
- `ProcessDocumentJob` prepares the document before running the ingestion
  pipeline.
- Deterministic preparation through `Documents::Prepare` supports text-like
  uploads and PDFs:
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

## Image Ingestion

- `ProcessImageDocumentJob` creates a `PipelineRun` and invokes the separate
  `Agentic::ImageDocumentIngestionPipeline`.
- `Agents::ImageDocumentExtractor` sends the normalized image to GPT in one
  structured multimodal extraction request.
- The extraction result includes the most complete textual reading GPT can
  produce, a document category, summary, key points, and search chunks.
- GPT classification is metadata-only in this first iteration and never changes
  `Document.category`. The GPT-detected category is persisted with the
  extraction metadata. This first iteration does not persist
  prescription-specific fields.
- The extracted chunks are persisted as `DocumentChunk` records and
  `Agents::DocumentEmbedder` creates pgvector embeddings so image documents are
  available to the existing search pipeline.
- If extraction succeeds but a downstream step fails, the generated summary and
  chunks remain persisted. The document is marked failed and the downstream
  error remains available through `preparation_error` and the `PipelineRun`.
- The first image iteration does not add conventional OCR, a second extraction
  or verification pass, handwriting-specific model routing, region-level
  citations, multi-image documents, or timeline-event extraction. Those remain
  follow-up work informed by real image quality and extraction results.

## Validation

```bash
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/agentic_pipeline_harness.rb queue
```

For local PDF binary availability:

```bash
ruby scripts/agentic_pipeline_harness.rb pdf-tools
```

For local image codec availability:

```bash
ruby scripts/agentic_pipeline_harness.rb image-tools
```
