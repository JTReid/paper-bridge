#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

ROOT = Pathname.new(__dir__).join("..").realpath

CURRENT_PRODUCT_FILES = %w[
  AGENTS.md
  config/application.rb
  config/importmap.rb
  config/routes.rb
  db/schema.rb
  db/migrate/20260719000100_create_appointments.rb
  db/migrate/20260808000100_create_ai_assistant_queries.rb
  db/migrate/20260808000200_add_enqueued_at_to_ai_assistant_queries.rb
  docs/runbooks/current-product-shape.md
  docs/runbooks/care-team-access.md
  docs/runbooks/billing.md
  docs/runbooks/document-sharing.md
  scripts/paper_bridge_harness.rb
  scripts/agentic_pipeline_harness.rb
  app/controllers/concerns/calendar_workspace.rb
  app/controllers/concerns/subscription_gate.rb
  app/controllers/application_controller.rb
  app/controllers/home_controller.rb
  app/controllers/dashboard_controller.rb
  app/controllers/calendar_controller.rb
  app/controllers/appointments_controller.rb
  app/controllers/appointment_emails_controller.rb
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
  app/helpers/application_helper.rb
  app/helpers/documents_helper.rb
  app/helpers/ai_assistant_helper.rb
  app/jobs/answer_ai_assistant_query_job.rb
  app/javascript/controllers/document_search_controller.js
  app/javascript/controllers/ai_assistant_query_controller.js
  app/javascript/controllers/appointment_dialog_controller.js
  app/javascript/controllers/family_calendar_controller.js
  app/javascript/controllers/product_tour_controller.js
  app/assets/stylesheets/product_tour.css
  app/assets/stylesheets/vendor/driver.css
  app/models/account.rb
  app/models/ai_assistant_query.rb
  app/models/account_membership.rb
  app/models/user.rb
  app/models/dependent.rb
  app/models/appointment.rb
  app/models/document.rb
  app/models/care_team_membership.rb
  app/models/share_event.rb
  app/models/shared_document.rb
  app/models/billing_subscription.rb
  app/services/billing/stripe_config.rb
  app/services/billing/checkout_return_broadcaster.rb
  app/services/billing/stripe_webhook_handler.rb
  app/mailers/document_share_mailer.rb
  app/mailers/appointment_mailer.rb
  app/views/care_team_memberships/index.html.erb
  app/views/calendar/show.html.erb
  app/views/calendar/_workspace.html.erb
  app/views/calendar/_appointment_button.html.erb
  app/views/appointment_mailer/share.html.erb
  app/views/appointment_mailer/share.text.erb
  app/views/dashboard/index.html.erb
  app/views/dashboard/checkout_pending.html.erb
  app/views/layouts/application.html.erb
  app/views/shared/_app_shell.html.erb
  app/views/dependents/_form.html.erb
  app/views/dependents/show.html.erb
  app/views/documents/_form.html.erb
  app/views/documents/index.html.erb
  app/views/documents/show.html.erb
  app/views/ai_assistant/index.html.erb
  app/views/ai_assistant/_query_result.html.erb
  app/views/ai_assistant/create.turbo_stream.erb
  test/controllers/home_controller_test.rb
  test/controllers/devise_registrations_controller_test.rb
  test/controllers/devise_sessions_controller_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/calendar_controller_test.rb
  test/controllers/appointments_controller_test.rb
  test/controllers/appointment_emails_controller_test.rb
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
  test/fixtures/appointments.yml
  test/fixtures/dependents.yml
  test/models/account_test.rb
  test/models/user_test.rb
  test/models/dependent_test.rb
  test/models/appointment_test.rb
  test/models/care_team_membership_test.rb
  test/models/share_event_test.rb
  test/models/shared_document_test.rb
  test/models/billing_subscription_test.rb
  test/services/billing/stripe_config_test.rb
  test/services/billing/checkout_return_broadcaster_test.rb
  test/services/billing/stripe_webhook_handler_test.rb
  test/mailers/document_share_mailer_test.rb
  test/mailers/appointment_mailer_test.rb
  test/mailers/previews/document_share_mailer_preview_test.rb
  test/helpers/application_helper_test.rb
  test/helpers/documents_helper_test.rb
  test/helpers/ai_assistant_helper_test.rb
  test/controllers/ai_assistant_controller_test.rb
  test/jobs/answer_ai_assistant_query_job_test.rb
  test/models/ai_assistant_query_test.rb
  tests/e2e/product/document_management.spec.js
  tests/e2e/product/calendar.spec.js
  tests/e2e/product/accessibility_suite.spec.js
  tests/e2e/product/mobile_suite.spec.js
  tests/e2e/product/ai_assistant.spec.js
  tests/e2e/product/billing.spec.js
  tests/e2e/product/onboarding_tour.spec.js
  vendor/javascript/driver.js.js
  vendor/javascript/driver.js.LICENSE.txt
].freeze

FOUNDATION_TESTS = %w[
  test/models/account_test.rb
  test/models/user_test.rb
  test/models/dependent_test.rb
  test/helpers/application_helper_test.rb
  test/controllers/home_controller_test.rb
  test/controllers/devise_registrations_controller_test.rb
  test/controllers/devise_sessions_controller_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/dependents_controller_test.rb
].freeze

