#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "cgi"
require "json"
require "net/http"
require "open3"
require "pathname"
require "shellwords"
require "time"
require "timeout"
require "uri"

ROOT = Pathname.new(__dir__).join("..").realpath
QA_PORT = ENV.fetch("QA_PORT", "3100")
QA_HOST = ENV.fetch("QA_HOST", "127.0.0.1")
QA_BASE_URL = ENV.fetch("QA_BASE_URL", "http://#{QA_HOST}:#{QA_PORT}")
MAILPIT_SMTP_ADDRESS = ENV.fetch("MAILPIT_SMTP_ADDRESS", "127.0.0.1")
MAILPIT_SMTP_PORT = ENV.fetch("MAILPIT_SMTP_PORT", "1025")
MAILPIT_API_URL = ENV.fetch("QA_MAILPIT_API_URL", "http://127.0.0.1:8025")
ARTIFACT_ROOT = ROOT.join("tmp/qa-artifacts")
SERVER_LOG = ARTIFACT_ROOT.join("logs/rails-test-server.log")
BUGHUNT_EVIDENCE_SCHEMA = "paper_bridge.bughunt_evidence.v1"
BUGHUNT_EVIDENCE_FILES = {
  manifest: "manifest.json",
  summary: "summary.md",
  index: "index.html"
}.freeze

DoctorCheck = Struct.new(:label, :command, :env, :required, :hint, keyword_init: true)

WORKFLOW_SPECS = {
  "billing" => [ "tests/e2e/product/billing.spec.js" ].freeze,
  "sharing" => [ "tests/e2e/product/document_sharing.spec.js" ].freeze,
  "documents" => [ "tests/e2e/product/document_management.spec.js" ].freeze,
  "care-team" => [ "tests/e2e/product/care_team.spec.js" ].freeze,
  "ai" => [ "tests/e2e/product/ai_assistant.spec.js" ].freeze
}.freeze
WORKFLOW_ALL_PATHS = WORKFLOW_SPECS.values.flatten.freeze
WORKFLOW_MODES = [ *WORKFLOW_SPECS.keys, "all" ].freeze

NEGATIVE_SPECS = {
  "documents" => [ "tests/e2e/product/document_negative.spec.js" ].freeze,
  "care-team" => [ "tests/e2e/product/care_team_negative.spec.js" ].freeze,
  "mobile" => [ "tests/e2e/product/mobile_negative.spec.js" ].freeze,
  "edge-states" => [ "tests/e2e/product/qa_seed_edge_states.spec.js" ].freeze
}.freeze
NEGATIVE_ALL_PATHS = NEGATIVE_SPECS.values.flatten.freeze
NEGATIVE_MODES = [ *NEGATIVE_SPECS.keys, "all" ].freeze

ACCESSIBILITY_SPECS = {
  "surfaces" => [ "tests/e2e/product/accessibility_suite.spec.js" ].freeze
}.freeze
ACCESSIBILITY_ALL_PATHS = ACCESSIBILITY_SPECS.values.flatten.freeze
ACCESSIBILITY_MODES = [ *ACCESSIBILITY_SPECS.keys, "all" ].freeze

MOBILE_SPECS = {
  "surfaces" => [ "tests/e2e/product/mobile_suite.spec.js" ].freeze,
  "negative" => [ "tests/e2e/product/mobile_negative.spec.js" ].freeze
}.freeze
MOBILE_ALL_PATHS = MOBILE_SPECS.values.flatten.freeze
MOBILE_MODES = [ *MOBILE_SPECS.keys, "all" ].freeze

QA_DATA_RUNNER = <<~"RUBY"
  document = Document.find_by!(title: "Advance Directive")
  unless document.file.attached?
    document.file.attach(
      io: Rails.root.join("test/fixtures/files/sample.txt").open,
      filename: document.original_filename.presence || "advance-directive.txt",
      content_type: document.content_type.presence || "text/plain"
    )
    document.save!
  end
RUBY

QA_DB_CLEANUP_RUNNER = <<~"RUBY"
  PipelineActivity.delete_all
  PipelineLog.delete_all
  PipelineRun.delete_all
  Account.find_by(name: "PaperBridge QA Harness")&.destroy
  ActiveStorage::VariantRecord.delete_all
  ActiveStorage::Attachment.delete_all
  ActiveStorage::Blob.delete_all
RUBY

