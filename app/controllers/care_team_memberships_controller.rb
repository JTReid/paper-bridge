class CareTeamMembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_dependent
  before_action :set_care_team_membership, only: %i[edit update destroy]

  def index
    @care_team_memberships = @dependent.care_team_memberships.includes(:user).order(:created_at)
  end

  def new
    @care_team_membership = @dependent.care_team_memberships.new(default_membership_attributes)
  end

  def create
    user = find_or_initialize_user
    @care_team_membership = @dependent.care_team_memberships.new(care_team_membership_params)
    @care_team_membership.account = current_account
    @care_team_membership.user = user
    @care_team_membership.invited_by = current_user

    if save_invitation(user)
      redirect_to dependent_care_team_memberships_path(@dependent), notice: "Care team member invited."
    else
      user.errors.full_messages.each { |message| @care_team_membership.errors.add(:user, message) }
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

    def default_membership_attributes
      {
        role: :teacher,
        permissions: {
          educational: true,
          medical: false,
          therapy: false,
          insurance: false,
          general: false
        }
      }
    end

    def find_or_initialize_user
      User.find_or_initialize_by(email: care_team_membership_params.fetch(:email).to_s.strip.downcase).tap do |user|
        user.name = care_team_membership_params[:name] if user.new_record? || user.name.blank?
        if user.new_record?
          user.password = SecureRandom.urlsafe_base64(24)
          user.password_confirmation = user.password
        end
      end
    end

    def save_invitation(user)
      ActiveRecord::Base.transaction do
        user.save!
        @care_team_membership.save!
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def care_team_membership_params
      params.require(:care_team_membership).permit(
        :name,
        :email,
        :role,
        :status,
        permissions: CareTeamMembership::DOCUMENT_CATEGORY_PERMISSIONS
      )
    end
end
