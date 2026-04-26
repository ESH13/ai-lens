# frozen_string_literal: true

module AiLens
  class Feedback < ActiveRecord::Base
    self.table_name = "ai_lens_feedbacks"

    belongs_to :job, class_name: "AiLens::Job"

    # Allow controller to indicate it will handle reidentification manually.
    # Note: do NOT shadow the `reidentify_requested` DB column with an
    # attr_accessor — host apps may rely on persisting that column. The
    # signal to suppress auto-reidentification is `skip_auto_reidentify`.
    attr_accessor :skip_auto_reidentify

    # Encrypt the comments field (may contain sensitive user data) only if
    # the host app has configured Active Record encryption credentials.
    if defined?(Rails) && Rails.application&.config&.active_record&.encryption&.primary_key.present?
      encrypts :comments
    end

    # Note: suggested_corrections is a native JSON column in the database
    # No serialize needed - Rails 8+ handles JSON columns natively

    validates :helpful, inclusion: { in: [true, false] }

    # After creating feedback, trigger re-identification with the feedback
    # Skip if host app sets reidentify_requested (they'll handle it manually)
    after_create_commit :trigger_reidentification, if: :should_auto_reidentify?

    # Scopes
    scope :helpful, -> { where(helpful: true) }
    scope :not_helpful, -> { where(helpful: false) }
    scope :with_corrections, -> { where.not(suggested_corrections: [nil, {}, ""]) }
    scope :recent, -> { order(created_at: :desc) }

    # Build feedback text for re-identification
    def feedback_text
      parts = []

      if comments.present?
        parts << "User comments: #{comments}"
      end

      if suggested_corrections.present? && suggested_corrections.any?
        corrections = suggested_corrections.map do |field, value|
          "#{field}: #{value}"
        end.join(", ")
        parts << "Suggested corrections: #{corrections}"
      end

      parts.join("\n")
    end

    private

    def should_auto_reidentify?
      # Skip auto-reidentification if host app will handle it manually
      return false if skip_auto_reidentify

      # Re-identify if user marked as not helpful or provided corrections
      !helpful? || suggested_corrections.present?
    end

    def trigger_reidentification
      return unless job.identifiable.present?

      identifiable = job.identifiable

      # Build combined feedback from this and any previous feedback
      combined_feedback = build_combined_feedback

      # Trigger new identification with the feedback
      identifiable.identify!(
        adapter: job.adapter,
        photos_mode: job.photos_mode,
        item_mode: job.item_mode,
        user_feedback: combined_feedback,
        context: job.context
      )
    end

    def build_combined_feedback
      # Get all feedback for this job's identifiable
      all_feedbacks = Feedback
        .joins(:job)
        .where(ai_lens_jobs: { identifiable: job.identifiable })
        .order(created_at: :desc)
        .limit(5)

      all_feedbacks.map(&:feedback_text).reject(&:blank?).join("\n\n")
    end
  end
end