STATIC_FILES = %w[
  docs/runbooks/qa-troubleshooting.md
  docs/runbooks/browser-qa.md
  docs/runbooks/qa-seed-data.md
  db/seeds/qa_harness.rb
  scripts/paper_bridge_qa_harness.rb
  app/javascript/controllers/document_search_controller.js
  playwright.config.js
  package.json
  package-lock.json
  tests/e2e/helpers/auth.js
  tests/e2e/helpers/backend.js
  tests/e2e/helpers/diagnostics.js
  tests/e2e/helpers/accessibility.js
  tests/e2e/helpers/mailpit.js
  tests/e2e/fixtures.js
  tests/e2e/smoke/public_home.spec.js
  tests/e2e/smoke/auth.spec.js
  tests/e2e/smoke/product_shape.spec.js
  tests/e2e/product/dependent_workspace.spec.js
  tests/e2e/product/document_sharing.spec.js
  tests/e2e/product/document_sharing_mailpit.spec.js
  tests/e2e/product/billing.spec.js
  tests/e2e/product/document_management.spec.js
  tests/e2e/product/document_negative.spec.js
  tests/e2e/product/care_team.spec.js
  tests/e2e/product/care_team_negative.spec.js
  tests/e2e/product/accessibility_suite.spec.js
  tests/e2e/product/mobile_suite.spec.js
  tests/e2e/product/mobile_negative.spec.js
  tests/e2e/product/qa_seed_edge_states.spec.js
  tests/e2e/product/ai_assistant.spec.js
  tests/e2e/regressions/README.md
].freeze

def usage
  puts(<<~USAGE)
    Usage: ruby scripts/paper_bridge_qa_harness.rb COMMAND

    Commands:
      doctor   Check local QA prerequisites
      static   Check QA harness files exist
      seed     Load deterministic development QA seed data
      db       Prepare test DB, load fixtures, and apply QA data setup
      assets   Build generated Tailwind CSS
      server   Prepare QA env and run a Rails test server in the foreground
      smoke    Run fast Chromium browser smoke checks
      browser  Run all Chromium browser QA checks
      workflow Run named Chromium workflow scenarios
      negative Run named Chromium negative/error-state probes
      accessibility Run named Chromium accessibility suites
      mobile   Run named Chromium mobile viewport suites
      mailpit  Run email QA checks through local Mailpit SMTP and API
      bughunt  Run browser checks with named screenshots, videos, and traces always on
      rubocop  Run RuboCop on the QA harness Ruby script
      review   Run docs, static, doctor, development harness checks, and browser smoke

    Examples:
      ruby scripts/paper_bridge_qa_harness.rb workflow documents
      ruby scripts/paper_bridge_qa_harness.rb workflow all
      ruby scripts/paper_bridge_qa_harness.rb negative documents
      ruby scripts/paper_bridge_qa_harness.rb negative care-team
      ruby scripts/paper_bridge_qa_harness.rb negative edge-states
      ruby scripts/paper_bridge_qa_harness.rb negative all
      ruby scripts/paper_bridge_qa_harness.rb accessibility surfaces
      ruby scripts/paper_bridge_qa_harness.rb accessibility all
      ruby scripts/paper_bridge_qa_harness.rb mobile surfaces
      ruby scripts/paper_bridge_qa_harness.rb mobile negative
      ruby scripts/paper_bridge_qa_harness.rb mobile all
      ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal
      ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal tests/e2e/product/document_sharing.spec.js
      ruby scripts/paper_bridge_qa_harness.rb bughunt tests/e2e/product/document_sharing.spec.js
      ruby scripts/paper_bridge_qa_harness.rb mailpit
      ruby scripts/paper_bridge_qa_harness.rb mailpit tests/e2e/product/document_sharing_mailpit.spec.js
  USAGE
end

def workflow_usage
  puts(<<~USAGE)
    Usage: ruby scripts/paper_bridge_qa_harness.rb workflow MODE
    Available modes: #{WORKFLOW_MODES.join(", ")}

    Modes:
      billing    Run billing access and subscription state workflow checks
      sharing    Run document sharing workflow checks without Mailpit
      documents  Run document upload and metadata workflow checks
      care-team  Run care team invitation and permissions workflow checks
      ai         Run AI assistant page workflow checks without live model calls
      all        Run all workflow modes above
  USAGE
end

def accessibility_usage
  puts(<<~USAGE)
    Usage: ruby scripts/paper_bridge_qa_harness.rb accessibility MODE
    Available modes: #{ACCESSIBILITY_MODES.join(", ")}

    Modes:
      surfaces Run axe checks over public, auth, billing, workspace, documents,
               sharing, care team, AI, and seeded edge-state surfaces
      all      Run all accessibility modes above

    These modes use deterministic Chromium Playwright specs through the QA test
    server. They do not start Mailpit, require SMTP capture, or call live services.
  USAGE
end

def mobile_usage
  puts(<<~USAGE)
    Usage: ruby scripts/paper_bridge_qa_harness.rb mobile MODE
    Available modes: #{MOBILE_MODES.join(", ")}

    Modes:
      surfaces Run successful mobile navigation through public, billing,
               workspace, documents, sharing, care team, and AI surfaces
      negative Run narrow viewport negative workflow probes
      all      Run all mobile modes above

    These modes use deterministic Chromium Playwright specs through the QA test
    server. They do not start Mailpit, require SMTP capture, or call live services.
  USAGE
