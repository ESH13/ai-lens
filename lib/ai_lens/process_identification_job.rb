# frozen_string_literal: true

module AiLens
  class ProcessIdentificationJob < ActiveJob::Base
    queue_as { AiLens.configuration.queue_name }

    # ActiveJob's `retry_on` evaluates `attempts:` once at class-load time,
    # so `attempts: AiLens.configuration.max_retries` would freeze the
    # value before any host-app initializer ran, and procs aren't
    # accepted there (the runtime check is `executions < attempts`, a
    # strict integer comparison). Procs ARE accepted by `wait:`, but we
    # need a single source of truth for both knobs, so retry/discard
    # decisions are made in the per-error rescue inside `perform` and
    # this class declares no `retry_on` directives.

    discard_on AiLoom::AuthenticationError

    # Runtime accessors for retry tuning. Read at perform / retry time so
    # changes made in a host-app initializer take effect.
    def self.configured_max_retries
      AiLens.configuration.max_retries
    end

    def self.configured_retry_delay
      AiLens.configuration.retry_delay
    end

    def perform(job)
      return if job.status_completed? || job.status_failed?

      job.update_stage!("queued")
      # If another worker won the race to claim this job, bail out. The
      # winner is responsible for advancing it.
      return unless job.start_processing!

      begin
        # Get the identifiable record
        identifiable = job.identifiable

        # Get photos as image URLs (using variants for preprocessing)
        job.update_stage!("encoding")
        image_urls = prepare_images(identifiable)

        if image_urls.empty?
          job.fail!(error_message: "No photos available for identification")
          return
        end

        # Build the prompt with mode support
        schema = identifiable.identification_schema
        prompt_builder = PromptBuilder.new(
          schema: schema,
          context: job.context,
          user_feedback: job.user_feedback,
          photos_mode: job.photos_mode,
          item_mode: job.item_mode
        )
        prompt = prompt_builder.build

        # Get the adapter and make the API call
        job.update_stage!("analyzing")
        adapter = get_adapter_for_job(job)
        response = adapter.analyze_with_images(
          prompt: prompt,
          image_urls: image_urls,
          system_prompt: prompt_builder.system_prompt
        )

        job.update_stage!("extracting")

        if response.success?
          extracted = response.json_content || {}

          job.update_stage!("validating")
          job.update_stage!("applying")
          job.complete!(
            extracted_attributes: extracted,
            llm_results: response.raw_response
          )
          job.update_stage!("completed")
        else
          # Try fallback adapters from the job's configured chain
          try_fallback_adapters(job, identifiable, image_urls, prompt_builder)
        end
      rescue AiLoom::RateLimitError => e
        retry_or_fail(job, e, wait: polynomial_backoff_seconds)
      rescue AiLoom::TimeoutError => e
        retry_or_fail(job, e, wait: self.class.configured_retry_delay)
      rescue AiLoom::AdapterError => e
        # Try fallback adapters before failing
        if try_fallback_adapters(job, job.identifiable, nil, nil, primary_error: e)
          return
        end

        job.fail!(
          error_message: e.message,
          error_details: { error_class: e.class.name }
        )
      rescue => e
        job.fail!(
          error_message: "Unexpected error: #{e.message}",
          error_details: {
            error_class: e.class.name,
            backtrace: e.backtrace&.first(10)
          }
        )
      end
    end

    private

    # Re-enqueue the job for another attempt, or fail it if the runtime-
    # configured max_retries has been exhausted. `executions` (provided by
    # ActiveJob) is 1 on first execution, 2 on first retry, etc.
    def retry_or_fail(job, error, wait:)
      if executions < self.class.configured_max_retries
        retry_job(wait: wait, error: error)
      else
        job.fail!(
          error_message: error.message,
          error_details: { error_class: error.class.name, attempts: executions }
        )
      end
    end

    # Same polynomial backoff curve ActiveJob's `:polynomially_longer` uses,
    # so the visible behavior matches the previous declaration: ~3s, ~18s,
    # ~83s, ...
    def polynomial_backoff_seconds
      (executions**4) + 2
    end

    def prepare_images(identifiable)
      photos = identifiable.identification_photos
      max_photos = AiLens.configuration.max_photos

      photos.first(max_photos).map do |photo|
        encode_photo(photo)
      end.compact
    end

    def encode_photo(photo)
      # Handle ActiveStorage attachments with variant preprocessing
      if photo.respond_to?(:variant) && photo.respond_to?(:download)
        variant_options = AiLens.configuration.image_variant_options

        # Use variant for preprocessing (resize, format conversion)
        if variant_options.present?
          begin
            # Get the variant and download it
            variant = photo.variant(variant_options)
            # Process the variant to get the actual blob
            processed = variant.processed
            # Use the format from variant options if specified, otherwise use original content_type
            # This ensures HEIC images converted to JPEG have the correct content type
            content_type = if variant_options[:format]
              "image/#{variant_options[:format]}"
            else
              photo.content_type || "image/jpeg"
            end
            AiLoom::ImageEncoder.encode_data(processed.download, content_type: content_type)
          rescue => e
            # Fall back to original if variant fails
            logger.warn "[AiLens] Variant processing failed, using original: #{e.message}"
            content_type = photo.content_type || "image/jpeg"
            AiLoom::ImageEncoder.encode_data(photo.download, content_type: content_type)
          end
        else
          content_type = photo.content_type || "image/jpeg"
          AiLoom::ImageEncoder.encode_data(photo.download, content_type: content_type)
        end
      elsif photo.respond_to?(:download)
        # ActiveStorage attachment without variant support
        content_type = photo.content_type || "image/jpeg"
        AiLoom::ImageEncoder.encode_data(photo.download, content_type: content_type)
      elsif photo.respond_to?(:url)
        # Handle URL-based photos
        photo.url
      elsif photo.is_a?(String)
        # Handle file paths or URLs
        AiLoom::ImageEncoder.normalize(photo)
      else
        nil
      end
    rescue => e
      logger.error "[AiLens] Failed to encode photo: #{e.message}"
      nil
    end

    def get_adapter(name)
      AiLoom.adapter(name)
    end

    def get_adapter_for_job(job)
      config = AiLens.configuration
      if config.task && defined?(AiLoom) && AiLoom.respond_to?(:router)
        begin
          return AiLoom.router.for(config.task)
        rescue AiLoom::AdapterError
          # Fall through to default adapter selection
        end
      end
      get_adapter(job.adapter.to_sym)
    end

    def try_fallback_adapters(job, identifiable, image_urls, prompt_builder, primary_error: nil)
      # Get fallback chain from job's error_details or configuration
      fallback_adapters = job.error_details&.dig("fallback_adapters") ||
                          job.error_details&.dig(:fallback_adapters) ||
                          AiLens.configuration.fallback_adapters

      tried_adapter = job.adapter.to_sym
      tried_adapters = [tried_adapter]

      Array(fallback_adapters).each do |fallback_name|
        fallback_sym = fallback_name.to_sym
        next if tried_adapters.include?(fallback_sym)
        tried_adapters << fallback_sym

        begin
          logger.info "[AiLens] Trying fallback adapter: #{fallback_name}"

          # Re-prepare images if not provided
          image_urls ||= prepare_images(identifiable)

          # Re-build prompt if not provided
          if prompt_builder.nil?
            schema = identifiable.identification_schema
            prompt_builder = PromptBuilder.new(
              schema: schema,
              context: job.context,
              user_feedback: job.user_feedback,
              photos_mode: job.photos_mode,
              item_mode: job.item_mode
            )
          end
          prompt = prompt_builder.build

          adapter = get_adapter(fallback_sym)
          response = adapter.analyze_with_images(
            prompt: prompt,
            image_urls: image_urls,
            system_prompt: prompt_builder.system_prompt
          )

          if response.success?
            extracted = response.json_content || {}

            # Update the adapter used and record tried adapters
            job.update!(
              adapter: fallback_name.to_s,
              error_details: (job.error_details || {}).merge("tried_adapters" => tried_adapters.map(&:to_s))
            )

            job.complete!(
              extracted_attributes: extracted,
              llm_results: response.raw_response
            )

            return true
          end
        rescue AiLoom::AdapterError => e
          logger.warn "[AiLens] Fallback #{fallback_name} failed: #{e.message}"
          # Continue to next fallback
        end
      end

      false
    end

    def logger
      AiLens.configuration.logger
    end
  end
end
