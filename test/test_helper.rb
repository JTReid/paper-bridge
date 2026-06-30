ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "active_job/test_helper"
require "rails/test_help"

module SingletonMethodStub
  def with_stubbed_singleton_method(object, method_name, replacement)
    singleton_class = object.singleton_class
    method_existed = object.respond_to?(method_name, true)
    original_method = object.method(method_name) if method_existed

    singleton_class.define_method(method_name) do |*args, **kwargs, &block|
      if replacement.respond_to?(:call)
        replacement.call(*args, **kwargs, &block)
      else
        replacement
      end
    end

    yield
  ensure
    if method_existed
      singleton_class.define_method(method_name) do |*args, **kwargs, &block|
        original_method.call(*args, **kwargs, &block)
      end
    elsif singleton_class.method_defined?(method_name)
      singleton_class.remove_method(method_name)
    end
  end
end

module ActiveSupport
  class TestCase
    include ActiveJob::TestHelper
    include SingletonMethodStub

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    setup do
      clear_enqueued_jobs
      clear_performed_jobs
    end
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SingletonMethodStub
end