end

def negative_usage
  puts(<<~USAGE)
    Usage: ruby scripts/paper_bridge_qa_harness.rb negative MODE
    Available modes: #{NEGATIVE_MODES.join(", ")}

    Modes:
      documents   Run document form validation probes
      care-team   Run invalid care team invite probes
      mobile      Run narrow viewport negative workflow probes
      edge-states Run seeded empty, failed, and partial document state probes
      all         Run all negative/error-state modes above

    These modes use deterministic Chromium Playwright specs through the QA test
    server. They do not start Mailpit, require SMTP capture, or call live services.
  USAGE
end

def run_command(command, env: {})
  puts("\n--- #{[ env_summary(env), command.join(" ") ].compact.join(" ")} ---")
  system(env, *command, chdir: ROOT.to_s)
end

def run_command_logged(command, env: {}, log_path:)
  header = "--- #{[ env_summary(env), command.join(" ") ].compact.join(" ")} ---"
  puts("\n#{header}")

  FileUtils.mkdir_p(log_path.dirname)
  File.open(log_path, "a") do |log|
    log.puts("\n#{header}")
    Open3.popen2e(env, *command, chdir: ROOT.to_s) do |_stdin, output, wait_thread|
      output.each do |line|
        print(line)
        log.write(line)
      end

      wait_thread.value.success?
    end
  end
rescue Errno::ENOENT => error
  warn("Command failed: #{error.message}")
  false
end

def capture_command(command, env: {})
  output, status = Open3.capture2e(env, *command, chdir: ROOT.to_s)
  [ status.success?, output.to_s.strip ]
rescue Errno::ENOENT
  [ false, "command not found: #{command.first}" ]
end

def capture_optional(command, env: {})
  passed, output = capture_command(command, env: env)
  passed ? output : nil
end

