require "test_helper"
require "rake"
require Rails.root.join("lib/setup/ai_configuration").to_s

class PaperBridgeTasksTest < ActiveSupport::TestCase
  setup do
    @original_rake_application = Rake.application
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/paper_bridge.rake")
  end

  teardown do
    Rake.application = @original_rake_application
  end

  test "release setup task initializes all AI configuration without seeding families or running AI" do
    Prompt.delete_all
    AgentType.delete_all
    Llm.delete_all
    JsonSchema.delete_all

    assert_no_difference [ "Account.count", "User.count", "Document.count", "PipelineRun.count" ] do
      assert_no_enqueued_jobs do
        with_stubbed_singleton_method(Rails.application, :load_seed, -> { flunk "Release setup must not load sample data" }) do
          with_stubbed_singleton_method(Agentic::Providers::Openai, :new, ->(*) { flunk "Setup must not call AI" }) do
            output, errors = capture_io { Rake::Task["paper_bridge:setup_ai"].invoke }
            assert_includes output, "set up and checked (Rails environment: test)"
            assert_empty errors
          end
        end
      end
    end

    assert_equal 3, Llm.count
    assert_equal 9, AgentType.count
    assert_equal 9, Prompt.active.count
    assert_equal 14, JsonSchema.count
    assert_empty Setup::AiConfigurationCheck.call
  end

  test "check task reports the selected environment without changing configuration" do
    Setup::AiConfiguration.call
    before = configuration_snapshot

    with_stubbed_singleton_method(Setup::AiConfiguration, :call, -> { flunk "Checking must not set up records" }) do
      output, errors = capture_io { Rake::Task["paper_bridge:check_ai"].invoke }

      assert_includes output, "passed (Rails environment: test)"
      assert_empty errors
    end

    assert_equal before, configuration_snapshot
  end

  test "check task exits unsuccessfully when Ask PaperBridge configuration is missing" do
    Setup::AiConfiguration.call
    JsonSchema.find_by!(name: "openai_search_answer").destroy!
    before = configuration_snapshot

    output, errors = capture_io do
      exception = assert_raises(SystemExit) { Rake::Task["paper_bridge:check_ai"].invoke }
      assert_equal 1, exception.status
    end

    assert_empty output
    assert_includes errors, "failed (Rails environment: test)"
    assert_includes errors, "openai_search_answer is missing"
    assert_equal before, configuration_snapshot
  end

  test "setup task propagates invalid configuration rather than reporting a successful release" do
    Setup::AiConfiguration.call
    AgentType.find_by!(name: "search_answer_generator").prompts.active.first.update_column(:system_directive, " ")
    before = configuration_snapshot

    output, = capture_io do
      error = assert_raises(Agentic::Errors::ConfigurationError) { Rake::Task["paper_bridge:setup_ai"].invoke }
      assert_includes error.message, "search_answer_generator has a blank active prompt"
    end

    assert_empty output
    assert_equal before, configuration_snapshot
  end

  private

    def configuration_snapshot
      [ Llm, AgentType, Prompt, JsonSchema ].map { |model| model.order(:id).map(&:attributes) }
    end
end
