# frozen_string_literal: true

require "ai_loom"

require_relative "ai_lens/version"
require_relative "ai_lens/configuration"
require_relative "ai_lens/schema"
require_relative "ai_lens/schema_field"

module AiLens
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

    # Default schema for collectibles
    def default_schema
      @default_schema ||= Schema.new.tap do |s|
        s.field :name, type: :string, description: "The name or title of the item"
        s.field :category, type: :string, description: "Primary category (e.g., 'Trading Card', 'Coin', 'Stamp', 'Figurine')"
        s.field :subcategory, type: :string, description: "Subcategory within the main category"
        s.field :brand, type: :string, description: "Manufacturer, brand, or issuing authority"
        s.field :year, type: :integer, description: "Year of manufacture or release"
        s.field :condition, type: :string, description: "Condition assessment (e.g., 'Mint', 'Near Mint', 'Good', 'Fair', 'Poor')"
        s.field :rarity, type: :string, description: "Rarity level (e.g., 'Common', 'Uncommon', 'Rare', 'Ultra Rare')"
        s.field :description, type: :text, description: "Detailed description of the item"
        s.field :estimated_value_low, type: :decimal, description: "Low estimate of market value in USD"
        s.field :estimated_value_high, type: :decimal, description: "High estimate of market value in USD"
        s.field :confidence_score, type: :float, description: "Confidence in the identification (0.0 to 1.0)"
        s.field :identifying_features, type: :array, description: "List of key identifying features"
        s.field :notes, type: :text, description: "Additional notes or observations"
      end
    end
  end
end

# Require files that depend on AiLens.configuration after the module is defined
require_relative "ai_lens/prompt_builder"
require_relative "ai_lens/identifiable"
require_relative "ai_lens/process_identification_job"
require_relative "ai_lens/recover_stuck_jobs_job"

require_relative "ai_lens/engine" if defined?(Rails::Engine)
