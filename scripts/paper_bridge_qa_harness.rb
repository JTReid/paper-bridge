#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "net/http"
require "pathname"
require "time"
require "timeout"

ROOT = Pathname.new(__dir__).join("..").realpath
QA_PORT = ENV.fetch("QA_PORT", "3100")
QA_HOST = ENV.fetch("QA_HOST", "127.0.0.1")
QA_BASE_URL = ENV.fetch("QA_BASE_URL", "http://#{QA_HOST}:#{QA_PORT}")
MAILPIT_SMTP_ADDRESS = ENV.fetch("MAILPIT_SMTP_ADDRESS", "127.0.0.1")
MAILPIT_SMTP_PORT = ENV.fetch("MAILPIT_SMTP_PORT", "1025")
MAILPIT_API_URL = ENV.fetch("QA_MAILPIT_API_URL", "http://127.0.0.1:8025")
ARTIFACT_ROOT = ROOT.join("tmp/qa-artifacts")
SERVER_LOG = ARTIFACT_ROOT.join("logs/rails-test-server.log")

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
  tests/e2e/product/dependent_workspace.spec.js
  tests/e2e/product/document_sharing.spec.js
  tests/e2e/product/document_sharing_mailpit.spec.js
  tests/e2e/product/billing.spec.js
  tests/e2e/product/document_management.spec.js
  tests/e2e/product/care_team.spec.js
  tests/e2e/product/care_team_negative.spec.js
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
      mailpit  Run email QA checks through local Mailpit SMTP and API
      bughunt  Run browser checks with named screenshots, videos, and traces always on
      rubocop  Run RuboCop on the QA harness Ruby script
      review   Run docs, static, doctor, development harness checks, and browser smoke

    Examples:
      ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal
      ruby scripts/paper_bridge_qa_harness.rb bughunt share-modal tests/e2e/product/document_sharing.spec.js
      ruby scripts/paper_bridge_qa_harness.rb bughunt tests/e2e/product/document_sharing.spec.js
      ruby scripts/paper_bridge_qa_harness.rb mailpit
      ruby scripts/paper_bridge_qa_harness.rb mailpit tests/e2e/product/document_sharing_mailpit.spec.js
  USAGE
end

def run_command(command, env: {})
  puts("\n--- #{[ env_summary(env), command.join(" ") ].compact.join(" ")} ---")
  system(env, *command, chdir: ROOT.to_s)
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

def run_playwright(paths: [], always_record: false, artifact_dir: nil, env: {})
  ensure_artifact_dirs
  command = [ "npx", "playwright", "test", *paths, "--project=chromium" ]
  playwright_env = {
    "QA_BASE_URL" => QA_BASE_URL
  }.merge(env)
  playwright_env["QA_ARTIFACT_MODE"] = "always" if always_record
  playwright_env["QA_ARTIFACT_DIR"] = artifact_dir.relative_path_from(ROOT).to_s if artifact_dir

  result = run_command(command, env: playwright_env)

  if artifact_dir
    puts "\nQA artifacts written under #{artifact_dir.relative_path_from(ROOT)}"
    puts "HTML report: #{artifact_dir.join("playwright-report/index.html").relative_path_from(ROOT)}"
  end

  result
end

def bughunt_artifact_dir(raw_bug_id)
  bug_id = raw_bug_id.to_s.strip
  bug_id = Time.now.utc.strftime("bug-%Y%m%d-%H%M%S") if bug_id.empty?
  safe_bug_id = bug_id.downcase.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A-+|-+\z/, "")
  safe_bug_id = Time.now.utc.strftime("bug-%Y%m%d-%H%M%S") if safe_bug_id.empty?
  ARTIFACT_ROOT.join("bugs", safe_bug_id)
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
    [ "node", "--version" ],
    [ "npm", "--version" ],
    [ "npx", "playwright", "--version" ],
    [ "npm", "ls", "@axe-core/playwright", "--depth=0" ],
    [ "psql", "postgres", "-tAc", "SELECT default_version FROM pg_available_extensions WHERE name = 'vector'" ]
  ]

  checks.all? { |command| run_command(command) }
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

  artifact_dir = bughunt_artifact_dir(bug_id)
  FileUtils.mkdir_p(artifact_dir)
  with_server { run_playwright(paths: paths, always_record: true, artifact_dir: artifact_dir) }
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
