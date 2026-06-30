class ApplicationMailer < ActionMailer::Base
  DEFAULT_FROM_ADDRESS = "support@paperbridgeadvocacy.com"

  default from: -> { Rails.application.credentials[:mailer_from].presence || DEFAULT_FROM_ADDRESS }
  layout "mailer"
end
