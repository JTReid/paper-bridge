# frozen_string_literal: true

class ReworkMembershipDomain < ActiveRecord::Migration[8.1]
  def up
    create_table :account_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end
    add_index :account_memberships, %i[account_id user_id], unique: true
    add_index :account_memberships, %i[user_id role]

    create_table :dependents do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.date :date_of_birth
      t.string :avatar_url
      t.string :grade
      t.string :school
      t.text :notes

      t.timestamps
    end
    add_index :dependents, %i[account_id name]

    create_table :care_team_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :dependent, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :email, null: false
      t.string :role, null: false
      t.string :status, null: false, default: "invited"
      t.jsonb :permissions, null: false, default: {}
      t.datetime :invited_at
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :care_team_memberships, %i[dependent_id user_id], unique: true
    add_index :care_team_memberships, %i[account_id status]
    add_index :care_team_memberships, :email

    add_reference :documents, :dependent, null: false, foreign_key: true
    add_column :documents, :category, :string, null: false, default: "general"
    add_index :documents, %i[dependent_id created_at]
    add_index :documents, %i[account_id category]

    remove_reference :users, :account, foreign_key: true, index: true
    remove_column :users, :role
  end

  def down
    add_reference :users, :account, null: true, foreign_key: true
    add_column :users, :role, :string, null: false, default: "family_admin"

    remove_index :documents, %i[account_id category]
    remove_index :documents, %i[dependent_id created_at]
    remove_column :documents, :category
    remove_reference :documents, :dependent, foreign_key: true

    drop_table :care_team_memberships
    drop_table :dependents
    drop_table :account_memberships
  end
end