DOCUMENT_UI_TESTS = %w[
  test/models/document_test.rb
  test/controllers/documents_controller_test.rb
  test/helpers/documents_helper_test.rb
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
  test/controllers/dashboard_controller_test.rb
  test/controllers/billing_controller_test.rb
  test/controllers/billing_checkout_sessions_controller_test.rb
  test/controllers/billing_portal_sessions_controller_test.rb
  test/controllers/admin_accounts_controller_test.rb
  test/controllers/stripe_webhooks_controller_test.rb
  test/services/billing/stripe_config_test.rb
  test/services/billing/checkout_return_broadcaster_test.rb
  test/services/billing/stripe_webhook_handler_test.rb
].freeze

CALENDAR_TESTS = %w[
  test/models/appointment_test.rb
  test/controllers/calendar_controller_test.rb
  test/controllers/appointments_controller_test.rb
  test/controllers/appointment_emails_controller_test.rb
  test/mailers/appointment_mailer_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/dependents_controller_test.rb
].freeze

RUBOCOP_PATHS = %w[
  Gemfile
  config/application.rb
  config/routes.rb
  db/migrate/20260719000100_create_appointments.rb
  db/migrate/20260808000100_create_ai_assistant_queries.rb
  db/migrate/20260808000200_add_enqueued_at_to_ai_assistant_queries.rb
  app/controllers/application_controller.rb
  app/controllers/concerns/calendar_workspace.rb
  app/controllers/concerns/subscription_gate.rb
  app/controllers/home_controller.rb
  app/controllers/dashboard_controller.rb
  app/controllers/calendar_controller.rb
  app/controllers/appointments_controller.rb
  app/controllers/appointment_emails_controller.rb
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
  app/helpers/application_helper.rb
  app/helpers/documents_helper.rb
  app/helpers/ai_assistant_helper.rb
  app/jobs/answer_ai_assistant_query_job.rb
  app/models/account.rb
  app/models/ai_assistant_query.rb
  app/models/account_membership.rb
  app/models/user.rb
  app/models/dependent.rb
  app/models/appointment.rb
  app/models/document.rb
  app/models/care_team_membership.rb
  app/models/share_event.rb
  app/models/shared_document.rb
  app/models/billing_subscription.rb
  app/services/billing/stripe_config.rb
  app/services/billing/checkout_return_broadcaster.rb
  app/services/billing/stripe_webhook_handler.rb
  config/initializers/stripe.rb
  app/mailers/document_share_mailer.rb
  app/mailers/appointment_mailer.rb
  test/test_helper.rb
  test/controllers/home_controller_test.rb
  test/controllers/devise_registrations_controller_test.rb
  test/controllers/devise_sessions_controller_test.rb
  test/controllers/dashboard_controller_test.rb
  test/controllers/calendar_controller_test.rb
  test/controllers/appointments_controller_test.rb
  test/controllers/appointment_emails_controller_test.rb
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
  test/models/dependent_test.rb
  test/models/appointment_test.rb
  test/models/care_team_membership_test.rb
  test/models/share_event_test.rb
  test/models/shared_document_test.rb
  test/models/billing_subscription_test.rb
  test/services/billing/stripe_config_test.rb
  test/services/billing/checkout_return_broadcaster_test.rb
  test/services/billing/stripe_webhook_handler_test.rb
  test/mailers/document_share_mailer_test.rb
  test/mailers/appointment_mailer_test.rb
  test/mailers/previews/document_share_mailer_preview_test.rb
  test/helpers/application_helper_test.rb
  test/helpers/documents_helper_test.rb
  test/helpers/ai_assistant_helper_test.rb
  test/controllers/ai_assistant_controller_test.rb
  test/jobs/answer_ai_assistant_query_job_test.rb
  test/models/ai_assistant_query_test.rb
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
  "document-ui" => [
    [ "bin/rails", "test", *DOCUMENT_UI_TESTS ]
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
  "calendar" => [
    [ "bin/rails", "test", *CALENDAR_TESTS ]
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
      document-ui Run document listing, filename/category filter, upload-form, and presentation tests
      access      Run care team and search-access permission tests
      sharing     Run current document sharing and mailer tests
      billing     Run Stripe billing foundation tests
      calendar    Run appointment persistence, calendar, email delivery, creation, and dashboard tests
      documents   Delegate document ingestion/search checks to the agentic harness
      agentic     Run agentic static, framework, and document lifecycle checks
      product     Run foundation, calendar, document UI, access, sharing, and billing checks
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
  puts "Product workflows covered: foundation, calendar, document UI, access, sharing, billing."
  puts "Agentic document workflows remain delegated to scripts/agentic_pipeline_harness.rb."
  true
end

def run_named_command(name)
  case name
  when "static"
    static_check_passed?
  when "product"
    run_command_group("assets") && %w[foundation calendar document-ui access sharing billing].all? { |command| run_command_group(command) }
  when "review"
    %w[docs static product agentic rubocop].all? { |command| run_named_command(command) }
  when "foundation", "calendar", "document-ui", "access", "sharing", "billing"
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
