#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__).join("..").realpath

CURRENT_PRODUCT_FILES = %w[
  AGENTS.md
  config/routes.rb
  docs/runbooks/current-product-shape.md
  docs/runbooks/care-team-access.md
  docs/runbooks/billing.md
  docs/runbooks/document-sharing.md
  scripts/paper_bridge_harness.rb
  scripts/agentic_pipeline_harness.rb
  app/controllers/concerns/subscription_gate.rb
  app/controllers/application_controller.rb
  app/controllers/home_controller.rb
  app/controllers/dashboard_controller.rb
  app/controllers/dependents_controller.rb
  app/controllers/documents_controller.rb
  app/controllers/care_team_memberships_controller.rb
  app/controllers/share_events_controller.rb
  app/controllers/ai_assistant_controller.rb
  app/controllers/billing_controller.rb
  app/controllers/billing/checkout_sessions_controller.rb
  app/controllers/billing/portal_sessions_controller.rb
  app/controllers/admin/base_controller.rb
  app/controllers/admin/accounts_controller.rb
  app/models/account.rb
  app/models/account_membership.rb
  app/models/user.rb
  app/models/dependent.rb
  app/models/document.rb
  app/models/care_team_membership.rb
  app/models/share_event.rb
  app/models/shared_document.rb
  app/models/billing_subscription.rb
  app/services/billing/stripe_config.rb
  app/services/billing/stripe_webhook_handler.rb
  app/mailers/document_share_mailer.rb
  test/controllers/home_controller_test.rb
  test/controllers/devise_registrations_controller_test.rb
  test/controllers/devise_sessions_controller_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/dependents_controller_test.rb
  test/controllers/documents_controller_test.rb
  test/controllers/care_team_memberships_controller_test.rb
  test/controllers/share_events_controller_test.rb
  test/controllers/billing_controller_test.rb
  test/controllers/billing_checkout_sessions_controller_test.rb
  test/controllers/billing_portal_sessions_controller_test.rb
  test/controllers/admin_accounts_controller_test.rb
  test/controllers/stripe_webhooks_controller_test.rb
  test/fixtures/billing_subscriptions.yml
  test/models/account_test.rb
  test/models/user_test.rb
  test/models/care_team_membership_test.rb
  test/models/share_event_test.rb
  test/models/shared_document_test.rb
  test/models/billing_subscription_test.rb
  test/services/billing/stripe_config_test.rb
  test/services/billing/stripe_webhook_handler_test.rb
  test/mailers/document_share_mailer_test.rb
  test/mailers/previews/document_share_mailer_preview_test.rb
].freeze

FOUNDATION_TESTS = %w[
  test/models/account_test.rb
  test/models/user_test.rb
  test/controllers/home_controller_test.rb
  test/controllers/devise_registrations_controller_test.rb
  test/controllers/devise_sessions_controller_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/dependents_controller_test.rb
].freeze

ACCESS_TESTS = %w[
  test/models/care_team_membership_test.rb
  test/controllers/care_team_memberships_controller_test.rb
  test/services/documents/search_access_profile_test.rb
].freeze

SHARING_TESTS = %w[
  test/models/share_event_test.rb
  test/models/shared_document_test.rb
  test/controllers/share_events_controller_test.rb
  test/mailers/document_share_mailer_test.rb
  test/mailers/previews/document_share_mailer_preview_test.rb
].freeze

BILLING_TESTS = %w[
  test/models/billing_subscription_test.rb
  test/controllers/billing_controller_test.rb
  test/controllers/billing_checkout_sessions_controller_test.rb
  test/controllers/billing_portal_sessions_controller_test.rb
  test/controllers/admin_accounts_controller_test.rb
  test/controllers/stripe_webhooks_controller_test.rb
  test/services/billing/stripe_config_test.rb
  test/services/billing/stripe_webhook_handler_test.rb
].freeze

