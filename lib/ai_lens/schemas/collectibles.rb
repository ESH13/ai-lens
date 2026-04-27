# frozen_string_literal: true

module AiLens
  module Schemas
    # The 17-field collectibles schema that ships with ai-lens. Until
    # 0.3.0 this was the gem's default schema, which baked Grailsome-
    # specific assumptions (trading_card, pokemon_card, watch, etc.)
    # into every host. 0.3.0 trims the default to a 4-field generic
    # schema and exposes this richer schema as an opt-in module.
    #
    # Usage from a host model:
    #
    #   class Item < ApplicationRecord
    #     include AiLens::Identifiable
    #     identifiable_photos :photos
    #     define_schema(&AiLens::Schemas::Collectibles.method(:apply))
    #   end
    #
    # Or globally:
    #
    #   AiLens.configure do |c|
    #     c.default_schema = AiLens::Schemas::Collectibles.build
    #   end
    module Collectibles
      module_function

      # Apply the 17 collectibles fields to a Schema instance via the
      # define_schema DSL. Used like:
      #   define_schema(&AiLens::Schemas::Collectibles.method(:apply))
      def apply(schema = nil)
        target = schema || self
        target.field :name, type: :string, description: "The name or title of the item"
        target.field :category, type: :string, description: "Primary category",
          enum: %w[trading_card pokemon_card sports_card mtg_card yugioh_card coin stamp
                   comic_book vinyl_record action_figure funko_pop lego_set board_game
                   video_game sneakers watch jewelry handbag art_print figurine diecast_car
                   plush ornament pottery antique memorabilia autograph book instrument other]
        target.field :subcategory, type: :string, description: "Subcategory within the main category"
        target.field :manufacturer, type: :string, description: "Manufacturer or brand name"
        target.field :series, type: :string, description: "Series, collection, or product line"
        target.field :variant, type: :string, description: "Specific variant, edition, or colorway"
        target.field :brand, type: :string, description: "Manufacturer, brand, or issuing authority"
        target.field :year, type: :integer, description: "Year of manufacture or release"
        target.field :condition, type: :string, description: "Condition assessment",
          enum: %w[mint near_mint excellent good fair poor]
        target.field :rarity, type: :string, description: "Rarity level (e.g., 'Common', 'Uncommon', 'Rare', 'Ultra Rare')"
        target.field :description, type: :text, description: "Detailed description of the item"
        target.field :estimated_value_low, type: :decimal, description: "Low estimate of market value in USD"
        target.field :estimated_value_high, type: :decimal, description: "High estimate of market value in USD"
        target.field :confidence_score, type: :float, description: "Confidence in the identification (0.0 to 1.0)"
        target.field :counterfeit_risk, type: :float, description: "Counterfeit risk score (0.0-1.0)"
        target.field :featured_photo_index, type: :integer, description: "Index of the best photo for display"
        target.field :identifying_features, type: :array, description: "List of key identifying features"
        target.field :notes, type: :text, description: "Additional notes or observations"
        target
      end

      # Build a standalone Schema with the collectibles fields. Useful
      # for setting AiLens.configuration.default_schema.
      def build
        AiLens::Schema.new(
          name: "collectibles",
          description: "Rich schema for collectibles, antiques, and memorabilia."
        ).tap { |s| apply(s) }
      end
    end
  end
end
