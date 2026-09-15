class AddNonBillableToAccounts < ActiveRecord::Migration[8.1]
  def change
    add_column :accounts, :non_billable, :boolean, default: false, null: false
  end
end
