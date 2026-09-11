module MeetingPrepWorkspace
  private

    def load_meeting_prep_workspace
      @meeting_prep_answers = @meeting_prep.meeting_prep_answers.includes(:saved_answer)
      source_ids = @meeting_prep_answers.flat_map do |entry|
        Array(entry.saved_answer.answer_payload[:citations]).filter_map { |citation| citation[:document_id] }
      end
      @source_documents_by_id = @dependent.documents.where(id: source_ids).includes(file_attachment: :blob).index_by(&:id)
      @available_saved_answers = current_user.saved_answers.where(account: current_account, dependent: @dependent)
        .where.not(id: @meeting_prep.meeting_prep_answers.select(:saved_answer_id))
        .order(created_at: :desc, id: :desc)
    end
end
