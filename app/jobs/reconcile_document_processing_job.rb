class ReconcileDocumentProcessingJob < ApplicationJob
  queue_as :default

  def perform
    Documents::ReconcileFailedProcessing.call
  end
end
