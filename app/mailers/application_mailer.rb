class ApplicationMailer < ActionMailer::Base
  DEFAULT_FROM_ADDRESS = "support@paperbridgeadvocacy.com"

  default from: -> { ApplicationMailer.default_from_address }
  layout "mailer"

  def self.default_from_address
    Rails.application.credentials[:mailer_from].presence || DEFAULT_FROM_ADDRESS
  end
end
