class AddSiteRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :site_role, :string, null: false, default: "user"
    add_index :users, :site_role
  end
end
