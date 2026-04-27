# frozen_string_literal: true

module AiLens
  class Job < ActiveRecord::Base
    self.table_name = "ai_lens_jobs"

    STAGES = %w[queued encoding analyzing extracting validating applying completed].freeze

    belongs_to :identifiable, polymorphic: true
    has_many :feedbacks, class_name: "AiLens::Feedback", dependent: :destroy

    enum :status, {
      pending: "pending",
      processing: "processing",
      completed: "completed",
      failed: "failed"
    }, prefix: true

    enum :photos_mode, {
      single: "single",
      multiple: "multiple"
    }, default: :single, prefix: true

    enum :item_mode, {
      single: "single",
      multiple: "multiple"
    }, default: :single, prefix: true

    # Scopes
    scope :pending_or_processing, -> { where(status: [:pending, :processing]) }
    scope :recent, -> { order(created_at: :desc) }
    scope :completed, -> { where(status: :completed) }
    scope :failed, -> { where(status: :failed) }
    scope :stuck, -> { where(status: [:pending, :processing]).where("created_at < ?", AiLens.configuration.stuck_job_threshold.ago) }

    # Callbacks
    before_create :set_defaults

    # Encrypt sensitive data only if the host app has configured Active Record
    # encryption credentials. This makes encryption opt-in for host apps that
    # don't use Active Record Encryption.
    if defined?(Rails) && Rails.application&.config&.active_record&.encryption&.primary_key.present?
      encrypts :llm_results
      encrypts :extracted_attributes
      encrypts :user_feedback
    end

    # Note: schema_snapshot and error_details are native JSON columns
    # No serialize needed - Rails handles JSON natively

    # Validations
    validates :status, presence: true
    validates :adapter, presence: true

    # Stage tracking
    def update_stage!(stage)
      update!(current_stage: stage)
      identifiable&.run_identification_callbacks(:on_stage_change, self, stage) if identifiable&.respond_to?(:run_identification_callbacks)
    end

    # Mark job as processing
    def start_processing!
      update!(
        status: :processing,
        started_at: Time.current
      )
    end

    # Mark job as completed with results
    # extracted_attributes: Hash of extracted data
    # llm_results: Raw response from the LLM (encrypted)
    def complete!(extracted_attributes:, llm_results: nil)
      # Convert to JSON string for encrypted storage
      self.extracted_attributes = extracted_attributes.is_a?(Hash) ? extracted_attributes.to_json : extracted_attributes
      self.llm_results = llm_results.is_a?(Hash) ? llm_results.to_json : llm_results

      update!(
        status: :completed,
        completed_at: Time.current
      )

      # Auto-apply extracted attributes to identifiable (always on success per plan)
      if identifiable.respond_to?(:apply_identification!)
        identifiable.apply_identification!(self)
      end

      # Run success callbacks
      identifiable.run_identification_callbacks(:on_success, self) if identifiable.respond_to?(:run_identification_callbacks)
    end

    # Mark job as failed
    def fail!(error_message:, error_details: nil)
      update!(
        status: :failed,
        error_message: error_message,
        error_details: error_details,
        completed_at: Time.current
      )

      # Run failure callbacks
      if identifiable.respond_to?(:run_identification_callbacks)
        identifiable.run_identification_callbacks(:on_failure, self, error_message)
      end
    end

    # Duration in seconds
    def duration
      return nil unless started_at && completed_at
      completed_at - started_at
    end

    # Check if this is a retry of a previous job
    def retry?
      user_feedback.present?
    end

    # Parse extracted_attributes from encrypted JSON string
    def parsed_extracted_attributes
      return {} if extracted_attributes.blank?
      JSON.parse(extracted_attributes)
    rescue JSON::ParserError
      {}
    end

    # Parse llm_results from encrypted JSON string
    def parsed_llm_results
      return {} if llm_results.blank?
      JSON.parse(llm_results)
    rescue JSON::ParserError
      {}
    end

    # Photo tag sets from LLM results
    def photo_tag_sets
      @photo_tag_sets ||= parsed_photo_tags.map do |entry|
        AiLens::PhotoTagSet.new(
          photo_index: entry["photo_index"],
          tags: entry["tags"] || [],
          open_tags: entry["open_tags"] || []
        )
      end
    end

    def photo_tags_for(index)
      photo_tag_sets.find { |pts| pts.photo_index == index }
    end

    # Get adapters to try (configured fallback chain)
    def adapters_to_try
      adapters = [adapter.to_sym]
      adapters += AiLens.configuration.fallback_adapters
      adapters.uniq
    end

    private

    # photo_tags is emitted by the LLM inside its JSON content (which lands in
    # extracted_attributes), not in the provider envelope (llm_results). Read
    # it from extracted_attributes; fall back to llm_results for legacy rows
    # written by the previous wiring.
    def parsed_photo_tags
      attrs = parsed_extracted_attributes
      tags = attrs["photo_tags"] || attrs[:photo_tags]
      return tags if tags.is_a?(Array)

      legacy = parsed_llm_results
      legacy["photo_tags"] || legacy[:photo_tags] || []
    end

    def set_defaults
      self.status ||= :pending
    end
  end
end
