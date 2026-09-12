# Required AI records use the same setup as the Heroku release task.
require Rails.root.join("lib/setup/ai_configuration").to_s
Setup::AiConfiguration.call

load Rails.root.join("db/seeds/qa_harness.rb") if ENV["PAPER_BRIDGE_SEED_QA"].present?
