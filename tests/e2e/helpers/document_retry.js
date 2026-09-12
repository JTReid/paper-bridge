// @ts-check
import { execFileSync } from 'node:child_process';

export function createDocumentRetryScenario() {
  return run(`
    user = User.find_by!(email: "admin@example.test")
    profile = user.account.dependents.create!(first_name: "DocumentRetry", last_name: "QA-#{SecureRandom.hex(6)}")
    document = profile.documents.new(account: user.account, user: user, title: "Family edited title", category: :therapy, description: "Family edited description")
    document.file.attach(io: StringIO.new("Original evidence for deterministic document retry QA."), filename: "retry-original.txt", content_type: "text/plain")
    document.save!
    document.update!(status: :failed, preparation_status: :prepared, prepared_payload: { text: "Obsolete prepared text", preparation_version: "text-v1" }, summary: { summary: "Summary from the earlier attempt.", key_points: [ "Earlier summary key point." ] }, summarized_at: Time.current, preparation_error: "Synthetic failed attempt")
    page = document.document_pages.create!(account: user.account, page_number: 1, status: :processed, embedded_text: "Obsolete page text")
    chunk = page.document_chunks.create!(account: user.account, document: document, content: "Obsolete retry chunk.", content_hash: DocumentChunk.content_hash_for("Obsolete retry chunk."), label: "therapy", chunk_index: 0)
    chunk.document_embeddings.create!(provider: DocumentEmbedding::PROVIDER, model: DocumentEmbedding::MODEL, dimensions: DocumentEmbedding::DIMENSIONS, distance_metric: DocumentEmbedding::DISTANCE_METRIC, embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001))
    chunk.timeline_events.create!(event_type: "observation", title: "Old extracted event", description: "Old retry evidence", occurred_on: "2026-01-02", date_precision: "exact", date_source: "explicit", source_quote: chunk.content, content_hash: "old-retry-event")
    history = document.pipeline_runs.create!(user: user, state: :failed, context: { document_id: document.id })
    saved = profile.saved_answers.create!(account: user.account, user: user, question: "What should we discuss?", generated_at: Time.current, answer: { answer: "Keep this saved answer during processing.", citations: [ { document_id: document.id, document_title: document.title, page_number: 1, source_number: 1 } ], limitations: [] })
    meeting = profile.meeting_preps.create!(account: user.account, user: user, name: "Retry preservation meeting")
    entry = meeting.add_answer!(saved)
    share = user.account.share_events.create!(sender: user, recipient_email: "retry-qa@example.test", status: :sent, sent_at: Time.current)
    share.shared_documents.create!(document: document)
    puts JSON.generate(profileId: profile.id, documentId: document.id, savedAnswerId: saved.id, meetingId: meeting.id, entryId: entry.id, historyId: history.id)
  `);
}

export function documentRetryState(profileId) {
  return run(`
    ${profileLookup}
    ${stateReader}
    puts JSON.generate(retry_state(document))
  `, { QA_RETRY_PROFILE_ID: String(profileId) });
}

export function finishDocumentRetry(profileId) {
  return run(`
    ${profileLookup}
    ${stateReader}
    ${fakeConnection}
    checkpoints = {}
    RetryQaConnection.on_request = ->(name) do
      if name.in?(%w[document_summary embeddings])
        checkpoints[name] = { state: retry_state(document.reload), broadcast_count: ActionCable.server.pubsub.broadcasts(document.to_gid_param).size }
      end
    end
    ProcessDocumentJob.llm_connection = RetryQaConnection
    ProcessDocumentJob.perform_now(document)
    document.reload
    raise "Synthetic retry did not complete" unless document.processed?
    broadcasts = ActionCable.server.pubsub.broadcasts(document.to_gid_param).map { |message| JSON.parse(message) }
    before_summary = checkpoints.fetch("document_summary")
    after_summary = checkpoints.fetch("embeddings")
    puts JSON.generate(
      state: retry_state(document), requests: RetryQaConnection.requests,
      beforeSummary: { state: before_summary.fetch(:state), broadcasts: broadcasts.take(before_summary.fetch(:broadcast_count)) },
      afterSummary: { state: after_summary.fetch(:state), broadcasts: broadcasts[before_summary.fetch(:broadcast_count)...after_summary.fetch(:broadcast_count)] },
      broadcasts: broadcasts.drop(after_summary.fetch(:broadcast_count))
    )
  `, { QA_RETRY_PROFILE_ID: String(profileId) });
}