def qa_environment_valid?
  errors = []
  begin
    uri = URI(QA_BASE_URL)
    errors << "QA_BASE_URL must be http or https" unless %w[http https].include?(uri.scheme)
    errors << "QA_BASE_URL must include a host" if uri.host.to_s.empty?
  rescue URI::InvalidURIError => error
    errors << "QA_BASE_URL is invalid: #{error.message}"
  end

  errors << "QA_HOST is blank" if QA_HOST.to_s.strip.empty?
  errors << "QA_PORT must be numeric" unless QA_PORT.match?(/\A\d+\z/)
  errors << "QA_WORKERS must be numeric" if ENV["QA_WORKERS"] && !ENV["QA_WORKERS"].match?(/\A\d+\z/)

  if errors.empty?
    puts "PASS QA environment variables"
    true
  else
    warn("FAIL QA environment variables\n#{errors.map { |error| "     #{error}" }.join("\n")}")
    false
  end
end

def env_summary(env)
  return nil if env.empty?

  env.map { |key, value| "#{key}=#{value}" }.join(" ")
end

def ensure_artifact_dirs
  FileUtils.mkdir_p(ARTIFACT_ROOT.join("logs"))
  FileUtils.mkdir_p(ARTIFACT_ROOT.join("screenshots"))
  FileUtils.mkdir_p(ARTIFACT_ROOT.join("traces"))
  FileUtils.mkdir_p(ARTIFACT_ROOT.join("videos"))
end

def prepare_database
  run_command([ "bin/rails", "db:prepare" ], env: { "RAILS_ENV" => "test" }) &&
    run_command([ "bin/rails", "runner", QA_DB_CLEANUP_RUNNER ], env: { "RAILS_ENV" => "test" }) &&
    run_command([ "bin/rails", "db:fixtures:load" ], env: { "RAILS_ENV" => "test" }) &&
    run_command([ "bin/rails", "db:seed" ], env: { "RAILS_ENV" => "test", "PAPER_BRIDGE_SEED_QA" => "1" }) &&
    run_command([ "bin/rails", "runner", QA_DATA_RUNNER ], env: { "RAILS_ENV" => "test" })
end

def build_assets
  run_command([ "bin/rails", "tailwindcss:build" ])
end

def seed_development
  run_command([ "bin/rails", "db:prepare" ], env: { "RAILS_ENV" => "development" }) &&
    run_command([ "bin/rails", "db:seed" ], env: { "RAILS_ENV" => "development", "PAPER_BRIDGE_SEED_QA" => "1" })
end

def app_responding?
  response = Net::HTTP.get_response(URI("#{QA_BASE_URL}/up"))
  response.is_a?(Net::HTTPSuccess)
rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, SocketError, Net::OpenTimeout, Net::ReadTimeout
  false
end

def mailpit_responding?
  response = Net::HTTP.get_response(URI("#{MAILPIT_API_URL}/api/v1/info"))
  response.is_a?(Net::HTTPSuccess)
rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, SocketError, Net::OpenTimeout, Net::ReadTimeout
  false
end

def ensure_mailpit_ready
  return true if mailpit_responding?

  warn(
    [
      "Mailpit is not responding at #{MAILPIT_API_URL}.",
      "Start it with:",
      "  mailpit --smtp #{MAILPIT_SMTP_ADDRESS}:#{MAILPIT_SMTP_PORT} --listen #{URI(MAILPIT_API_URL).host}:#{URI(MAILPIT_API_URL).port}"
    ].join("\n")
  )
  false
end

def wait_for_server(timeout_seconds: 30)
  Timeout.timeout(timeout_seconds) do
    sleep 0.25 until app_responding?
  end
  true
rescue Timeout::Error
  warn("Rails test server did not respond at #{QA_BASE_URL}. See #{SERVER_LOG.relative_path_from(ROOT)}")
  false
end

def start_server(env: {})
  return nil if app_responding?

  ensure_artifact_dirs
  log = File.open(SERVER_LOG, "a")
  log.puts("\n--- starting Rails test server at #{Time.now.utc.iso8601} ---")
  log.flush

  spawn(
    { "RAILS_ENV" => "test", "PORT" => QA_PORT }.merge(env),
    "bin/rails", "server", "-p", QA_PORT, "-b", QA_HOST,
    chdir: ROOT.to_s,
    out: log,
    err: log,
    pgroup: true
  ).tap do |pid|
    unless wait_for_server
      stop_server(pid)
      return false
    end
  end
end

def stop_server(pid)
  return if pid.nil? || pid == false

  Process.kill("TERM", -pid)
  Timeout.timeout(10) { Process.wait(pid) }
rescue Errno::ESRCH, Errno::ECHILD
  nil
rescue Timeout::Error
  Process.kill("KILL", -pid)
  Process.wait(pid)
end

def with_server(env: {})
  return false unless prepare_database && build_assets

  pid = start_server(env: env)
  return false if pid == false

  begin
    yield
  ensure
    stop_server(pid)
    run_command([ "bin/rails", "runner", QA_DB_CLEANUP_RUNNER ], env: { "RAILS_ENV" => "test" })
  end
end

def run_playwright(paths: [], always_record: false, artifact_dir: nil, env: {}, command_log: nil)
  ensure_artifact_dirs
  command = [ "npx", "playwright", "test", *paths, "--project=chromium" ]
  playwright_env = {
    "QA_BASE_URL" => QA_BASE_URL
  }.merge(env)
  playwright_env["QA_ARTIFACT_MODE"] = "always" if always_record
  playwright_env["QA_ARTIFACT_DIR"] = artifact_dir.relative_path_from(ROOT).to_s if artifact_dir

  result = if command_log
    run_command_logged(command, env: playwright_env, log_path: command_log)
  else
    run_command(command, env: playwright_env)
  end

  if artifact_dir
    puts "\nQA artifacts written under #{artifact_dir.relative_path_from(ROOT)}"
    puts "HTML report: #{artifact_dir.join("playwright-report/index.html").relative_path_from(ROOT)}"
  end

  result
end

def workflow_paths(workflow_name)
  return WORKFLOW_ALL_PATHS if workflow_name == "all"

  WORKFLOW_SPECS[workflow_name]
end

def negative_paths(negative_name)
  return NEGATIVE_ALL_PATHS if negative_name == "all"

  NEGATIVE_SPECS[negative_name]
end

def accessibility_paths(accessibility_name)
  return ACCESSIBILITY_ALL_PATHS if accessibility_name == "all"

  ACCESSIBILITY_SPECS[accessibility_name]
end

def mobile_paths(mobile_name)
  return MOBILE_ALL_PATHS if mobile_name == "all"

  MOBILE_SPECS[mobile_name]
end

def run_workflow(workflow_name)
  if workflow_name.to_s.empty?
    warn("Missing workflow mode.")
    workflow_usage
    return false
  end

  paths = workflow_paths(workflow_name)
  unless paths
    warn("Unknown workflow mode: #{workflow_name}")
    workflow_usage
    return false
  end

  with_server { run_playwright(paths: paths) }
end

def run_negative(negative_name)
  if negative_name.to_s.empty?
    warn("Missing negative mode.")
    negative_usage
    return false
  end

  paths = negative_paths(negative_name)
  unless paths
    warn("Unknown negative mode: #{negative_name}")
    negative_usage
    return false
  end

  with_server { run_playwright(paths: paths) }
end

def run_accessibility(accessibility_name)
  if accessibility_name.to_s.empty?
    warn("Missing accessibility mode.")
    accessibility_usage
    return false
  end

  paths = accessibility_paths(accessibility_name)
  unless paths
    warn("Unknown accessibility mode: #{accessibility_name}")
    accessibility_usage
    return false
  end

  with_server { run_playwright(paths: paths) }
end

def run_mobile(mobile_name)
  if mobile_name.to_s.empty?
    warn("Missing mobile mode.")
    mobile_usage
    return false
  end

  paths = mobile_paths(mobile_name)
  unless paths
    warn("Unknown mobile mode: #{mobile_name}")
    mobile_usage
    return false
  end

  with_server { run_playwright(paths: paths) }
end

def accessibility_command(args)
  if args.length > 1
    warn("Unexpected accessibility arguments: #{args.drop(1).join(", ")}")
    accessibility_usage
    return false
  end

  run_accessibility(args.first)
end

def mobile_command(args)
  if args.length > 1
    warn("Unexpected mobile arguments: #{args.drop(1).join(", ")}")
    mobile_usage
    return false
  end

  run_mobile(args.first)
end

def bughunt_case_dir(raw_bug_id)
  bug_id = raw_bug_id.to_s.strip
  bug_id = Time.now.utc.strftime("bug-%Y%m%d-%H%M%S") if bug_id.empty?
  safe_bug_id = bug_id.downcase.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A-+|-+\z/, "")
  safe_bug_id = Time.now.utc.strftime("bug-%Y%m%d-%H%M%S") if safe_bug_id.empty?
  ARTIFACT_ROOT.join("bugs", safe_bug_id)
