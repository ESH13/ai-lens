# frozen_string_literal: true

require "ai_loom"

require_relative "ai_lens/version"
require_relative "ai_lens/configuration"
require_relative "ai_lens/schema"
require_relative "ai_lens/schema_field"
require_relative "ai_lens/schemas/collectibles"
require_relative "ai_lens/photo_tag_set"

module AiLens
  # Base class for all AiLens errors. Host apps can rescue AiLens::Error
  # to catch any gem-specific failure.
  class Error < StandardError; end

  # Raised when a feature is requested that is not implemented in the
  # current version (e.g. item_mode: :multiple in 0.3.0).
  class NotImplementedError < Error; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end

    # Minimal default schema — name + description + freeform category +
    # notes. Suitable for any "tell me about this photo" use case.
    # Hosts that want the richer collectibles schema (rarity, condition,
    # estimated value, etc.) can opt in via AiLens::Schemas::Collectibles.
    #
    # Reset between configurations with reset_default_schema!.
    def default_schema
      @default_schema ||= Schema.new(
        name: "default",
        description: "Generic photo identification — name + freeform category + notes."
      ).tap do |s|
        s.field :name, type: :string, description: "The name or title of the item"
        s.field :description, type: :text, description: "Detailed description of the item"
        s.field :category, type: :string, description: "Freeform category (no enum)"
        s.field :notes, type: :text, description: "Additional notes or observations"
      end
    end

    # Test/dev helper: clear the cached default_schema so a subsequent
    # call rebuilds it. Useful when tests mutate the schema.
    def reset_default_schema!
      @default_schema = nil
    end
  end
end

# Require files that depend on AiLens.configuration after the module is defined
require_relative "ai_lens/prompt_builder"
require_relative "ai_lens/identifiable"
require_relative "ai_lens/process_identification_job"
require_relative "ai_lens/recover_stuck_jobs_job"

require_relative "ai_lens/engine" if defined?(Rails::Engine)
