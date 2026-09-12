# frozen_string_literal: true

# Run after db:migrate in the intended Rails environment. Does not process documents.
Documents::PipelineConfiguration.sync!
puts "Document pipeline configuration synchronized and checked (#{Rails.env})."