end

def bughunt_run_dir(case_dir, started_at)
  base_name = started_at.strftime("run-%Y%m%dT%H%M%SZ")
  candidate = case_dir.join("runs", base_name)
  suffix = 2

  while candidate.exist?
    candidate = case_dir.join("runs", "#{base_name}-#{suffix}")
    suffix += 1
  end

  candidate
end

def bughunt_relative(path)
  path.relative_path_from(ROOT).to_s
end

def bughunt_command_args(requested_bug_id, paths)
  args = [ "ruby", "scripts/paper_bridge_qa_harness.rb", "bughunt" ]
  args << requested_bug_id if requested_bug_id.to_s.strip != ""
  args.concat(paths)
end

def bughunt_git_metadata
  {
    "branch" => capture_optional([ "git", "rev-parse", "--abbrev-ref", "HEAD" ]),
    "commit" => capture_optional([ "git", "rev-parse", "HEAD" ]),
    "dirty" => !capture_optional([ "git", "status", "--short" ]).to_s.empty?
  }
end

def bughunt_versions
  {
    "ruby" => capture_optional([ "ruby", "--version" ]),
    "node" => capture_optional([ "node", "--version" ]),
    "playwright" => capture_optional([ "npx", "playwright", "--version" ])
  }
end

def bughunt_artifact_counts(run_dir)
  results_dir = run_dir.join("test-results")

  {
    "screenshots" => Dir.glob(results_dir.join("**/*.png").to_s).count,
    "videos" => Dir.glob(results_dir.join("**/*.webm").to_s).count,
    "traces" => Dir.glob(results_dir.join("**/*trace*.zip").to_s).count
  }
end

def copy_bughunt_server_log(run_dir)
  return nil unless SERVER_LOG.file?

  destination = run_dir.join("rails-test-server.log")
  FileUtils.cp(SERVER_LOG, destination)
  destination
rescue Errno::ENOENT
  nil
end

def bughunt_manifest(case_dir:, run_dir:, requested_bug_id:, paths:, started_at:, finished_at:, passed:, server_log_path:)
  effective_paths = paths.empty? ? [ "<all Playwright specs>" ] : paths
  command_args = bughunt_command_args(requested_bug_id, paths)

  {
    "schema" => BUGHUNT_EVIDENCE_SCHEMA,
    "bug_id" => case_dir.basename.to_s,
    "requested_bug_id" => requested_bug_id.to_s.empty? ? nil : requested_bug_id,
    "run_id" => run_dir.basename.to_s,
    "status" => passed ? "passed" : "failed",
    "started_at" => started_at.iso8601,
    "finished_at" => finished_at.iso8601,
    "duration_seconds" => (finished_at - started_at).round(2),
    "command" => Shellwords.join(command_args),
    "paths" => effective_paths,
    "qa" => {
      "base_url" => QA_BASE_URL,
      "workers" => ENV.fetch("QA_WORKERS", "1"),
      "project" => "chromium",
      "artifact_mode" => "always"
    },
    "artifacts" => {
      "case_directory" => bughunt_relative(case_dir),
      "run_directory" => bughunt_relative(run_dir),
      "case_index" => bughunt_relative(case_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:index))),
      "manifest" => bughunt_relative(run_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:manifest))),
      "summary" => bughunt_relative(run_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:summary))),
      "command_log" => bughunt_relative(run_dir.join("command.log")),
      "playwright_report" => bughunt_relative(run_dir.join("playwright-report/index.html")),
      "test_results" => bughunt_relative(run_dir.join("test-results")),
      "rails_server_log" => server_log_path ? bughunt_relative(server_log_path) : nil
    },
    "artifact_counts" => bughunt_artifact_counts(run_dir),
    "git" => bughunt_git_metadata,
    "versions" => bughunt_versions
  }
