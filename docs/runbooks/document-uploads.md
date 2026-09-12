# Document Uploads

The upload form asks only for files. The native picker has no `accept` filter,
so all file types are visible. PaperBridge does not impose a file-count limit
on an upload batch. Remove and Clear selection let the user adjust the files
before submitting them.

The existing processing formats are unchanged: PDF, plain text, CSV, Markdown,
JSON, JPEG, PNG, WebP, HEIC, HEIF, and TIFF. Other file types, including Word,
are saved without conversion or AI processing. The normalizer still rejects
malformed supported images and requires one image per image document. Storage
support does not add Word parsing or conversion.

Each selected file has a Remove button, and Clear selection empties the entire
pending selection. Both update the actual file input as well as the displayed
list. Removing the last file restores required-file validation and the setup
tour's choose-files step. Choosing or dropping another set replaces the current
selection, as before. These controls never delete saved documents.

Single, multiple, and partially successful uploads return to the profile's
unfiltered Documents list. Notices distinguish documents being prepared from
files saved without processing and include reasons for individual failures.
If no files succeed, the upload form shows its errors. Category-filtered pages
do not preassign a category to new uploads.

## Processing Limits

The following application-imposed limits have been removed:

| Previous limit | Current behavior |
| --- | --- |
| 50 files per upload batch | All selected files are submitted and handled individually. |
| Rack's 128-file multipart threshold | The request parser has no configured file-count ceiling. |
| Rack's 4,096-part multipart threshold | The request parser has no configured part-count ceiling. |
| First 200,000 bytes of a text upload | Preparation retains the entire text and preserves valid UTF-8 characters. |
| First 60,000 characters of summary evidence | Summarization receives all available document chunks. |
| 50 MB for HEIC/HEIF/TIFF source images | No application byte-size cutoff before conversion. |
| 15 MB for JPEG/PNG/WebP or converted images | No application byte-size cutoff before attachment. |
| 40,000,000 decoded image pixels | No application pixel-count cutoff; dimensions are preserved. |

`config/initializers/document_uploads.rb` disables Rack's two multipart count
limits using their supported zero values. Other multipart parsing checks remain
in place. Parser regressions cover 128 files and 4,097 form parts.

