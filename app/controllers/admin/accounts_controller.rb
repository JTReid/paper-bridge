module Admin
  class AccountsController < BaseController
    def index
      @accounts = Account.includes(:billing_subscription, :users).order(:name)
    end
  end
end
