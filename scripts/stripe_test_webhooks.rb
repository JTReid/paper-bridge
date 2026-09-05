# Run through Rails so the listener uses the same encrypted credentials as the
# app, not the Stripe CLI's potentially unrelated default account.
require "logger"
require "open3"
require "optparse"

options = { port: 3000 }
parser = OptionParser.new do |flags|
  flags.banner = "Usage: bin/rails runner scripts/stripe_test_webhooks.rb --confirm-test-mode --account acct_... [--port 3000]"
  flags.on("--confirm-test-mode") { options[:confirmed] = true }
  flags.on("--account ID") { |value| options[:account] = value }
  flags.on("--port PORT", Integer) { |value| options[:port] = value }
  flags.on("--help") { puts flags; exit }
end
parser.parse!
abort parser.to_s unless ARGV.empty? && options[:confirmed] && options[:account]&.match?(/\Aacct_[A-Za-z0-9]+\z/)
abort "Only local development forwarding is supported." unless Rails.env.development? && options[:port].between?(1, 65_535)

begin
  Stripe.logger = Logger.new(File::NULL)
  key = Billing::StripeConfig.secret_key.to_s
  abort "A Stripe test-mode key is required; live keys are never accepted." unless key.match?(/\A(?:rk|sk)_test_\S+\z/)
  Stripe.api_key = key
  account = Stripe::Account.retrieve
  abort "The configured Stripe account does not match --account." unless account.id == options[:account]

  cli_environment = { "STRIPE_API_KEY" => key, "STRIPE_DEVICE_NAME" => "paperbridge-company-test" }
  output, status = Open3.capture2e(cli_environment, "stripe", "listen", "--print-secret", "--skip-update")
  signing_secret = output[/\bwhsec_[A-Za-z0-9]+\b/]
  abort "Could not obtain the test listener signing secret. Check Stripe CLI access." unless status.success? && signing_secret
  configured_secret = Billing::StripeConfig.webhook_secret.to_s
  unless ActiveSupport::SecurityUtils.secure_compare(signing_secret, configured_secret)
    abort "The app's webhook signing secret does not match this test account's CLI listener. Update encrypted development credentials before forwarding."
  end

  destination = "http://127.0.0.1:#{options[:port]}/stripe/webhooks"
  events = %w[checkout.session.completed customer.subscription.created customer.subscription.updated customer.subscription.deleted invoice.payment_failed]
  puts "Forwarding TEST events for #{account.id} to #{destination}. Secret values are hidden."
  $stdout.sync = true
  Open3.popen2e(cli_environment, "stripe", "listen", "--skip-update", "--events", events.join(","), "--forward-to", destination) do |input, stream, process|
    input.close
    begin
      stream.each_line { |line| puts line.gsub(/\b(?:whsec_|[rs]k_(?:test|live)_)[A-Za-z0-9]+/, "[REDACTED]") }
      exit process.value.exitstatus || 1
    ensure
      Process.kill("TERM", process.pid) if process.alive?
    end
  end
rescue Stripe::StripeError => error
  abort "Stripe test listener failed (#{error.class.name}). Check test-mode permissions."
rescue Errno::ENOENT
  abort "Stripe CLI was not found. Install it before starting test webhook forwarding."
end