end

def bughunt_summary_markdown(manifest)
  paths = manifest.fetch("paths").map { |path| "- `#{path}`" }.join("\n")
  artifacts = manifest.fetch("artifacts")

  <<~MARKDOWN
    # Bughunt Evidence: #{manifest.fetch("bug_id")} / #{manifest.fetch("run_id")}

    Status: **#{manifest.fetch("status")}**

    ## Run

    - Command: `#{manifest.fetch("command")}`
    - QA base URL: `#{manifest.dig("qa", "base_url")}`
    - QA workers: `#{manifest.dig("qa", "workers")}`
    - Started: `#{manifest.fetch("started_at")}`
    - Finished: `#{manifest.fetch("finished_at")}`
    - Duration: `#{manifest.fetch("duration_seconds")}s`
    - Git branch: `#{manifest.dig("git", "branch") || "unknown"}`
    - Git commit: `#{manifest.dig("git", "commit") || "unknown"}`
    - Git dirty: `#{manifest.dig("git", "dirty")}`

    ## Specs

    #{paths}

    ## Artifacts

    - Case index: `#{artifacts.fetch("case_index")}`
    - Playwright report: `#{artifacts.fetch("playwright_report")}`
    - Test results: `#{artifacts.fetch("test_results")}`
    - Command log: `#{artifacts.fetch("command_log")}`
    - Rails server log: `#{artifacts.fetch("rails_server_log") || "not copied"}`
    - Machine manifest: `#{artifacts.fetch("manifest")}`

    ## Artifact Counts

    - Screenshots: `#{manifest.dig("artifact_counts", "screenshots")}`
    - Videos: `#{manifest.dig("artifact_counts", "videos")}`
    - Traces: `#{manifest.dig("artifact_counts", "traces")}`

    ## Loop

    Use this run directory as the evidence packet for the named bug. Re-run the
    same bughunt command before and after a fix when the issue needs visual proof.
    Move durable assertions into `workflow`, `negative`, `mailpit`, or a
    regression spec after the behavior is understood.
  MARKDOWN
end

def bughunt_case_index_html(case_dir)
  manifests = Dir.glob(case_dir.join("runs/*/#{BUGHUNT_EVIDENCE_FILES.fetch(:manifest)}").to_s)
    .filter_map do |path|
      JSON.parse(File.read(path))
    rescue JSON::ParserError
      nil
    end
    .sort_by { |manifest| manifest.fetch("started_at", "") }
    .reverse

  rows = manifests.map do |manifest|
    artifacts = manifest.fetch("artifacts")
    <<~HTML
      <tr>
        <td>#{CGI.escapeHTML(manifest.fetch("started_at", ""))}</td>
        <td>#{CGI.escapeHTML(manifest.fetch("status", ""))}</td>
        <td><a href="#{CGI.escapeHTML(ROOT.join(artifacts.fetch("summary")).relative_path_from(case_dir).to_s)}">#{CGI.escapeHTML(manifest.fetch("run_id", ""))}</a></td>
        <td><a href="#{CGI.escapeHTML(ROOT.join(artifacts.fetch("playwright_report")).relative_path_from(case_dir).to_s)}">report</a></td>
        <td><code>#{CGI.escapeHTML(manifest.fetch("command", ""))}</code></td>
      </tr>
    HTML
  end.join("\n")

  <<~HTML
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <title>PaperBridge Bughunt #{CGI.escapeHTML(case_dir.basename.to_s)}</title>
        <style>
          body { font-family: sans-serif; margin: 2rem; line-height: 1.45; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border-bottom: 1px solid #ddd; padding: 0.5rem; text-align: left; vertical-align: top; }
          code { white-space: pre-wrap; }
        </style>
      </head>
      <body>
        <h1>PaperBridge Bughunt: #{CGI.escapeHTML(case_dir.basename.to_s)}</h1>
        <p>Newest runs are listed first.</p>
        <table>
          <thead>
            <tr>
              <th>Started</th>
              <th>Status</th>
              <th>Summary</th>
              <th>Report</th>
              <th>Command</th>
            </tr>
          </thead>
          <tbody>
            #{rows}
          </tbody>
        </table>
      </body>
    </html>
  HTML
end

def write_bughunt_evidence(case_dir, run_dir, manifest)
  File.write(run_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:manifest)), "#{JSON.pretty_generate(manifest)}\n")
  File.write(run_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:summary)), bughunt_summary_markdown(manifest))
  File.write(case_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:index)), bughunt_case_index_html(case_dir))
end

