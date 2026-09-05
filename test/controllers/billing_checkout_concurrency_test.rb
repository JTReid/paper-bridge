require "test_helper"
require "timeout"

class BillingCheckoutConcurrencyTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  test "overlapping checkout posts create one Stripe session" do
    threads = nil
    account = Account.create!(name: "Concurrent checkout")
    user = User.create!(email: "checkout-#{SecureRandom.hex(8)}@example.test", password: "checkout-test-password")
    account.account_memberships.create!(user: user, role: :admin)
    account.create_billing_subscription!(status: :incomplete, stripe_customer_id: "cus_concurrent_checkout")
    sessions = 2.times.map do
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.post user_session_path, params: { user: { email: user.email, password: "checkout-test-password" } }
      assert session.response.redirect?
      session
    end
    lock_attempts = Queue.new
    api_entered = Queue.new
    api_release = Queue.new
    creations = 0
    retrievals = 0
    target_id = account.id
    original_lock = Account.instance_method(:with_lock)
    Account.define_method(:with_lock) do |*args, **kwargs, &block|
      lock_attempts << true if id == target_id
      original_lock.bind_call(self, *args, **kwargs, &block)
    end

    stripe_session = Struct.new(:id, :url, :status).new("cs_concurrent", "https://checkout.stripe.test/concurrent", "open")
    creator = lambda do |*_args|
      creations += 1
      api_entered << true
      api_release.pop
      stripe_session
    end
    retriever = lambda do |id|
      assert_equal "cs_concurrent", id
      retrievals += 1
      stripe_session
    end

    with_stubbed_singleton_method(Billing::StripeConfig, :checkout_ready?, true) do
      with_stubbed_singleton_method(Billing::StripeConfig, :profile_price_id, "price_concurrent") do
        with_stubbed_singleton_method(Stripe::Checkout::Session, :create, creator) do
          with_stubbed_singleton_method(Stripe::Checkout::Session, :retrieve, retriever) do
            threads = sessions.map do |session|
              Thread.new do
                ActiveRecord::Base.connection_pool.with_connection do
                  session.post billing_checkout_session_path
                  [ session.response.status, session.response.location ]
                end
              end
            end

            Timeout.timeout(15) do
              # Both requests reach the same account lock while the first
              # request is still waiting on Stripe. Only then let it complete.
              2.times { lock_attempts.pop }
              api_entered.pop
              api_release << true
              threads.each do |thread|
                assert_equal [ 303, "https://checkout.stripe.test/concurrent" ], thread.value
              end
            end
          end
        end
      end
    end

    assert_equal 1, creations
    assert_equal 1, retrievals
    assert_equal "cs_concurrent", account.reload.billing_subscription.checkout_attempt.fetch("session_id")
  ensure
    2.times { api_release << true } if api_release
    threads&.each do |thread|
      thread.join(5)
      thread.kill.join if thread.alive?
    end
    Account.define_method(:with_lock, original_lock) if original_lock
    account&.destroy!
    user&.destroy!
  end
end
