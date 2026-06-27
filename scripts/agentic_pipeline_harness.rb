#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__).join("..").realpath

AGENTIC_CORE_FILES = %w[
  app/models/agent_type.rb
  app/models/json_schema.rb
  app/models/llm.rb
  app/models/pipeline_activity.rb
  app/models/pipeline_log.rb
  app/models/pipeline_run.rb
  app/models/prompt.rb
  app/services/agentic/errors.rb
  app/services/agentic/example_pipeline.rb
  app/services/agentic/instrumented.rb
  app/services/agentic/llm_call_pricing.rb
  app/services/agentic/null_progress_tracker.rb
  app/services/agentic/pipeline.rb
  app/services/agentic/pipeline_context.rb
  app/services/agentic/pipeline_instrumentation.rb
  app/services/agentic/progress_tracker.rb
  app/services/agentic/providers.rb
  app/services/agentic/providers/anthropic.rb
  app/services/agentic/providers/llm_call_telemetry.rb
  app/services/agentic/providers/openai.rb
  app/services/agentic/telemetry/elapsed_time_summary.rb
  app/services/agentic/telemetry/log_entries.rb
  app/services/agentic/telemetry/pricing_summary.rb
  app/services/agentic/telemetry/summary.rb
  app/services/agents.rb
  app/services/agents/structured_text_summarizer.rb
  app/services/agents/structured_text_validator.rb
  app/services/concerns/locally_interactable.rb
  app/services/concerns/pipeline_notifiable.rb
  db/migrate/20260614023700_create_agentic_pipeline.rb
  docs/agentic-pipeline-runbook.md
  docs/runbooks/agentic-pipeline.md
  test/services/agentic/pipeline_test.rb
  test/services/agentic/providers/anthropic_test.rb
  test/services/agentic/providers/openai_test.rb
  test/services/agentic/telemetry/summary_test.rb
].freeze

DOCUMENT_PIPELINE_FILES = %w[
  app/controllers/ai_assistant_controller.rb
  app/jobs/process_document_job.rb
  app/models/document.rb
  app/models/document_chunk.rb
  app/models/document_embedding.rb
  app/models/document_page.rb
  app/models/timeline_event.rb
  config/database.yml
  config/environments/development.rb
  app/services/agentic/document_ingestion_pipeline.rb
  app/services/agentic/document_search_pipeline.rb
  app/services/agents/document_chunker.rb
  app/services/agents/document_embedder.rb
  app/services/agents/document_summarizer.rb
  app/services/agents/query_embedder.rb
  app/services/agents/search_answer_generator.rb
  app/services/agents/timeline_event_extractor.rb
  app/services/agents/vector_retriever.rb
  app/services/documents/pdf_command_runner.rb
  app/services/documents/prepare.rb
  app/services/documents/prepare_pdf.rb
  app/services/documents/prepare_text.rb
  app/services/documents/search_access_profile.rb
  app/services/documents/vector_search.rb
  docs/runbooks/document-ingestion.md
  docs/runbooks/ai-assistant-search.md
  db/migrate/20260614033907_add_summary_to_documents.rb
  db/migrate/20260614040236_create_document_pages.rb
  db/migrate/20260614040243_add_preparation_to_documents.rb
  db/migrate/20260614230725_enable_pgvector.rb
  db/migrate/20260614230726_create_document_chunks.rb
  db/migrate/20260614230727_create_document_embeddings.rb
  db/migrate/20260615020405_create_timeline_events.rb
  test/controllers/documents_controller_test.rb
  test/controllers/ai_assistant_controller_test.rb
  test/jobs/process_document_job_test.rb
  test/models/document_chunk_test.rb
  test/models/document_embedding_test.rb
  test/models/document_page_test.rb
  test/models/document_test.rb
  test/models/timeline_event_test.rb
  test/services/documents/prepare_pdf_test.rb
  test/services/documents/prepare_text_test.rb
  test/services/documents/search_access_profile_test.rb
  test/services/documents/vector_search_test.rb
].freeze

PROVIDER_FILES = %w[
  app/services/agentic/providers/openai.rb
  app/services/agentic/providers/anthropic.rb
].freeze
PROVIDER_INSTANCE_METHODS = %w[call parse_response].freeze

