class ApplicationMailer < ActionMailer::Base
  default from: -> { Rails.application.credentials[:mailer_from].presence || "from@example.com" }
  layout "mailer"
end
