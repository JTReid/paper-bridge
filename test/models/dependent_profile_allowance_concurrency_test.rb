require "test_helper"
require "timeout"

class DependentProfileAllowanceConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent creations cannot claim the same remaining profile slot" do
    account = Account.create!(name: "Concurrent profile allowance test")
    account.create_billing_subscription!(status: :active, profile_limit: 5)
    4.times { |index| account.dependents.create!(first_name: "Existing #{index}") }
    ready = Queue.new
    release = Queue.new

    threads = 2.times.map do |index|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          profile = Dependent.new(account_id: account.id, first_name: "Concurrent #{index}")
          # Both requests pass the ordinary validation before either INSERT.
          # The locked callback must still allow only one of them to save.
          profile.define_singleton_method(:valid?) do |context = nil|
            result = super(context)
            ready << result
            release.pop
            result
          end

          [ profile.save, profile.errors[:base] ]
        end
      end
    end

    Timeout.timeout(10) do
      2.times { assert ready.pop }
      2.times { release << true }
      results = threads.map(&:value)

      assert_equal 1, results.count(&:first)
      assert_match(/allowance is full/, results.find { |saved, _| !saved }.last.join)
      assert_equal 5, account.dependents.count
    end
  ensure
    2.times { release << true } if release
    threads&.each do |thread|
      thread.join(5)
      thread.kill.join if thread.alive?
    end
    account&.destroy!
  end
end
