# frozen_string_literal: true

# Read the selected environment without changing configuration or calling AI:
#   bin/rails runner scripts/check_document_pipeline_configuration.rb
errors = ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  Documents::PipelineConfigurationCheck.call
end

if errors.any?
  abort("Document pipeline configuration check failed (Rails environment: #{Rails.env}):\n- #{errors.join("\n- ")}")
end

puts "Document pipeline configuration check passed (Rails environment: #{Rails.env})."