DOCTOR_RUNNER = <<~"RUBY"
  Rails.application.load_seed
  errors = []
  provider_classes = Llm.distinct.pluck(:provider_class).compact_blank.sort
  provider_classes.each do |provider_class|
    begin
      klass = provider_class.constantize
      errors << "\#{provider_class} does not implement .default_operation_type" unless klass.respond_to?(:default_operation_type)
    rescue NameError => e
      errors << "\#{provider_class} could not be constantized: \#{e.message}"
    end
  end
  AgentType.includes(:llm, :prompts).find_each do |agent_type|
    errors << "AgentType \#{agent_type.name} has no llm" if agent_type.llm.blank?
    errors << "AgentType \#{agent_type.name} has no active prompt" if agent_type.prompts.active.empty?
  end
  required_agent_types = %w[structured_text_summarizer structured_text_validator document_chunker document_summarizer document_embedder query_embedder search_answer_generator timeline_event_extractor]
  missing_agent_types = required_agent_types - AgentType.pluck(:name)
  errors.concat(missing_agent_types.map { |name| "Required AgentType \#{name} is missing" })
  errors << "openai_document_summary JsonSchema is missing" unless JsonSchema.exists?(name: "openai_document_summary")
  errors << "openai_document_chunks JsonSchema is missing" unless JsonSchema.exists?(name: "openai_document_chunks")
  errors << "openai_search_answer JsonSchema is missing" unless JsonSchema.exists?(name: "openai_search_answer")
  errors << "openai_timeline_events JsonSchema is missing" unless JsonSchema.exists?(name: "openai_timeline_events")
  puts "Agentic provider classes in test DB: \#{provider_classes.any? ? provider_classes.join(", ") : "none"}"
  puts "OpenAI credential present: \#{Agentic::Providers::Openai.api_key_present?}"
  puts "Anthropic credential present: \#{Agentic::Providers::Anthropic.api_key_present?}"
  abort("Agentic pipeline doctor failed:\\n- \#{errors.join("\\n- ")}") if errors.any?
  puts "Agentic pipeline doctor passed."
RUBY

LIVE_RUNNER = <<~"RUBY"
  provider_name = ENV.fetch("AGENTIC_LIVE_PROVIDER", "").downcase
  model = ENV.fetch("AGENTIC_LIVE_MODEL", "gpt-5.4-nano")
  abort("Set AGENTIC_LIVE_PROVIDER to openai or anthropic.") if provider_name.blank?
  provider_class, key_name, schema = case provider_name
  when "openai"
    [
      Agentic::Providers::Openai,
      "OPENAI_API_KEY",
      {
        response_format: {
          type: "json_schema",
          json_schema: {
            name: "agentic_harness_smoke",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              properties: { status: { type: "string", enum: ["OK"] } },
              required: ["status"]
            }
          }
        }
      }
    ]
  when "anthropic"
    [
      Agentic::Providers::Anthropic,
      "ANTHROPIC_API_KEY",
      {
        tools: [
          {
            name: "agentic_harness_smoke",
            description: "Return provider smoke status.",
            input_schema: {
              type: "object",
              additionalProperties: false,
              properties: { status: { type: "string", enum: ["OK"] } },
              required: ["status"]
            }
          }
        ],
        tool_choice: { type: "tool", name: "agentic_harness_smoke" }
      }
    ]
  else
    abort("Unsupported AGENTIC_LIVE_PROVIDER=\#{provider_name.inspect}. Use openai or anthropic.")
  end
  abort("\#{key_name} or Rails credentials are required for live agentic provider smoke.") unless provider_class.api_key_present?
  provider = provider_class.new(
    connection: RestClient,
    operation_type: provider_class.default_operation_type,
    requirements: {
      model: model,
      system: "You are a PaperBridge agentic pipeline harness check.",
      prompt: "Return status OK.",
      max_tokens: 32,
      response_format: "structured_json",
      schema: schema
    }
  )
  raw_response = provider.call
  parsed = JSON.parse(provider.parse_response(raw_response))
  abort("Live provider smoke failed: expected status OK, got \#{parsed.inspect}.") unless parsed["status"] == "OK"
  puts "Agentic live provider smoke passed for \#{provider_name}:\#{model}."
RUBY

PDF_TOOLS_RUNNER = <<~"RUBY"
  required = %w[pdfinfo pdftotext pdftoppm tesseract]
  missing = required.reject do |executable|
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      File.executable?(File.join(directory, executable))
    end
  end
  abort("Missing PDF preparation tools: \#{missing.join(", ")}") if missing.any?
  puts "PDF preparation tools present: \#{required.join(", ")}"
RUBY

