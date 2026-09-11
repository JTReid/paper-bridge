class ConvertCareTeamMembershipsToContacts < ActiveRecord::Migration[8.1]
  def change
    add_column :care_team_memberships, :phone_number, :string
    change_column_null :care_team_memberships, :user_id, true
    change_column_null :care_team_memberships, :status, true
    change_column_default :care_team_memberships, :status, from: "invited", to: nil
  end
end
