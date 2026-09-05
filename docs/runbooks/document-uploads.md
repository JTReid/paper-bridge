# Document Uploads

The upload form asks only for files. The native picker has no `accept` filter,
so all file types are visible; supported formats are listed beside the upload
area. `Documents::UploadNormalizer` still rejects unsupported or invalid files
before persistence. Word support, duplicate handling, and new batch limits are
not part of this change.

Each selected file has a Remove button, and Clear selection empties the entire
pending selection. Both update the actual file input as well as the displayed
list. Removing the last file restores required-file validation and the setup
tour's choose-files step. Choosing or dropping another set replaces the current
selection, as before. These controls never delete saved documents.

Single, multiple, and partially successful uploads return to the profile's
unfiltered Documents list. Notices report successful uploads and any failures.
If no files succeed, the upload form shows its errors. Category-filtered pages
do not preassign a category to new uploads.

## One-Time Category And Description

New web uploads set `initial_metadata_pending` to true. The existing PDF/text
summary call and image extraction call return a category from the six existing
categories plus a short, source-grounded description. The fuller summary stays
separate. This uses the same model configuration and number of AI calls.
Structured output follows the existing provider integration and the
[OpenAI structured-output contract](https://developers.openai.com/api/docs/guides/structured-outputs).

`Document#complete_initial_metadata!` validates the output, locks the record,
and saves category, description, and pending=false together. Missing/invalid
metadata fails processing without completing the step or becoming searchable.
Pending records are excluded from vector search, including care-team search;
the existing category and chunk-label access checks still apply afterward.

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

The migration changes only the schema. Refresh the four document-output schema
records separately, without reseeding unrelated models, prompts, or schemas:

```bash
bin/rails db:migrate
bin/rails runner scripts/update_document_metadata_schemas.rb
```

Use the intended Rails environment. Coordinate the migration, schema-record
update, and web/worker restart before accepting new uploads. The updater is
repeatable and requires all four existing records before making any changes.
Fresh databases get the same definitions through the normal seeds.

## Validation

```bash
ruby scripts/paper_bridge_harness.rb document-ui
ruby scripts/agentic_pipeline_harness.rb documents
ruby scripts/paper_bridge_qa_harness.rb workflow documents
ruby scripts/paper_bridge_qa_harness.rb negative documents
ruby scripts/paper_bridge_qa_harness.rb workflow onboarding
```

Rails tests exercise fake AI responses through both processing jobs, completion
broadcasts, malformed output, retry safety, legacy preservation, access gates,
and the narrow schema updater. Browser tests use deterministic metadata
completion rather than live AI. They deliver the captured model-generated
Turbo messages in the browser because the test Cable adapter is process-local;
this checks in-place rendering, not cross-process Cable transport.
They cover selection controls, upload routes,
errors, edit-field unlocking, original-file buttons, and onboarding recovery.