export function deleteDocumentRetryScenario(profileId) {
  run(`
    ${profileLookup}
    document.share_events.each(&:destroy!)
    document.destroy!
    profile.destroy!
    puts "null"
  `, { QA_RETRY_PROFILE_ID: String(profileId) });
}

const profileLookup = `
  profile = User.find_by!(email: "admin@example.test").account.dependents.find(ENV.fetch("QA_RETRY_PROFILE_ID"))
  raise "Not a document retry QA profile" unless profile.first_name == "DocumentRetry" && profile.last_name.start_with?("QA-")
  document = profile.documents.sole
`;

const stateReader = `
  def retry_state(document)
    profile = document.dependent
    access = Documents::SearchAccessProfile.for(document.user, account: document.account, dependent: profile)
    searchable = Documents::VectorSearch.new(account: document.account, dependent: profile, access_profile: access, query_embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001)).call
    {
      status: document.status,
      preserved: { id: document.id, blobId: document.file.blob.id, original: document.file.download, title: document.title, category: document.category, description: document.description,
        savedAnswers: profile.saved_answers.order(:id).map { |answer| [ answer.id, answer.answer ] },
        meetingEntries: MeetingPrepAnswer.joins(:meeting_prep).where(meeting_preps: { dependent_id: profile.id }).order(:id).pluck(:id, :saved_answer_id),
        shares: document.share_events.order(:id).pluck(:id, :status) },
      pageIds: document.document_pages.pluck(:id), chunkIds: document.document_chunks.pluck(:id), embeddingIds: document.document_embeddings.pluck(:id), timelineIds: document.timeline_events.pluck(:id),
      summary: document.summary, summarizedAt: document.summarized_at, searchableIds: searchable.map { |result| result.document.id },
      runs: document.pipeline_runs.order(:id).pluck(:id, :state)
    }
  end
`;

// The real worker, preparation and agents execute; every provider request is
// answered locally. Any unexpected endpoint/schema fails instead of using HTTP.
const fakeConnection = `
  class RetryQaConnection
    class << self
      attr_accessor :requests, :on_request
    end
    self.requests = []

    class Request
      def self.execute(**options)
        payload = JSON.parse(options.fetch(:payload))
        if options.fetch(:url).end_with?("/embeddings")
          RetryQaConnection.requests << "embeddings"
          RetryQaConnection.on_request.call("embeddings")
          return { data: Array(payload.fetch("input")).each_with_index.map { |_text, index| { index: index, embedding: Array.new(DocumentEmbedding::DIMENSIONS, 0.001) } }, model: payload.fetch("model"), usage: { prompt_tokens: 1, total_tokens: 1 } }.to_json
        end
        raise "Unexpected retry QA endpoint" unless options.fetch(:url).end_with?("/chat/completions")
        schema = payload.dig("response_format", "json_schema", "name")
        RetryQaConnection.requests << schema
        RetryQaConnection.on_request.call(schema)
        result = case schema
        when "document_chunks"
          { chunks: [ { content: "Fresh retry evidence.", label: "therapy" } ] }
        when "document_summary"
          { title: "Generated title", summary: "Fresh summary after retry.", key_points: [ "Rebuilt from the saved original." ], category: "medical", description: "Generated replacement description" }
        when "timeline_events"
          text = payload.dig("messages", 1, "content").to_s
          chunk_id = text[/document_chunk_id:\\s*(\\d+)/, 1].to_i
          { events: [ { document_chunk_id: chunk_id, event_type: "observation", title: "Fresh extracted event", description: "Fresh retry evidence.", occurred_on: "2026-01-03", started_on: "", ended_on: "", date_precision: "exact", date_source: "explicit", source_quote: "Fresh retry evidence." } ] }
        else
          raise "Unexpected retry QA schema: #{schema.inspect}"
        end
        { choices: [ { message: { content: result.to_json } } ], usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } }.to_json
      end
    end
  end
`;

function run(code, env = {}) {
  const output = execFileSync('bin/rails', ['runner', code], {
    cwd: process.cwd(), env: { ...process.env, ...env, RAILS_ENV: 'test' }, stdio: 'pipe', encoding: 'utf8',
  });
  return JSON.parse(output.trim().split('\n').at(-1));
}