QUEUE_RUNNER = <<~"RUBY"
  errors = []
  errors << "Development Active Job adapter is not Solid Queue" unless ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
  errors << "Solid Queue is not configured to use the queue database" unless SolidQueue.connects_to == { database: { writing: :queue } }
  errors << "solid_queue_jobs table is missing" unless SolidQueue::Job.table_exists?
  errors << "solid_queue_ready_executions table is missing" unless SolidQueue::ReadyExecution.table_exists?

  class HarnessSolidQueueSmokeJob < ApplicationJob
    def perform; end
  end

  job = HarnessSolidQueueSmokeJob.perform_later
  record = SolidQueue::Job.find_by(active_job_id: job.job_id)
  errors << "Solid Queue did not persist the smoke job" unless record
  errors << "Solid Queue did not mark the smoke job ready" if record && SolidQueue::ReadyExecution.where(job_id: record.id).empty?

  if record
    SolidQueue::ReadyExecution.where(job_id: record.id).delete_all
    record.destroy!
  end

  abort("Solid Queue harness failed:\\n- \#{errors.join("\\n- ")}") if errors.any?
  puts "Solid Queue development enqueue smoke passed."
RUBY

COMMANDS = {
  "docs" => [
    [ "ruby", "scripts/check_docs_index.rb" ]
  ],
  "assets" => [
    [ "bin/rails", "tailwindcss:build" ]
  ],
  "doctor" => [
    [ "bin/rails", "runner", "-e", "test", DOCTOR_RUNNER ]
  ],
  "tests" => [
    [
      "bin/rails", "test",
      "test/services/agentic/pipeline_test.rb",
      "test/services/agentic/providers/openai_test.rb",
      "test/services/agentic/providers/anthropic_test.rb",
      "test/services/agentic/telemetry/summary_test.rb",
      "test/models/user_test.rb"
    ]
  ],
  "documents" => [
    [ "bin/rails", "tailwindcss:build" ],
    [
      "bin/rails", "test",
      "test/models/document_test.rb",
      "test/models/document_page_test.rb",
      "test/models/document_chunk_test.rb",
      "test/models/document_embedding_test.rb",
      "test/models/timeline_event_test.rb",
      "test/controllers/documents_controller_test.rb",
      "test/controllers/ai_assistant_controller_test.rb",
      "test/jobs/process_document_job_test.rb",
      "test/services/documents/prepare_text_test.rb",
      "test/services/documents/prepare_pdf_test.rb",
      "test/services/documents/search_access_profile_test.rb",
      "test/services/documents/vector_search_test.rb"
    ]
  ],
  "pdf-tools" => [
    [ "bin/rails", "runner", PDF_TOOLS_RUNNER ]
  ],
  "queue" => [
    [ "bin/rails", "runner", QUEUE_RUNNER ]
  ],
  "rubocop" => [
    [
      "bin/rubocop",
      "--cache", "false",
      "app/controllers/ai_assistant_controller.rb",
      "app/controllers/documents_controller.rb",
      "app/jobs",
      "app/models/agent_type.rb",
      "app/models/document.rb",
      "app/models/document_chunk.rb",
      "app/models/document_embedding.rb",
      "app/models/json_schema.rb",
      "app/models/llm.rb",
      "app/models/pipeline_activity.rb",
      "app/models/pipeline_log.rb",
      "app/models/pipeline_run.rb",
      "app/models/prompt.rb",
      "app/models/timeline_event.rb",
      "app/models/user.rb",
      "app/services/agentic",
      "app/services/agents",
      "app/services/concerns",
      "app/services/documents",
      "test/controllers/ai_assistant_controller_test.rb",
      "test/controllers/documents_controller_test.rb",
      "test/jobs",
      "test/services/agentic",
      "test/services/documents",
      "test/models/document_test.rb",
      "test/models/document_page_test.rb",
      "test/models/document_chunk_test.rb",
      "test/models/document_embedding_test.rb",
      "test/models/timeline_event_test.rb",
      "test/models/user_test.rb",
      "scripts/check_docs_index.rb",
      "scripts/agentic_pipeline_harness.rb"
    ]
  ],
  "live" => [
    [ "bin/rails", "runner", LIVE_RUNNER ]
  ]
}.freeze

