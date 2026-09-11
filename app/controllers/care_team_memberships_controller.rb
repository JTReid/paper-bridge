class CareTeamMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_current_account!
  before_action :set_dependent
  before_action :require_account_manager!, except: :index
  before_action :set_care_team_membership, only: %i[edit update destroy]

  def index
    @care_team_memberships = @dependent.care_team_memberships.order(:created_at)
  end

  def new
    @care_team_membership = @dependent.care_team_memberships.new(role: :teacher)
  end

  def create
    @care_team_membership = @dependent.care_team_memberships.new(care_team_membership_params)
    @care_team_membership.account = current_account
    @care_team_membership.invited_by = current_user

    if @care_team_membership.save
      redirect_to dependent_care_team_memberships_path(@dependent), notice: "Care team member added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @care_team_membership.update(care_team_membership_params)
      redirect_to dependent_care_team_memberships_path(@dependent), notice: "Care team member updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @care_team_membership.destroy
    redirect_to dependent_care_team_memberships_path(@dependent), notice: "Care team member removed.", status: :see_other
  end

  private

    def set_dependent
      @dependent = current_account.dependents.find(params[:dependent_id])
    end

    def set_care_team_membership
      @care_team_membership = @dependent.care_team_memberships.find(params[:id])
    end

    def require_account_manager!
      head :forbidden unless current_user.can_manage_account?(current_account)
    end

    def care_team_membership_params
      params.require(:care_team_membership).permit(
        :name,
        :email,
        :role,
        :phone_number
      )
    end
end
