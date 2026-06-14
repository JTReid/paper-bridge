require "test_helper"

class ProcessDocumentJobTest < ActiveJob::TestCase
  class FakeConnection
    class << self
      attr_accessor :last_request
    end

    class Request
      def self.execute(**kwargs)
        FakeConnection.last_request = kwargs
        {
          choices: [
            {
              message: {
                content: {
                  title: "Durable Power of Attorney",
                  summary: "This document names an agent and describes authority.",
                  key_points: [
                    "Names an agent",
                    "Describes delegated authority"
                  ],
                  document_type: "legal",
                  notable_dates: []
                }.to_json
              }
            }
          ],
          usage: {
            prompt_tokens: 30,
            completion_tokens: 20,
            total_tokens: 50
          }
        }.to_json
      end
    end
  end

  setup do
    Rails.application.load_seed
    @original_connection = ProcessDocumentJob.llm_connection
    ProcessDocumentJob.llm_connection = FakeConnection
  end

  teardown do
    ProcessDocumentJob.llm_connection = @original_connection
  end

  test "downloads the file, runs the pipeline, and persists the summary" do
    document = create_document
    clear_enqueued_jobs

    assert_difference -> { PipelineRun.count } do
      ProcessDocumentJob.perform_now(document)
    end

    document.reload
    pipeline_run = document.pipeline_runs.last
    payload = JSON.parse(FakeConnection.last_request.fetch(:payload))

    assert_equal "processed", document.status
    assert_equal "Durable Power of Attorney", document.summary.fetch("title")
    assert_equal "This document names an agent and describes authority.", document.summary.fetch("summary")
    assert_equal "completed", pipeline_run.state
    assert_equal "gpt-5.4-nano", payload.fetch("model")
    assert_includes payload.dig("messages", 1, "content"), "This is the uploaded test document."
    assert pipeline_run.pipeline_log.entries.any? { |entry| entry["event_type"] == "llm_call" }
    assert pipeline_run.pipeline_activity.entries.any? { |entry| entry["action"] == "document_summarized" }
  end

  private

    def create_document
      Document.create!(
        account: accounts(:greenfield),
        user: users(:family_admin),
        title: "Power of Attorney",
        file: {
          io: StringIO.new("This is the uploaded test document."),
          filename: "power-of-attorney.txt",
          content_type: "text/plain"
        }
      )
    end
end
