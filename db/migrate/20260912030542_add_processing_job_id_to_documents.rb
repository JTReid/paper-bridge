class AddProcessingJobIdToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :processing_job_id, :bigint
  end
end
