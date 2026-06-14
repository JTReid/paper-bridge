# frozen_string_literal: true

class PipelineRun < ApplicationRecord
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :user, optional: true

  has_one :pipeline_activity, dependent: :destroy
  has_one :pipeline_log, dependent: :destroy

  enum :state, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }

  def mark_processing!(message: nil)
    update_state!("processing", message: message)
  end

  def mark_completed!(message: nil)
    update_state!("completed", message: message, timestamp_column: :completed_at)
  end

  def mark_failed!(message: nil)
    update_state!("failed", message: message, timestamp_column: :failed_at)
  end

  def append_log(agent:, message:, payload: {}, event_type: nil)
    record = pipeline_log || create_pipeline_log!
    entry = {
      "agent" => agent,
      "message" => message,
      "occurred_at" => Time.current.to_i,
      "payload" => payload
    }
    entry["event_type"] = event_type if event_type.present?

    record.with_lock do
      entries = Array(record.entries)
      entries << entry
      record.update!(entries: entries)
    end

    entry
  end

  def append_activity(action:, message:, metadata: {})
    record = pipeline_activity || create_pipeline_activity!
    entry = {
      "action" => action,
      "message" => message,
      "occurred_at" => Time.current.to_i,
      "metadata" => metadata
    }

    record.with_lock do
      entries = Array(record.entries)
      entries << entry
      record.update!(entries: entries)
    end

    broadcast_activity(entry, record.entries)

    entry
  end

  def telemetry_summary(by_agent: false)
    Agentic::Telemetry::Summary.new(self, by_agent: by_agent).call
  end

  private

  def update_state!(state_value, message:, timestamp_column: nil)
    attributes = { state: state_value }
    attributes[:message] = message if message.present?
    attributes[timestamp_column] = Time.current if timestamp_column

    update!(attributes)
  end

  def broadcast_activity(entry, all_entries)
    return if user_id.blank?

    ActionCable.server.broadcast(
      "pipeline_activity_#{user_id}",
      {
        action: "add_entry",
        pipeline_run_id: id,
        state: state,
        occurred_at: entry["occurred_at"],
        entry: entry,
        entries: all_entries,
        subject: { label: activity_subject_label }
      }
    )
  end

  def activity_subject_label
    return subject.name if subject.respond_to?(:name) && subject.name.present?
    return subject.title if subject.respond_to?(:title) && subject.title.present?

    "Pipeline Run ##{id}"
  end
end
