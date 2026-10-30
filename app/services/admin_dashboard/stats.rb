module AdminDashboard
  # Platform-wide totals for the founders. Every value is a count, so nothing
  # here can identify a family.
  class Stats
    FAMILY_GOAL = 4_000
    RECENT_PERIOD = 30.days

    def initialize
      @recent = RECENT_PERIOD.ago..
    end

    def family_count
      families.count
    end

    def new_family_count
      families.where(created_at: recent).count
    end

    # The signup cap counts every account, including the founders' own.
    def signup_spots_left
      limit = Account.signup_limit
      [ limit - Account.count, 0 ].max if limit
    end

    def profile_count
      Dependent.where(account: families).count
    end

    def active_family_count
      families.where(id: Document.where(created_at: recent).select(:account_id))
        .or(families.where(id: AiAssistantQuery.where(created_at: recent).select(:account_id)))
        .count
    end

    def document_count
      documents.count
    end

    def recent_upload_count
      documents.where(created_at: recent).count
    end

    def recent_question_count
      AiAssistantQuery.where(account: families, created_at: recent).count
    end

    def recent_shared_document_count
      SharedDocument.joins(:share_event).merge(ShareEvent.sent.where(account: families, sent_at: recent)).count
    end

    def failed_document_count
      documents.failed.count
    end

    private

      attr_reader :recent

      def families
        Account.with_product_access.without_super_admins
      end

      def documents
        Document.where(account: families)
      end
  end
end