def usage
  puts(<<~USAGE)
    Usage: ruby scripts/agentic_pipeline_harness.rb COMMAND

    Commands:
      docs      Check agent-facing docs are indexed
      assets    Build generated Tailwind CSS for Rails view tests
      static    Check generic agentic pipeline file shape and provider interface
      doctor    Seed/check local test DB provider records and API key visibility
      tests     Run deterministic generic pipeline Minitest coverage
      documents Run deterministic document upload, ingestion, timeline, and search lifecycle coverage
      pdf-tools Check local Poppler/Tesseract binaries for live PDF preparation
      queue     Check development Solid Queue adapter/tables/enqueue path
      rubocop   Run RuboCop on generic pipeline files and this harness
      live      Run an explicit live provider smoke using AGENTIC_LIVE_* env vars
      review    Run docs, static, doctor, tests, documents, and rubocop
  USAGE
end

def run_command(command)
  puts("\n--- #{command.join(" ")} ---")
  system(*command, chdir: ROOT.to_s)
end

def pipeline_candidate_files
  files = Dir.glob(ROOT.join("app/services/agentic/**/*pipeline*.rb")).map { |path| Pathname.new(path) }
  example = ROOT.join("app/services/agentic/example_pipeline.rb")
  files << example if example.file?
  files.uniq
end

def pipeline_subclass_files
  pipeline_candidate_files.select do |path|
    path.read.match?(/<\s*(?:Agentic::)?Pipeline\b/)
  end
end

def static_check_passed?
  failures = []

  missing_files = AGENTIC_CORE_FILES.reject { |relative_path| ROOT.join(relative_path).file? }
  failures.concat(missing_files.map { |path| "Missing expected Agentic Pipeline file: #{path}" })

  missing_document_files = DOCUMENT_PIPELINE_FILES.reject { |relative_path| ROOT.join(relative_path).file? }
  failures.concat(missing_document_files.map { |path| "Missing expected Document Pipeline file: #{path}" })

  tracked_agentic_files = IO.popen(
    [ "git", "-C", ROOT.to_s, "ls-files", "app/services/agentic", "app/services/agents" ],
    &:read
  ).split("\n")
  tracked_dot_store_files = tracked_agentic_files.grep(%r{(^|/)\.DS_Store\z})
  failures.concat(tracked_dot_store_files.map { |path| "Remove tracked Finder metadata file: #{path}" })

  pipeline_subclasses = pipeline_subclass_files
  failures << "No Agentic::Pipeline subclasses were found." if pipeline_subclasses.empty?

  pipeline_subclasses.each do |path|
    source = path.read
    failures << "#{path.relative_path_from(ROOT)} must implement #to_response" unless source.match?(/def\s+to_response\b/)
  end

  PROVIDER_FILES.each do |relative_path|
    path = ROOT.join(relative_path)
    next unless path.file?

    source = path.read
    PROVIDER_INSTANCE_METHODS.each do |method_name|
      failures << "#{relative_path} must implement ##{method_name}" unless source.match?(/def\s+#{method_name}\b/)
    end
    failures << "#{relative_path} must implement .default_operation_type" unless source.match?(/def\s+self\.default_operation_type\b/)
    failures << "#{relative_path} must support runtime schema requirements" unless source.include?("requirements[:schema]")
  end

  if failures.any?
    warn("Agentic Pipeline static check failed:\n#{failures.map { |failure| "- #{failure}" }.join("\n")}")
    return false
  end

  puts "Expected Agentic Pipeline files exist."
  puts "Expected Document Pipeline files exist."
  puts "Pipeline subclasses checked: #{pipeline_subclasses.map { |path| path.relative_path_from(ROOT) }.join(", ")}"
  puts "Provider files checked: #{PROVIDER_FILES.join(", ")}"
  true
end

command = ARGV.fetch(0, nil)

case command
when nil, "-h", "--help", "help"
  usage
when "static"
  exit(static_check_passed? ? 0 : 1)
when "review"
  ok = COMMANDS.fetch("docs").all? { |cmd| run_command(cmd) }
  ok &&= static_check_passed?
  ok &&= COMMANDS.fetch("doctor").all? { |cmd| run_command(cmd) }
  ok &&= COMMANDS.fetch("tests").all? { |cmd| run_command(cmd) }
  ok &&= COMMANDS.fetch("documents").all? { |cmd| run_command(cmd) }
  ok &&= COMMANDS.fetch("rubocop").all? { |cmd| run_command(cmd) }
  exit(ok ? 0 : 1)
when *COMMANDS.keys
  ok = COMMANDS.fetch(command).all? { |cmd| run_command(cmd) }
  exit(ok ? 0 : 1)
else
  warn("Unknown command: #{command}")
  usage
  exit(1)
end
