namespace :paper_bridge do
  desc "Set up and validate all required AI configuration without resetting model or prompt choices"
  task setup_ai: :environment do
    require Rails.root.join("lib/setup/ai_configuration").to_s

    Setup::AiConfiguration.call
    puts "AI configuration set up and checked (Rails environment: #{Rails.env})."
  end

  desc "Check stored AI configuration without seeding, changing records, or calling AI"
  task check_ai: :environment do
    require Rails.root.join("lib/setup/ai_configuration_check").to_s

    errors = ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
      Setup::AiConfigurationCheck.call
    end

    if errors.any?
      abort("AI configuration check failed (Rails environment: #{Rails.env}):\n- #{errors.join("\n- ")}")
    end

    puts "AI configuration check passed (Rails environment: #{Rails.env})."
  end
end