RUBOCOP_PATHS = %w[
  Gemfile
  app/controllers/application_controller.rb
  app/controllers/concerns/subscription_gate.rb
  app/controllers/home_controller.rb
  app/controllers/dashboard_controller.rb
  app/controllers/dependents_controller.rb
  app/controllers/documents_controller.rb
  app/controllers/care_team_memberships_controller.rb
  app/controllers/share_events_controller.rb
  app/controllers/ai_assistant_controller.rb
  app/controllers/billing_controller.rb
  app/controllers/billing/checkout_sessions_controller.rb
  app/controllers/billing/portal_sessions_controller.rb
  app/controllers/admin/base_controller.rb
  app/controllers/admin/accounts_controller.rb
  app/models/account.rb
  app/models/account_membership.rb
  app/models/user.rb
  app/models/dependent.rb
  app/models/document.rb
  app/models/care_team_membership.rb
  app/models/share_event.rb
  app/models/shared_document.rb
  app/models/billing_subscription.rb
  app/services/billing/stripe_config.rb
  app/services/billing/stripe_webhook_handler.rb
  config/initializers/stripe.rb
  app/mailers/document_share_mailer.rb
  test/test_helper.rb
  test/controllers/home_controller_test.rb
  test/controllers/devise_registrations_controller_test.rb
  test/controllers/devise_sessions_controller_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/dependents_controller_test.rb
  test/controllers/documents_controller_test.rb
  test/controllers/care_team_memberships_controller_test.rb
  test/controllers/share_events_controller_test.rb
  test/controllers/billing_controller_test.rb
  test/controllers/billing_checkout_sessions_controller_test.rb
  test/controllers/billing_portal_sessions_controller_test.rb
  test/controllers/admin_accounts_controller_test.rb
  test/controllers/stripe_webhooks_controller_test.rb
  test/models/account_test.rb
  test/models/user_test.rb
  test/models/care_team_membership_test.rb
  test/models/share_event_test.rb
  test/models/shared_document_test.rb
  test/models/billing_subscription_test.rb
  test/services/billing/stripe_config_test.rb
  test/services/billing/stripe_webhook_handler_test.rb
  test/mailers/document_share_mailer_test.rb
  test/mailers/previews/document_share_mailer_preview_test.rb
  scripts/paper_bridge_harness.rb
].freeze

COMMANDS = {
  "docs" => [
    [ "ruby", "scripts/check_docs_index.rb" ]
  ],
  "assets" => [
    [ "bin/rails", "tailwindcss:build" ]
  ],
  "foundation" => [
    [ "bin/rails", "test", *FOUNDATION_TESTS ]
  ],
  "access" => [
    [ "bin/rails", "test", *ACCESS_TESTS ]
  ],
  "sharing" => [
    [ "bin/rails", "test", *SHARING_TESTS ]
  ],
  "billing" => [
    [ "bin/rails", "test", *BILLING_TESTS ]
  ],
  "documents" => [
    [ "ruby", "scripts/agentic_pipeline_harness.rb", "documents" ]
  ],
  "agentic" => [
    [ "ruby", "scripts/agentic_pipeline_harness.rb", "static" ],
    [ "ruby", "scripts/agentic_pipeline_harness.rb", "tests" ],
    [ "ruby", "scripts/agentic_pipeline_harness.rb", "documents" ]
  ],
  "rubocop" => [
    [ "bin/rubocop", "--cache", "false", *RUBOCOP_PATHS ]
  ]
}.freeze

def usage
  puts(<<~USAGE)
    Usage: ruby scripts/paper_bridge_harness.rb COMMAND

    Commands:
      docs        Check agent-facing docs are indexed
      assets      Build generated Tailwind CSS for Rails view tests
      static      Check current product-shape files and runbooks exist
      foundation  Run public/auth/account/dashboard/dependent workflow tests
      access      Run care team and search-access permission tests
      sharing     Run current document sharing and mailer tests
      billing     Run Stripe billing foundation tests
      documents   Delegate document ingestion/search checks to the agentic harness
      agentic     Run agentic static, framework, and document lifecycle checks
      product     Run foundation, access, sharing, and billing checks
      rubocop     Run RuboCop on current product-shape files
      review      Run docs, static, product, agentic, and rubocop checks
  USAGE
end

def run_command(command)
  puts("\n--- #{command.join(" ")} ---")
  system(*command, chdir: ROOT.to_s)
end

def run_command_group(name)
  COMMANDS.fetch(name).all? { |command| run_command(command) }
end

def static_check_passed?
  failures = []

  missing_files = CURRENT_PRODUCT_FILES.reject { |relative_path| ROOT.join(relative_path).file? }
  failures.concat(missing_files.map { |path| "Missing expected current product-shape file: #{path}" })

  if failures.any?
    warn("PaperBridge product static check failed:\n#{failures.map { |failure| "- #{failure}" }.join("\n")}")
    return false
  end

  puts "Expected current product-shape files exist."
  puts "Product workflows covered: foundation, access, sharing, billing."
  puts "Agentic document workflows remain delegated to scripts/agentic_pipeline_harness.rb."
  true
end

def run_named_command(name)
  case name
  when "static"
    static_check_passed?
  when "product"
    run_command_group("assets") && %w[foundation access sharing billing].all? { |command| run_command_group(command) }
  when "review"
    %w[docs static product agentic rubocop].all? { |command| run_named_command(command) }
  when "foundation", "access", "sharing", "billing"
    run_command_group("assets") && run_command_group(name)
  else
    run_command_group(name)
  end
end

command = ARGV.fetch(0, nil)

case command
when nil, "-h", "--help", "help"
  usage
when "static", "product", "review", *COMMANDS.keys
  exit(run_named_command(command) ? 0 : 1)
else
  warn("Unknown command: #{command}")
  usage
  exit(1)
end
