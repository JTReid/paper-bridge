release: bundle exec rails db:migrate && bundle exec rails runner scripts/sync_document_pipeline_configuration.rb
web: bundle exec puma -C config/puma.rb
worker: bundle exec bin/jobs
