# frozen_string_literal: true

module AiLens
  class RecoverStuckJobsJob < ActiveJob::Base
    queue_as { AiLens.configuration.queue_name }

    # Finds and recovers jobs that have been stuck in pending/processing state
    # for longer than the configured threshold
    def perform
      stuck_jobs.find_each do |job|
        recover_job(job)
      end
    end

    private

    def stuck_jobs
      Job.stuck
    end

    def recover_job(job)
      logger.info "[AiLens] Recovering stuck job #{job.id} (#{job.status}, created #{job.created_at})"

      # Determine next adapter to try from fallback chain
      next_adapter = determine_next_adapter(job)

      if next_adapter
        # Retry with the next adapter in the chain
        retry_with_adapter(job, next_adapter)
      else
        # All adapters exhausted, mark as failed
        job.fail!(
          error_message: "All adapters exhausted after recovery attempts",
          error_details: { recovery_attempted_at: Time.current }
        )
      end
    rescue StandardError => e
      logger.error "[AiLens] Error recovering job #{job.id}: #{e.message}"
      job.fail!(
        error_message: "Recovery failed: #{e.message}",
        error_details: { exception: e.class.name, recovery_attempted_at: Time.current }
      )
    end

    def determine_next_adapter(job)
      # Get the fallback chain from job's error_details or configuration
      fallback_chain = job.error_details&.dig("fallback_adapters") ||
                       job.error_details&.dig(:fallback_adapters) ||
                       AiLens.configuration.fallback_adapters

      # Find adapters we haven't tried yet
      tried_adapters = extract_tried_adapters(job)
      available_adapters = Array(fallback_chain).map(&:to_sym) - tried_adapters

      available_adapters.first
    end

    def extract_tried_adapters(job)
      adapters = [job.adapter.to_sym]

      # Check error_details for previously tried adapters
      if job.error_details.is_a?(Hash)
        tried = job.error_details["tried_adapters"] || job.error_details[:tried_adapters]
        adapters += Array(tried).map(&:to_sym) if tried
      end

      adapters.uniq
    end

    def retry_with_adapter(job, adapter)
      # Record the attempt
      error_details = job.error_details || {}
      tried_adapters = extract_tried_adapters(job)
      tried_adapters << adapter.to_sym

      job.update!(
        status: :pending,
        adapter: adapter.to_s,
        error_message: nil,
        error_details: error_details.merge(
          "tried_adapters" => tried_adapters.map(&:to_s),
          "last_recovery_at" => Time.current
        ),
        started_at: nil
      )

      # Re-enqueue the processing job
      ProcessIdentificationJob.perform_later(job)

      logger.info "[AiLens] Retrying job #{job.id} with adapter: #{adapter}"
    end

    def logger
      AiLens.configuration.logger
    end
  end
end
