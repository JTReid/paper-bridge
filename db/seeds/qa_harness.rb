# frozen_string_literal: true

require "base64"
require "date"
require "stringio"

unless Rails.env.development? || Rails.env.test?
  raise "QA harness seed data is only allowed in development or test."
end

module QaHarnessSeed
  module_function

  PASSWORD = "password"
  ACCOUNT_NAME = "PaperBridge QA Harness"
  ADMIN_EMAIL = "qa-family-admin@example.test"

  PNG_BYTES = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
  )

  EVENT_TYPES = (
    ([ "recommendation" ] * 10) +
    ([ "birth" ] * 3) +
    ([ "assessment_score" ] * 4) +
    ([ "therapy" ] * 3) +
    ([ "iep" ] * 3) +
    ([ "service" ] * 4) +
    ([ "concern_observed" ] * 4) +
    ([ "accommodation" ] * 3) +
    ([ "observation" ] * 1) +
    ([ "evaluation" ] * 7) +
    ([ "diagnosis" ] * 6) +
    ([ "developmental_milestone" ] * 6)
  ).freeze

  DOCUMENTS = [
    {
      title: "QA Medical Intake Summary",
      description: "Synthetic medical intake used by the QA harness.",
      category: "medical",
      page_count: 2,
      labels: %w[medical education therapy behavior education],
      timeline_counts: [ 5, 1, 3, 2, 0 ],
      completed_log_entries: 11,
      signals: [ "care coordination", "specialist referral", "school follow-up" ]
    },
    {
      title: "QA Speech Therapy Progress Note",
      description: "Synthetic therapy progress note with retry history.",
      category: "medical",
      page_count: 2,
      labels: %w[medical education therapy education behavior therapy],
      timeline_counts: [ 6, 1, 9, 0, 2, 0 ],
      failed_retry: true,
      completed_log_entries: 11,
      signals: [ "communication goal", "home practice", "provider observation" ]
    },
    {
      title: "QA School IEP Plan",
      description: "Synthetic educational plan with accommodations and services.",
      category: "educational",
      page_count: 8,
      labels: %w[
        education education education education education education education therapy
        behavior general behavior therapy education behavior behavior education
        education education education education education therapy education therapy
        education behavior legal education general behavior legal
      ],
      timeline_counts: [
        4, 0, 1, 0, 0, 0, 1, 0,
        0, 0, 0, 0, 0, 0, 1, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 1, 0, 0, 0
      ],
      completed_log_entries: 17,
      signals: [ "IEP services", "classroom supports", "progress monitoring" ]
    },
    {
      title: "QA Developmental Evaluation",
      description: "Synthetic developmental evaluation for search and timeline coverage.",
      category: "medical",
      page_count: 7,
      labels: %w[
        general general education medical general medical education behavior medical medical
        medical medical medical medical medical behavior therapy education therapy therapy
        therapy education general
      ],
      timeline_counts: [
        3, 0, 6, 0, 0, 0, 0, 0, 1, 1,
        0, 0, 0, 0, 2, 0, 3, 1, 0, 0,
        0, 0, 0
      ],
      completed_log_entries: 16,
      signals: [ "developmental history", "evaluation scores", "therapy recommendation" ]
    }
  ].freeze

  EDGE_CASE_DOCUMENTS = [
    {
      title: "QA Edge Uploaded Only",
      description: "Attached file exists, but processing has not started.",
      category: "general",
      status: "uploaded",
      preparation_status: "unprepared"
    },
    {
      title: "QA Edge Queued Document",
      description: "Document is waiting for the ingestion worker.",
      category: "medical",
      status: "queued",
      preparation_status: "unprepared",
      pipeline_state: "pending"
    },
    {
      title: "QA Edge Processing Document",
      description: "Document is mid-ingestion with a processing page.",
      category: "therapy",
      status: "processing",
      preparation_status: "preparing",
      page_count: 1,
      page_status: "processing",
      pipeline_state: "processing"
    },
    {
      title: "QA Edge Preparation Failed",
      description: "PDF preparation failed before chunks or embeddings were created.",
      category: "medical",
      status: "failed",
      preparation_status: "failed",
      preparation_error: "Synthetic QA preparation failure.",
      pipeline_state: "failed",
      summary_error: "Synthetic QA preparation failure."
    },
    {
      title: "QA Edge Missing Embeddings",
      description: "Processed document has pages and chunks but no embeddings.",
      category: "educational",
      status: "processed",
      preparation_status: "prepared",
      page_count: 2,
      chunk_labels: %w[education behavior],
      embedding_count: 0
    },
    {
      title: "QA Edge Partial Embeddings",
      description: "Processed document has more chunks than embeddings.",
      category: "therapy",
      status: "processed",
      preparation_status: "prepared",
      page_count: 2,
      chunk_labels: %w[therapy behavior medical],
      embedding_count: 1
    },
    {
      title: "QA Edge No Summary",
      description: "Processed document has searchable content but no summary yet.",
      category: "general",
      status: "processed",
      preparation_status: "prepared",
      page_count: 1,
      chunk_labels: %w[general],
      embedding_count: 1,
      summary: :none
    }
  ].freeze

  def run
    with_local_active_storage do
      without_document_processing_callback do
        account = Account.find_or_create_by!(name: ACCOUNT_NAME)
        reset_account!(account)
        ensure_active_subscription!(account)

        admin = upsert_user!(ADMIN_EMAIL, "QA Family Admin")
        upsert_membership!(account, admin, :admin)

        dependent = account.dependents.create!(
          name: "Avery Morgan",
          date_of_birth: Date.new(2017, 4, 12),
          grade: "3",
          school: "QA Elementary",
          notes: "Synthetic dependent profile for repeatable QA harness runs."
        )

        create_care_team!(account, dependent, admin)
        processed_documents = seed_documents!(account, dependent, admin)
        edge_documents = seed_edge_case_documents!(account, dependent, admin)
        create_share_history!(account, admin, processed_documents, edge_documents)

        puts "QA harness seed loaded for #{ACCOUNT_NAME}."
        puts "Sign in as #{ADMIN_EMAIL} / #{PASSWORD}."
      end
    end
  end

  def with_local_active_storage
    service_name = Rails.env.test? ? :test : :local
    previous_service = ActiveStorage::Blob.service
    ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch(service_name)
    yield
  ensure
    ActiveStorage::Blob.service = previous_service
  end

  def without_document_processing_callback
    Document.skip_callback(:commit, :after, :enqueue_processing_pipeline)
    yield
  ensure
    Document.set_callback(:commit, :after, :enqueue_processing_pipeline, on: :create, if: :file_attached?)
  end

  def reset_account!(account)
    account.share_events.destroy_all
    account.documents.find_each(&:destroy)
    account.care_team_memberships.destroy_all
    account.dependents.destroy_all
  end

  def ensure_active_subscription!(account)
    subscription = account.billing_subscription || account.build_billing_subscription
    subscription.update!(
      status: :active,
      stripe_customer_id: "cus_qa_harness",
      stripe_subscription_id: "sub_qa_harness",
      stripe_price_id: "price_qa_harness"
    )
  end

  def upsert_user!(email, name)
    user = User.find_or_initialize_by(email: email)
    user.name = name
    user.password = PASSWORD
    user.password_confirmation = PASSWORD
    user.save!
    user
  end

  def upsert_membership!(account, user, role)
    membership = AccountMembership.find_or_initialize_by(account: account, user: user)
    membership.role = role
    membership.save!
    membership
  end

  def create_care_team!(account, dependent, admin)
    [
      {
        email: "qa-teacher@example.test",
        name: "QA Classroom Teacher",
        role: "teacher",
        status: "active",
        accepted_at: 2.days.ago,
        permissions: {
          "educational" => true,
          "general" => true,
          "medical" => false,
          "therapy" => false,
          "insurance" => false
        }
      },
      {
        email: "qa-therapist@example.test",
        name: "QA Speech Therapist",
        role: "therapist",
        status: "invited",
        permissions: {
          "therapy" => true,
          "medical" => true,
          "general" => true,
          "educational" => false,
          "insurance" => false
        }
      }
    ].each do |member|
      user = upsert_user!(member.fetch(:email), member.fetch(:name))

      account.care_team_memberships.create!(
        dependent: dependent,
        user: user,
        invited_by: admin,
        name: member.fetch(:name),
        email: member.fetch(:email),
        role: member.fetch(:role),
        status: member.fetch(:status),
        invited_at: 3.days.ago,
        accepted_at: member[:accepted_at],
        permissions: member.fetch(:permissions)
      )
    end
  end

  def seed_documents!(account, dependent, admin)
    event_cursor = 0
    processed_documents = []

    DOCUMENTS.each_with_index do |spec, document_index|
      document = create_document!(account, dependent, admin, spec, document_index)
      processed_documents << document
      pages = create_pages!(account, document, spec)
      chunks = create_chunks!(account, document, pages, spec)

      chunks.each_with_index do |chunk, chunk_index|
        create_embedding!(chunk, document_index, chunk_index)
        event_cursor = create_timeline_events!(
          chunk,
          count: spec.fetch(:timeline_counts).fetch(chunk_index),
          start_cursor: event_cursor
        )
      end

      finalize_document!(document, pages, chunks, spec)
      create_pipeline_runs!(document, admin, spec)
    end

    unless event_cursor == EVENT_TYPES.size
      raise "Expected #{EVENT_TYPES.size} timeline events, created #{event_cursor}."
    end

    processed_documents
  end

  def seed_edge_case_documents!(account, dependent, admin)
    EDGE_CASE_DOCUMENTS.each_with_index.map do |spec, index|
      document = create_edge_document!(account, dependent, admin, spec, index)
      pages = create_edge_pages!(account, document, spec)
      chunks = create_edge_chunks!(account, document, pages, spec)

      chunks.first(spec.fetch(:embedding_count, chunks.size)).each_with_index do |chunk, chunk_index|
        create_embedding!(chunk, index + 100, chunk_index)
      end

      finalize_edge_document!(document, pages, chunks, spec)
      create_edge_pipeline_run!(document, admin, spec)
      document
    end
  end

  def create_document!(account, dependent, admin, spec, document_index)
    filename = "#{spec.fetch(:title).parameterize}-#{document_index + 1}.pdf"
    account.documents.create!(
      dependent: dependent,
      user: admin,
      title: spec.fetch(:title),
      description: spec.fetch(:description),
      category: spec.fetch(:category),
      file: {
        io: StringIO.new(synthetic_pdf_body(spec)),
        filename: filename,
        content_type: Documents::Prepare::PDF_CONTENT_TYPE
      }
    )
  end

  def create_edge_document!(account, dependent, admin, spec, index)
    filename = "#{spec.fetch(:title).parameterize}-edge-#{index + 1}.pdf"
    account.documents.create!(
      dependent: dependent,
      user: admin,
      title: spec.fetch(:title),
      description: spec.fetch(:description),
      category: spec.fetch(:category),
      file: {
        io: StringIO.new(synthetic_edge_pdf_body(spec)),
        filename: filename,
        content_type: Documents::Prepare::PDF_CONTENT_TYPE
      }
    )
  end

  def create_pages!(account, document, spec)
    (1..spec.fetch(:page_count)).map do |page_number|
      embedded_text = page_text(spec, page_number, source: "embedded")
      ocr_text = page_text(spec, page_number, source: "ocr")
      page = document.document_pages.create!(
        account: account,
        page_number: page_number,
        embedded_text: embedded_text,
        ocr_text: ocr_text,
        metadata: {
          "dpi" => 300,
          "embedded_word_count" => word_count(embedded_text),
          "ocr_word_count" => word_count(ocr_text),
          "selected_text_source" => "combined"
        },
        status: "processed"
      )
      page.image.attach(
        io: StringIO.new(PNG_BYTES),
        filename: "#{document.title.parameterize}-page-#{page_number}.png",
        content_type: "image/png"
      )
      page
    end
  end

  def create_chunks!(account, document, pages, spec)
    labels = spec.fetch(:labels)

    labels.each_with_index.map do |label, index|
      page = pages.fetch((index * pages.size) / labels.size)
      content = chunk_content(spec, index + 1, label, page.page_number)
      normalized = DocumentChunk.normalize_content(content)

      document.document_chunks.create!(
        account: account,
        document_page: page,
        content: normalized,
        content_hash: DocumentChunk.content_hash_for(normalized),
        label: label,
        chunk_index: index + 1,
        metadata: {}
      )
    end
  end

  def create_edge_pages!(account, document, spec)
    (1..spec.fetch(:page_count, 0)).map do |page_number|
      embedded_text = page_text(edge_text_spec(spec), page_number, source: "embedded")
      ocr_text = page_text(edge_text_spec(spec), page_number, source: "ocr")
      status = spec.fetch(:page_status, "processed")
      page = document.document_pages.create!(
        account: account,
        page_number: page_number,
        embedded_text: embedded_text,
        ocr_text: ocr_text,
        metadata: {
          "dpi" => 300,
          "embedded_word_count" => word_count(embedded_text),
          "ocr_word_count" => word_count(ocr_text),
          "selected_text_source" => "combined"
        },
        status: status
      )
      page.image.attach(
        io: StringIO.new(PNG_BYTES),
        filename: "#{document.title.parameterize}-page-#{page_number}.png",
        content_type: "image/png"
      )
      page
    end
  end

  def create_edge_chunks!(account, document, pages, spec)
    spec.fetch(:chunk_labels, []).each_with_index.map do |label, index|
      page = pages.fetch((index * pages.size) / spec.fetch(:chunk_labels).size)
      content = chunk_content(edge_text_spec(spec), index + 1, label, page.page_number)
      normalized = DocumentChunk.normalize_content(content)

      document.document_chunks.create!(
        account: account,
        document_page: page,
        content: normalized,
        content_hash: DocumentChunk.content_hash_for(normalized),
        label: label,
        chunk_index: index + 1,
        metadata: { "seed_edge_case" => true }
      )
    end
  end

  def create_embedding!(chunk, document_index, chunk_index)
    axis = ((document_index * 97) + chunk_index) % DocumentEmbedding::DIMENSIONS
    vector = Array.new(DocumentEmbedding::DIMENSIONS, 0.0)
    vector[axis] = 1.0

    chunk.document_embeddings.create!(
      provider: DocumentEmbedding::PROVIDER,
      model: DocumentEmbedding::MODEL,
      dimensions: DocumentEmbedding::DIMENSIONS,
      distance_metric: DocumentEmbedding::DISTANCE_METRIC,
      embedding: vector,
      metadata: { "seed" => "qa_harness", "axis" => axis }
    )
  end

  def create_timeline_events!(chunk, count:, start_cursor:)
    count.times do |offset|
      cursor = start_cursor + offset
      event_type = EVENT_TYPES.fetch(cursor)
      occurred_on = Date.new(2024, 8, 1) + cursor.days
      title = "#{event_type.humanize} #{cursor + 1}"
      description = "Synthetic #{event_type.humanize.downcase} event extracted from #{chunk.document.title}."

      chunk.timeline_events.create!(
        event_type: event_type,
        title: title,
        description: description,
        occurred_on: occurred_on,
        started_on: nil,
        ended_on: nil,
        date_precision: "exact",
        date_source: "explicit",
        source_quote: "QA seed source quote for #{chunk.document.title} chunk #{chunk.chunk_index}.",
        content_hash: TimelineEvent.content_hash_for(
          event_type: event_type,
          title: title,
          description: description,
          occurred_on: occurred_on,
          started_on: nil,
          ended_on: nil
        ),
        metadata: { "seed" => "qa_harness" }
      )
    end

    start_cursor + count
  end

  def finalize_document!(document, pages, chunks, spec)
    full_text = pages.map do |page|
      <<~TEXT.strip
        Page #{page.page_number}
        Embedded text:
        #{page.embedded_text}

        OCR text:
        #{page.ocr_text}
      TEXT
    end.join("\n\n")

    document.update!(
      status: "processed",
      preparation_status: "prepared",
      prepared_at: 1.hour.ago,
      summarized_at: 30.minutes.ago,
      preparation_error: nil,
      prepared_payload: {
        "format" => "pdf",
        "preparation_version" => "pdf-v1",
        "page_count" => pages.size,
        "dpi" => 300,
        "full_text" => full_text,
        "pages" => pages.map { |page| page_payload(page) },
        "warnings" => []
      },
      summary: {
        "title" => spec.fetch(:title),
        "summary" => "Synthetic processed #{spec.fetch(:category)} document with #{pages.size} pages, " \
                     "#{chunks.size} chunks, deterministic embeddings, and timeline evidence.",
        "key_points" => [
          "Uses local QA seed attachments instead of private uploaded files.",
          "Covers #{chunks.map(&:label).uniq.sort.to_sentence} chunk labels.",
          "Includes #{chunks.sum { |chunk| chunk.timeline_events.size }} timeline events."
        ],
        "metadata" => {
          "seed" => "qa_harness",
          "synthetic" => true,
          "source" => "db/seeds/qa_harness.rb"
        }
      }
    )
  end

  def finalize_edge_document!(document, pages, chunks, spec)
    attributes = {
      status: spec.fetch(:status),
      preparation_status: spec.fetch(:preparation_status),
      preparation_error: spec[:preparation_error],
      prepared_at: pages.any? && spec.fetch(:preparation_status) == "prepared" ? 40.minutes.ago : nil,
      summarized_at: summarized_at_for(spec),
      prepared_payload: edge_prepared_payload(pages, spec),
      summary: edge_summary(document, pages, chunks, spec)
    }

    document.update!(attributes)
  end

  def create_pipeline_runs!(document, admin, spec)
    if spec[:failed_retry]
      create_pipeline_run!(
        document,
        admin,
        state: "failed",
        activity_entries: 2,
        log_entries: 4,
        message: "Synthetic retryable QA seed failure.",
        failed: true
      )
    end

    create_pipeline_run!(
      document,
      admin,
      state: "completed",
      activity_entries: 6,
      log_entries: spec.fetch(:completed_log_entries),
      message: "Synthetic QA seed processing completed.",
      failed: false
    )
  end

  def create_edge_pipeline_run!(document, admin, spec)
    state = spec[:pipeline_state]
    return if state.blank?

    create_pipeline_run!(
      document,
      admin,
      state: state,
      activity_entries: state == "failed" ? 2 : 1,
      log_entries: state == "failed" ? 3 : 1,
      message: "Synthetic QA edge-case pipeline is #{state}.",
      failed: state == "failed"
    )
  end

  def create_pipeline_run!(document, admin, state:, activity_entries:, log_entries:, message:, failed:)
    pipeline_run = document.pipeline_runs.create!(
      user: admin,
      state: state,
      message: message,
      context: pipeline_context(document),
      completed_at: state == "completed" ? 20.minutes.ago : nil,
      failed_at: state == "failed" ? 45.minutes.ago : nil
    )

    PipelineActivity.create!(
      pipeline_run: pipeline_run,
      entries: build_activity_entries(activity_entries, failed: failed)
    )
    PipelineLog.create!(
      pipeline_run: pipeline_run,
      entries: build_log_entries(log_entries, failed: failed)
    )
  end

  def pipeline_context(document)
    {
      "account_id" => document.account_id,
      "byte_size" => document.byte_size,
      "content_type" => document.content_type,
      "document_id" => document.id,
      "filename" => document.original_filename,
      "page_count" => document.document_pages.count,
      "preparation_status" => document.preparation_status,
      "preparation_version" => "pdf-v1"
    }
  end

  def build_activity_entries(count, failed:)
    actions = %w[
      document_preparation_started
      document_pages_prepared
      document_chunks_created
      document_summary_generated
      document_chunks_embedded
      timeline_events_extracted
    ]
    actions = [ "document_preparation_started", "document_processing_failed" ] if failed

    actions.first(count).each_with_index.map do |action, index|
      {
        "action" => action,
        "message" => action.humanize,
        "occurred_at" => (50.minutes.ago + index.minutes).to_i,
        "metadata" => { "seed" => "qa_harness" }
      }
    end
  end

  def build_log_entries(count, failed:)
    agents = %w[document_preparer document_chunker document_summarizer document_embedder timeline_event_extractor]

    count.times.map do |index|
      agent = failed && index >= 2 ? "document_preparer" : agents.fetch(index % agents.size)
      message = failed && index == count - 1 ? "Synthetic failure captured." : "Synthetic pipeline step #{index + 1}."

      {
        "agent" => agent,
        "message" => message,
        "occurred_at" => (50.minutes.ago + index.minutes).to_i,
        "payload" => { "seed" => "qa_harness", "step" => index + 1 },
        "event_type" => failed && index == count - 1 ? "error" : "info"
      }
    end
  end

  def page_payload(page)
    {
      "id" => page.id,
      "number" => page.page_number,
      "embedded_text" => page.embedded_text.to_s,
      "ocr_text" => page.ocr_text.to_s,
      "image_attached" => page.image.attached?,
      "image_blob_id" => page.image.attached? ? page.image.blob_id : nil,
      "metadata" => page.metadata
    }
  end

  def create_share_history!(account, admin, processed_documents, edge_documents)
    [
      {
        recipient_email: "qa-pending-share@example.test",
        subject: "Pending QA share",
        message: "Synthetic pending share event.",
        status: "pending",
        documents: [ edge_documents.first ]
      },
      {
        recipient_email: "qa-sent-share@example.test",
        subject: "Sent QA share",
        message: "Synthetic sent share event.",
        status: "sent",
        sent_at: 15.minutes.ago,
        documents: processed_documents.first(2)
      },
      {
        recipient_email: "qa-failed-share@example.test",
        subject: "Failed QA share",
        message: "Synthetic failed share event.",
        status: "failed",
        error_message: "Synthetic SMTP failure.",
        documents: [ processed_documents.first ]
      }
    ].each do |share|
      share_event = account.share_events.create!(
        sender: admin,
        recipient_email: share.fetch(:recipient_email),
        subject: share.fetch(:subject),
        message: share.fetch(:message),
        status: share.fetch(:status),
        sent_at: share[:sent_at],
        error_message: share[:error_message]
      )
      share.fetch(:documents).compact.each { |document| share_event.documents << document }
    end
  end

  def synthetic_pdf_body(spec)
    <<~PDF
      %PDF-1.4
      % Synthetic PaperBridge QA harness document
      Title: #{spec.fetch(:title)}
      Category: #{spec.fetch(:category)}
      Signals: #{spec.fetch(:signals).join(", ")}
      %%EOF
    PDF
  end

  def synthetic_edge_pdf_body(spec)
    <<~PDF
      %PDF-1.4
      % Synthetic PaperBridge QA edge-case document
      Title: #{spec.fetch(:title)}
      Status: #{spec.fetch(:status)}
      Preparation: #{spec.fetch(:preparation_status)}
      %%EOF
    PDF
  end

  def edge_text_spec(spec)
    spec.merge(
      category: spec.fetch(:category),
      signals: [ spec.fetch(:status), spec.fetch(:preparation_status), "edge-case rendering" ]
    )
  end

  def edge_prepared_payload(pages, spec)
    return {} if pages.empty? || spec.fetch(:preparation_status) != "prepared"

    {
      "format" => "pdf",
      "preparation_version" => "pdf-v1",
      "page_count" => pages.size,
      "dpi" => 300,
      "full_text" => pages.map(&:embedded_text).join("\n\n"),
      "pages" => pages.map { |page| page_payload(page) },
      "warnings" => []
    }
  end

  def edge_summary(document, pages, chunks, spec)
    return {} if spec[:summary] == :none

    if spec[:summary_error].present?
      return {
        "error" => {
          "message" => spec.fetch(:summary_error),
          "source" => "qa_harness_seed"
        }
      }
    end

    return {} unless spec.fetch(:status) == "processed"

    {
      "title" => document.title,
      "summary" => "Synthetic edge-case document with #{pages.size} pages, #{chunks.size} chunks, " \
                   "and #{document.document_embeddings.count} embeddings.",
      "key_points" => [
        "Status: #{spec.fetch(:status)}.",
        "Preparation status: #{spec.fetch(:preparation_status)}.",
        "Seeded to exercise partial and empty-state rendering."
      ],
      "metadata" => {
        "seed" => "qa_harness",
        "edge_case" => true
      }
    }
  end

  def summarized_at_for(spec)
    return nil if spec[:summary] == :none
    return nil unless spec.fetch(:status) == "processed"

    25.minutes.ago
  end

  def page_text(spec, page_number, source:)
    [
      "#{source.capitalize} QA text for #{spec.fetch(:title)} page #{page_number}.",
      "This page contains synthetic #{spec.fetch(:category)} material for PaperBridge browser and pipeline QA.",
      "Signals covered on this page include #{spec.fetch(:signals).to_sentence}.",
      "The content is deterministic and safe for screenshots, email attachments, search, and timeline views."
    ].join(" ")
  end

  def chunk_content(spec, chunk_index, label, page_number)
    [
      "QA synthetic #{label} chunk #{chunk_index} for #{spec.fetch(:title)}.",
      "It starts on page #{page_number} and represents processed text generated by the harness seed.",
      "The scenario covers #{spec.fetch(:signals).to_sentence} while avoiding private uploaded document content.",
      "Use this chunk to exercise document detail rendering, access filters, vector search records, and timeline evidence."
    ].join("\n")
  end

  def word_count(text)
    text.to_s.scan(/\S+/).count
  end
end

QaHarnessSeed.run
