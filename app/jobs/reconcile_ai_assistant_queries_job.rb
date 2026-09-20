class ReconcileAiAssistantQueriesJob < ApplicationJob
  queue_as :default

  def perform
    AiAssistant::ReconcileFailedQueries.call
  end
end
