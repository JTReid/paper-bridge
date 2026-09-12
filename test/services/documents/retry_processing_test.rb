require "test_helper"

class Documents::RetryProcessingTest < ActiveSupport::TestCase
  setup do
    @document = documents(:advance_directive)
    @document.file.attach(io: StringIO.new("Original text"), filename: "source.txt", content_type: "text/plain", metadata: { analyzed: true })
    @document.update!(status: :failed, preparation_error: "Earlier failure", summary: { summary: "Earlier result" })
    clear_enqueued_jobs
  end

  test "queues one full retry while retaining all data until the worker starts" do
    before = @document.attributes.except("status", "updated_at")
    page_ids = @document.document_pages.ids
    chunk_ids = @document.document_chunks.ids

    assert_enqueued_with(job: ProcessDocumentJob, args: [ @document ]) do
      assert Documents::RetryProcessing.call(@document)
    end
    assert_predicate @document.reload, :queued?
    assert_equal before, @document.attributes.except("status", "updated_at")
    assert_equal page_ids, @document.document_pages.ids
    assert_equal chunk_ids, @document.document_chunks.ids
    assert_no_enqueued_jobs { assert_not Documents::RetryProcessing.call(Document.find(@document.id)) }
  end

  test "routes failed images to the image pipeline" do
    @document.file.attach(io: StringIO.new("Image upload"), filename: "source.png", content_type: "image/png", metadata: { analyzed: true })
    clear_enqueued_jobs

    assert_enqueued_with(job: ProcessImageDocumentJob, args: [ @document ]) do
      assert Documents::RetryProcessing.call(@document)
    end
  end

  test "rejects nonfailed documents and storage-only files" do
    (Document.statuses.keys - [ "failed" ]).each do |status|
      @document.update!(status: status)
      assert_no_enqueued_jobs { assert_not Documents::RetryProcessing.call(@document), status }
    end
    @document.file.attach(io: StringIO.new("Stored file"), filename: "source.docx", content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", metadata: { analyzed: true })
    @document.update!(status: :failed)
    clear_enqueued_jobs
    assert_no_enqueued_jobs { assert_not Documents::RetryProcessing.call(@document) }
  end

  test "rejects a missing original attachment" do
    @document.file.detach
    assert_no_enqueued_jobs { assert_not Documents::RetryProcessing.call(@document) }
  end

  test "an unsuccessful enqueue rolls back the queued status and preserves evidence" do
    before = @document.attributes
    with_stubbed_singleton_method(ProcessDocumentJob, :perform_later, ->(*) { false }) do
      assert_raises(Documents::RetryProcessing::EnqueueError) { Documents::RetryProcessing.call(@document) }
    end
    assert_equal before, @document.reload.attributes
    assert_equal "Original text", @document.file.download
    assert_equal 1, @document.document_chunks.count
  end

  test "a queue database error rolls back the queued status" do
    before = @document.attributes
    with_stubbed_singleton_method(ProcessDocumentJob, :perform_later, ->(*) { raise SolidQueue::Job::EnqueueError, "Queue unavailable" }) do
      assert_raises(Documents::RetryProcessing::EnqueueError) { Documents::RetryProcessing.call(@document) }
    end
    assert_equal before, @document.reload.attributes
  end

  test "an unfinished automatic retry prevents another manual attempt" do
    create_queue_tables
    job = create_queue_job(@document, scheduled_at: 1.minute.from_now)
    before = @document.attributes

    with_stubbed_singleton_method(ProcessDocumentJob, :queue_adapter_name, "solid_queue") do
      assert_no_enqueued_jobs { assert_not Documents::RetryProcessing.call(@document) }
    end
    assert_equal before, @document.reload.attributes
    assert_nil job.reload.finished_at
  end

  test "terminal queue failures and another document's pending job do not block retry" do
    create_queue_tables
    job = create_queue_job(@document)
    SolidQueue::FailedExecution.create!(job: job, exception: StandardError.new("Previous processing failed"))
    create_queue_job(documents(:outside_account))

    with_stubbed_singleton_method(ProcessDocumentJob, :queue_adapter_name, "solid_queue") do
      assert_enqueued_with(job: ProcessDocumentJob, args: [ @document ]) do
        assert Documents::RetryProcessing.call(@document)
      end
    end
  end

  private

    def create_queue_job(document, scheduled_at: nil)
      arguments = ProcessDocumentJob.new(document).serialize
      id = SolidQueue::Job.insert_all!([ {
        active_job_id: arguments.fetch("job_id"), class_name: "ProcessDocumentJob", arguments: arguments,
        queue_name: "default", scheduled_at: scheduled_at, created_at: Time.current, updated_at: Time.current
      } ]).first.fetch("id")
      SolidQueue::Job.find(id)
    end

    def create_queue_tables
      # Exercise the real queue lookup inside the test transaction, without
      # connecting to the development queue database.
      connection = SolidQueue::Record.connection
      unless connection.table_exists?(:solid_queue_jobs)
        connection.create_table :solid_queue_jobs do |table|
          table.string :active_job_id
          table.string :class_name
          table.text :arguments
          table.string :queue_name
          table.datetime :scheduled_at
          table.datetime :finished_at
          table.timestamps
        end
      end
      unless connection.table_exists?(:solid_queue_failed_executions)
        connection.create_table :solid_queue_failed_executions do |table|
          table.bigint :job_id
          table.text :error
          table.datetime :created_at
        end
      end
      SolidQueue::Job.reset_column_information
      SolidQueue::FailedExecution.reset_column_information
    end
end
