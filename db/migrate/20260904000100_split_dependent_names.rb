class SplitDependentNames < ActiveRecord::Migration[8.1]
  def change
    remove_index :dependents, %i[account_id name]
    rename_column :dependents, :name, :legacy_name
    change_column_null :dependents, :legacy_name, true
    add_column :dependents, :first_name, :string
    add_column :dependents, :last_name, :string
    add_index :dependents, %i[account_id first_name last_name]
  end
end