def run_bughunt(requested_bug_id, paths)
  case_dir = bughunt_case_dir(requested_bug_id)
  started_at = Time.now.utc
  run_dir = bughunt_run_dir(case_dir, started_at)
  FileUtils.mkdir_p(run_dir)

  command_log = run_dir.join("command.log")
  passed = with_server do
    run_playwright(paths: paths, always_record: true, artifact_dir: run_dir, command_log: command_log)
  end
  finished_at = Time.now.utc
  copied_server_log = copy_bughunt_server_log(run_dir)
  manifest = bughunt_manifest(
    case_dir: case_dir,
    run_dir: run_dir,
    requested_bug_id: requested_bug_id,
    paths: paths,
    started_at: started_at,
    finished_at: finished_at,
    passed: passed,
    server_log_path: copied_server_log
  )
  write_bughunt_evidence(case_dir, run_dir, manifest)

  puts "\nBughunt case index: #{bughunt_relative(case_dir.join(BUGHUNT_EVIDENCE_FILES.fetch(:index)))}"
  puts "Bughunt run summary: #{manifest.dig("artifacts", "summary")}"
  puts "Bughunt manifest: #{manifest.dig("artifacts", "manifest")}"

  passed
end

def mailpit_server_env
  {
    "QA_MAILPIT" => "true",
    "MAILPIT_SMTP_ADDRESS" => MAILPIT_SMTP_ADDRESS,
    "MAILPIT_SMTP_PORT" => MAILPIT_SMTP_PORT
  }
end

def mailpit_playwright_env
  {
    "QA_MAILPIT_API_URL" => MAILPIT_API_URL
  }
end

def doctor_passed?
  checks = [
    DoctorCheck.new(
      label: "Ruby runtime",
      command: [ "ruby", "--version" ],
      required: true
    ),
    DoctorCheck.new(
      label: "Bundler",
      command: [ "bundle", "--version" ],
      required: true
    ),
    DoctorCheck.new(
      label: "Rails boots in test",
      command: [ "bin/rails", "runner", "puts 'rails-test-ok'" ],
      env: { "RAILS_ENV" => "test" },
      required: true
    ),
    DoctorCheck.new(
      label: "Test database connection",
      command: [ "bin/rails", "runner", "ActiveRecord::Base.connection.execute('SELECT 1'); puts 'test-db-ok'" ],
      env: { "RAILS_ENV" => "test" },
      required: true,
      hint: "Run RAILS_ENV=test bin/rails db:prepare."
    ),
    DoctorCheck.new(
      label: "pgvector extension enabled in test database",
      command: [
        "bin/rails",
        "runner",
        "enabled = ActiveRecord::Base.connection.select_value(\"SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'vector')\"); abort('vector extension is not enabled') unless enabled; puts 'pgvector-ok'"
      ],
      env: { "RAILS_ENV" => "test" },
      required: true,
      hint: "Install pgvector for this PostgreSQL version and run RAILS_ENV=test bin/rails db:prepare."
    ),
    DoctorCheck.new(
      label: "Node runtime",
      command: [ "node", "--version" ],
      required: true
    ),
    DoctorCheck.new(
      label: "npm",
      command: [ "npm", "--version" ],
      required: true
    ),
    DoctorCheck.new(
      label: "Playwright package",
      command: [ "npx", "playwright", "--version" ],
      required: true,
      hint: "Run npm install."
    ),
    DoctorCheck.new(
      label: "axe-core Playwright package",
      command: [ "npm", "ls", "@axe-core/playwright", "--depth=0" ],
      required: true,
      hint: "Run npm install."
    ),
    DoctorCheck.new(
      label: "Chromium browser launches",
      command: [
        "node",
        "-e",
        "const { chromium } = require('@playwright/test'); (async () => { const browser = await chromium.launch(); await browser.close(); console.log('chromium-ok'); })().catch((error) => { console.error(error.message); process.exit(1); });"
      ],
      required: true,
      hint: "Run npx playwright install chromium."
    ),
    DoctorCheck.new(
      label: "QA harness file inventory",
      command: [ "ruby", "scripts/paper_bridge_qa_harness.rb", "static" ],
      required: true
    ),
    DoctorCheck.new(
      label: "Mailpit API reachable",
      command: [
        "ruby",
        "-rnet/http",
        "-ruri",
        "-e",
        "begin; response = Net::HTTP.get_response(URI(ENV.fetch('QA_MAILPIT_API_URL'))); abort('Mailpit returned HTTP ' + response.code) unless response.is_a?(Net::HTTPSuccess); puts 'mailpit-ok'; rescue => error; abort(error.message); end"
      ],
      env: { "QA_MAILPIT_API_URL" => MAILPIT_API_URL },
      required: false,
      hint: "Only required for mailpit mode. Start with: mailpit --smtp #{MAILPIT_SMTP_ADDRESS}:#{MAILPIT_SMTP_PORT} --listen #{URI(MAILPIT_API_URL).host}:#{URI(MAILPIT_API_URL).port}"
    ),
    DoctorCheck.new(
      label: "Stripe CLI available",
      command: [ "stripe", "--version" ],
      required: false,
      hint: "Only required for future live Stripe webhook/Checkout QA."
    ),
    DoctorCheck.new(
      label: "Stripe Checkout config present",
      command: [ "bin/rails", "runner", "abort('stripe checkout is not configured') unless Billing::StripeConfig.checkout_ready?; puts 'stripe-checkout-config-ok'" ],
      env: { "RAILS_ENV" => "test" },
      required: false,
      hint: "Only required for live Stripe Checkout QA. Configure stripe.secret_key and stripe.standard_price, or STRIPE_SECRET_KEY and STRIPE_PRICE_ID."
    )
  ]

  passes = 0
  failures = 0
  warnings = 0

  puts "PaperBridge QA Environment Doctor"
  puts "QA base URL: #{QA_BASE_URL}"
  puts "QA artifacts: #{ARTIFACT_ROOT.relative_path_from(ROOT)}"

  if qa_environment_valid?
    passes += 1
  else
    failures += 1
  end

  checks.each do |check|
    passed, output = capture_command(check.command, env: check.env || {})
    status = if passed
      passes += 1
      "PASS"
    elsif check.required
      failures += 1
      "FAIL"
    else
      warnings += 1
      "WARN"
    end

    puts "#{status} #{check.label}"
    puts "     #{output.lines.first}" unless output.empty?
    puts "     #{check.hint}" if !passed && check.hint && !check.hint.empty?
  end

  if app_responding?
    warnings += 1
    puts "WARN Rails QA server already responding at #{QA_BASE_URL}"
    puts "     Existing server will be reused by browser commands; stop it if that is not intentional."
  else
    passes += 1
    puts "PASS Rails QA server is not already running at #{QA_BASE_URL}"
  end

  puts "\nDoctor summary: #{passes} passed, #{warnings} warnings, #{failures} failures."
  failures.zero?
