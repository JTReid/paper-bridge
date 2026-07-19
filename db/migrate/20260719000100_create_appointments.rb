class CreateAppointments < ActiveRecord::Migration[8.1]
  def change
    create_table :appointments do |t|
      t.references :dependent, null: false, foreign_key: true, index: false
      t.datetime :scheduled_at, null: false
      t.text :description, null: false

      t.timestamps
    end

    add_index :appointments, [ :dependent_id, :scheduled_at ]
  end
end
