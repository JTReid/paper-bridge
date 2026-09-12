# frozen_string_literal: true

# Run after the schema-only migration:
#   bin/rails runner scripts/update_document_metadata_schemas.rb
Documents::MetadataSchemas.update!
puts "Created or updated the four document summary and image extraction schema records."
