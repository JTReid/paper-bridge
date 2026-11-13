class RemoveLegacyNameFromDependents < ActiveRecord::Migration[8.1]
  def change
    # Fails, and rolls back the whole migration, if any profile still has no first name.
    change_column_null :dependents, :first_name, false
    remove_column :dependents, :legacy_name, :string
  end
end