This does not promise processing of arbitrarily large files. Hosting resources,
request limits, model context windows, output budgets, and provider image
constraints still apply. See the [OpenAI image-input requirements](https://developers.openai.com/api/docs/guides/images-vision#image-input-requirements).
PaperBridge does not silently clip source text or summary evidence to avoid a
provider limit. Supported formats, image decoding checks, single-image
validation, JPEG conversion settings, and network timeouts remain in place.

## Storage-Only Files

Non-processable documents have status `stored`, shown as **Stored—not processed**.
Their original bytes and filenames are preserved, and the original-file route
forces downloads for non-PDF files, including HTML and SVG. Active Storage
analysis is skipped for storage-only uploads as well. They remain available in
the profile's Documents list, filename search, category filters, and sharing.

Storage-only files start in General with a blank description and
`initial_metadata_pending=false`; their category and description are editable
immediately. Their summary and Ask PaperBridge cards say **Not supported**,
not waiting or failed. They receive no ingestion job, pipeline run, extracted
pages, chunks, embeddings, or AI-generated metadata. Both processing jobs also
ignore non-processable files if invoked directly, and vector search explicitly
excludes stored records even if stale embeddings exist.

## Duplicate Uploads

The web upload path compares the attached file's existing Active Storage
checksum and byte size against documents in the same profile. Renaming an
identical file does not bypass the check; using an existing name for different
contents is allowed, as is storing the same file in another profile. Existing
attachments participate immediately without a backfill. Images that require
conversion are compared after the existing normalization step.

The check and save run under a profile row lock so simultaneous web requests
cannot both insert the same file. Duplicates within a batch are rejected after
the first copy; other unique files still upload. No existing document is
overwritten or deleted, and rejected duplicates do not create orphan blobs.
This is an upload guard, not a uniqueness restriction on Rails console edits.

## One-Time Category And Description

New processable web uploads set `initial_metadata_pending` to true. The existing PDF/text
summary call and image extraction call return a category from the six existing
categories plus a short, source-grounded description. The fuller summary stays
separate. This uses the same model configuration and number of AI calls.
Structured output follows the existing provider integration and the
[OpenAI structured-output contract](https://developers.openai.com/api/docs/guides/structured-outputs).

`Document#complete_initial_metadata!` validates the output, locks the record,
and saves category, description, and pending=false together. Missing/invalid
metadata fails processing without completing the step or becoming searchable.
Pending records are excluded from vector search; the existing category and
chunk-label access checks still apply afterward.

Category and description are disabled on Edit Document until this initial step
finishes; title editing remains available. The backend also rejects premature
metadata edits. A transaction-commit broadcast replaces only the metadata
fields when they become editable, leaving an unfinished title untouched.
Generated descriptions also update on an open document detail page.

Once completed, later processing retries leave category and description alone,
including user corrections. There is no automatic/manual ownership system.
Existing documents default to pending=false and are not recategorized or
redescribed, even when processing is retried. Direct console/import creation
must explicitly set pending=true to opt into the new upload behavior.

## Deployment

The Heroku release command runs migrations, then synchronizes the document
pipeline configuration and checks it before the new release starts. The same
sequence can be run in the intended Rails environment:

```bash
bin/rails db:migrate
bin/rails runner scripts/sync_document_pipeline_configuration.rb
```

The sync updates the OpenAI and Anthropic document-summary and image-extraction
schemas, creating missing records. It also supplies a missing
`image_document_extractor` agent and active prompt, using the existing OpenAI
`gpt-5.4-mini` model record when the agent needs to be created. Existing agent
model assignments, active prompt contents, and model records are preserved.

`Documents::PipelineConfiguration.sync!` runs the configuration check inside
the same transaction. Invalid existing configuration rolls back the sync and
fails the release. It does not reseed the application, process documents, or
call an AI provider. Existing failed uploads still need a separate processing
retry after their configuration is repaired.

To inspect the currently stored configuration without changing it:

```bash
ruby scripts/agentic_pipeline_harness.rb config-check
RAILS_ENV=production ruby scripts/agentic_pipeline_harness.rb config-check
```

`config-check` uses the selected `RAILS_ENV`, defaulting to `development`, and
exits unsuccessfully when stored schemas, agents, prompts, or model bindings
do not meet the current document pipeline contract. It never loads seeds or
calls AI. Heroku normally uses `RAILS_ENV=production` even when the app name
includes development. The harness's `doctor` command instead loads seeds in
the test database; passing it does not verify a deployed environment.

`Documents::MetadataSchemas` defines summary/image output contracts;
`Documents::PipelineSchemas` defines chunk/timeline output contracts. Seeds
and configuration checks use these shared definitions. The older
`scripts/update_document_metadata_schemas.rb` remains a targeted update of
only the four summary/image schema records, including creating missing ones.
It does not replace the release configuration check.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb document-ui
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/paper_bridge_qa_harness.rb workflow documents
ruby scripts/paper_bridge_qa_harness.rb negative documents
ruby scripts/paper_bridge_qa_harness.rb workflow onboarding
```

Rails tests cover batches above the former file-count limits, mixed batches, exact duplicate detection,
normalized-image duplicates, existing attachments, immediate storage-only edits,
original download bytes and disposition, and unchanged CSV/text/image routing.
They also exercise fake AI responses through both processing jobs, completion
broadcasts, malformed output, retry safety, legacy preservation, access gates,
the former text/evidence/image boundaries, and the narrow schema updater. Browser tests use deterministic metadata
completion rather than live AI. They deliver the captured model-generated
Turbo messages in the browser because the test Cable adapter is process-local;
this checks in-place rendering, not cross-process Cable transport.
They cover selection controls, upload routes, batches above 50 files,
storage-only Word/ZIP
downloads and edits, duplicates and profile boundaries, errors, edit-field
unlocking, original-file buttons, and onboarding recovery.