end

def static_check_passed?
  failures = STATIC_FILES.reject { |relative_path| ROOT.join(relative_path).file? }

  if failures.any?
    warn("PaperBridge QA static check failed:\n#{failures.map { |path| "- Missing #{path}" }.join("\n")}")
    return false
  end

  puts "Expected QA harness files exist."
  puts "QA base URL: #{QA_BASE_URL}"
  puts "QA artifacts: #{ARTIFACT_ROOT.relative_path_from(ROOT)}"
  true
end

def run_server_foreground
  return false unless prepare_database && build_assets

  puts "Starting Rails test server at #{QA_BASE_URL}"
  exec(
    { "RAILS_ENV" => "test", "PORT" => QA_PORT },
    "bin/rails", "server", "-p", QA_PORT, "-b", QA_HOST,
    chdir: ROOT.to_s
  )
end

command = ARGV.fetch(0, nil)
args = ARGV.drop(1)

ok = case command
when nil, "-h", "--help", "help"
  usage
  true
when "doctor"
  doctor_passed?
when "static"
  static_check_passed?
when "seed"
  seed_development
when "db"
  prepare_database
when "assets"
  build_assets
when "server"
  run_server_foreground
when "smoke"
  with_server { run_playwright(paths: [ "tests/e2e/smoke" ]) }
when "browser"
  with_server { run_playwright }
when "workflow"
  run_workflow(args.first)
when "negative"
  run_negative(args.first)
when "accessibility"
  accessibility_command(args)
when "mobile"
  mobile_command(args)
when "mailpit"
  paths = args.any? ? args : [ "tests/e2e/product/document_sharing_mailpit.spec.js" ]
  ensure_mailpit_ready &&
    with_server(env: mailpit_server_env) do
      run_playwright(paths: paths, env: mailpit_playwright_env)
    end
when "bughunt"
  bug_id = args.first
  if bug_id&.start_with?("tests/")
    paths = args
    bug_id = nil
  else
    paths = args.drop(1)
  end

  run_bughunt(bug_id, paths)
when "rubocop"
  run_command([ "bin/rubocop", "--cache", "false", "scripts/paper_bridge_qa_harness.rb" ])
when "review"
  run_command([ "ruby", "scripts/check_docs_index.rb" ]) &&
    static_check_passed? &&
    doctor_passed? &&
    run_command([ "bin/rubocop", "--cache", "false", "scripts/paper_bridge_qa_harness.rb" ]) &&
    run_command([ "ruby", "scripts/paper_bridge_harness.rb", "product" ]) &&
    run_command([ "ruby", "scripts/agentic_pipeline_harness.rb", "documents" ]) &&
    with_server { run_playwright(paths: [ "tests/e2e/smoke" ]) }
else
  warn("Unknown command: #{command}")
  usage
  false
end

exit(ok ? 0 : 1)
