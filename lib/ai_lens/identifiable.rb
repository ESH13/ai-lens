# frozen_string_literal: true

module AiLens
  module Identifiable
    extend ActiveSupport::Concern

    included do
      # Association to identification jobs
      has_many :ai_lens_jobs,
        class_name: "AiLens::Job",
        as: :identifiable,
        dependent: :destroy

      # Class-level configuration
      class_attribute :_identifiable_photos_method, instance_writer: false
      class_attribute :_identifiable_mapping, instance_writer: false, default: {}
      class_attribute :_identifiable_schema, instance_writer: false
      class_attribute :_identifiable_callbacks, instance_writer: false, default: {}
    end

    class_methods do
      # Configure which association provides the photos
      # Example: identifiable_photos :photos
      def identifiable_photos(association_name)
        self._identifiable_photos_method = association_name
      end

      # Configure mapping from extracted attributes to model attributes
      # Example: identifiable_mapping(name: :title, category: :item_category)
      def identifiable_mapping(mapping = {})
        self._identifiable_mapping = mapping.with_indifferent_access
      end

      # Define a custom schema for this model
      # Uses instance_eval for DSL - standard Ruby pattern for schema definition
      # Example:
      #   define_schema do |s|
      #     s.field :name, type: :string, required: true
      #     s.field :year, type: :integer
      #   end
      def define_schema(name: nil, description: nil, &block)
        schema = Schema.new(name: name, description: description)
        schema.instance_eval(&block) if block_given?  # rubocop:disable Security/Eval -- instance_eval is not eval
        self._identifiable_schema = schema
      end

      # Register lifecycle callbacks
      # Example:
      #   before_identify -> (item) { item.credits.any? }
      #   after_identify -> (item, job) { broadcast_update(item) }
      #   on_success -> (item, job) { notify_user(item) }
      #   on_failure -> (item, job, error) { log_error(error) }
      def before_identify(callback = nil, &block)
        register_callback(:before_identify, callback || block)
      end

      def after_identify(callback = nil, &block)
        register_callback(:after_identify, callback || block)
      end

      def on_success(callback = nil, &block)
        register_callback(:on_success, callback || block)
      end

      def on_failure(callback = nil, &block)
        register_callback(:on_failure, callback || block)
      end

      def on_stage_change(method_name = nil, &block)
        _add_callback(:on_stage_change, method_name || block)
      end

      private

      def _add_callback(type, callback)
        register_callback(type, callback)
      end

      def register_callback(type, callback)
        callbacks = (_identifiable_callbacks[type] || []).dup
        callbacks << callback
        self._identifiable_callbacks = _identifiable_callbacks.merge(type => callbacks)
      end
    end

    # Instance methods

    # Get the schema for this instance (model-level or global default)
    def identification_schema
      self.class._identifiable_schema || AiLens.configuration.schema
    end

    # Get the photos for identification
    def identification_photos
      method = self.class._identifiable_photos_method
      raise NotConfiguredError, "identifiable_photos not configured for #{self.class.name}" unless method
      send(method)
    end

    # Check if the model has photos available for identification
    def identifiable?
      identification_photos.any?
    end

    # Start an identification job
    # Options:
    #   adapter: Override the default adapter (or array of adapters for fallback chain)
    #   adapters: Array of adapters to try in order (e.g., [:openai, :anthropic, :grok])
    #   photos_mode: :single or :multiple (how to interpret multiple photos)
    #   item_mode: :single or :multiple (expect single item or multiple items in photos)
    #   user_feedback: User feedback from previous attempt for re-identification
    #   context: Additional context for the LLM
    def identify!(adapter: nil, adapters: nil, photos_mode: :single, item_mode: :single, user_feedback: nil, context: nil)
      # Multi-item mode is not implemented in 0.3.0. Fail fast before
      # creating a job or running before_identify callbacks so callers
      # don't burn credits / enqueue work that will silently behave
      # like single-item mode.
      if item_mode.to_sym == :multiple
        raise AiLens::NotImplementedError,
          "Multi-item mode is not implemented in 0.3.0. " \
          "Pass `item_mode: :single` (default) to identify each photo's primary item."
      end

      # Run before_identify callbacks - can prevent identification by returning false
      unless run_identification_callbacks(:before_identify)
        return nil
      end

      # Determine primary adapter and fallback chain
      if adapters.is_a?(Array) && adapters.any?
        primary_adapter = adapters.first
        # Store the full chain in configuration for the job to use
        fallback_chain = adapters[1..]
      else
        primary_adapter = adapter || AiLens.configuration.default_adapter
        fallback_chain = AiLens.configuration.fallback_adapters
      end

      # Create the job record
      job = ai_lens_jobs.create!(
        adapter: primary_adapter,
        photos_mode: photos_mode,
        item_mode: item_mode,
        user_feedback: user_feedback,
        context: context,
        schema_snapshot: identification_schema.to_json_schema,
        status: :pending
      )

      # Store fallback chain in job's error_details for recovery use
      job.update!(error_details: { fallback_adapters: fallback_chain }) if fallback_chain&.any?

      # Enqueue the background job
      ProcessIdentificationJob.perform_later(job)

      # Run after_identify callbacks
      run_identification_callbacks(:after_identify, job)

      job
    end

    # Check if currently identifying
    def identifying?
      ai_lens_jobs.pending_or_processing.exists?
    end

    # Check if ever identified
    def identified?
      ai_lens_jobs.completed.exists?
    end

    # Get the most recent successful job
    def latest_identification
      ai_lens_jobs.completed.order(completed_at: :desc).first
    end

    # Apply extracted attributes from a job to this model.
    #
    # Only keys declared in the identification schema are considered. Non-schema
    # keys returned by the LLM (e.g. "photo_tags", "items") are ignored, even
    # if the host model happens to have a writer of the same name. This prevents
    # LLM output from silently overwriting unrelated host-model state.
    def apply_identification!(job)
      return false unless job.status_completed?

      mapping = self.class._identifiable_mapping
      extracted = job.parsed_extracted_attributes

      return false if extracted.blank?

      schema_keys = identification_schema.field_names.map(&:to_s).to_set
      attributes_to_update = {}

      extracted.each do |key, value|
        next unless schema_keys.include?(key.to_s)

        # Use mapping if defined, otherwise try direct attribute name
        target_attribute = mapping[key.to_s] || mapping[key.to_sym] || key

        if respond_to?("#{target_attribute}=")
          attributes_to_update[target_attribute] = value
        end
      end

      update!(attributes_to_update) if attributes_to_update.any?
      true
    end

    # Photo tag sets from the latest identification
    def photo_tag_sets
      latest_identification&.photo_tag_sets || []
    end

    def photo_tags_for(photo_or_index)
      index = photo_or_index.is_a?(Integer) ? photo_or_index : identification_photos.to_a.index(photo_or_index)
      latest_identification&.photo_tags_for(index)
    end

    # Run identification callbacks of a specific type
    # Named run_identification_callbacks to avoid conflicting with ActiveRecord's run_callbacks
    def run_identification_callbacks(type, *args)
      callbacks = self.class._identifiable_callbacks[type] || []

      callbacks.each do |callback|
        result = if callback.is_a?(Symbol)
          send(callback, *args)
        elsif callback.respond_to?(:call)
          callback.call(self, *args)
        end

        # For before_identify, returning false prevents the operation
        if type == :before_identify && result == false
          return false
        end
      end

      true
    end

    class NotConfiguredError < StandardError; end
  end
end
