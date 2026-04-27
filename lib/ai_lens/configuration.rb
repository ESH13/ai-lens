# frozen_string_literal: true

module AiLens
  class Configuration
    BUILT_IN_FACETS = {
      identifier: "Contains text, codes, serial numbers useful for deterministic identification",
      showcase: "Visually appealing, hero-worthy, display-quality photo",
      detail: "Close-up of specific feature, texture, flaw, or marking",
      context: "Shows scale, environment, or provenance",
      damage: "Documents wear, defects, or condition issues",
      documentation: "Paperwork, receipts, certificates, provenance docs"
    }.freeze

    # Default LLM adapter to use
    attr_accessor :default_adapter

    # Fallback adapters if primary fails
    attr_accessor :fallback_adapters

    # Default schema to use (can be overridden per model)
    attr_accessor :default_schema

    # Custom prompt template (path to YAML/ERB file, or nil for defaults)
    attr_accessor :prompt_template

    # Maximum number of photos to process per identification
    attr_accessor :max_photos

    # Job queue name
    attr_accessor :queue_name

    # Maximum retries for failed jobs
    attr_accessor :max_retries

    # Retry delay in seconds
    attr_accessor :retry_delay

    # Image processing options
    attr_accessor :max_image_dimension
    attr_accessor :image_quality
    attr_accessor :image_format

    # ActiveStorage variant options for image preprocessing
    attr_accessor :image_variant_options

    # Stuck job threshold (for recovery)
    attr_accessor :stuck_job_threshold

    # Logger
    attr_accessor :logger

    # Router integration - uses AiLoom.router.for(:task) if set
    attr_accessor :task

    # Photo tag options
    attr_accessor :open_photo_tags, :photo_tag_threshold
    attr_reader :custom_photo_tag_facets

    def initialize
      @default_adapter = :openai
      @fallback_adapters = [:anthropic, :grok, :gemini]  # Updated order per plan
      @default_schema = nil # Will use AiLens.default_schema
      @prompt_template = nil # Host app provides custom template
      @max_photos = 10  # Send all photos per plan decision
      @queue_name = :default
      @max_retries = 3
      @retry_delay = 5
      @max_image_dimension = 2048
      @image_quality = 85
      @image_format = :jpeg
      @image_variant_options = { resize_to_limit: [2048, 2048] }
      @stuck_job_threshold = 1.hour
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
      @task = nil
      @open_photo_tags = false
      @photo_tag_threshold = 0.3
      @custom_photo_tag_facets = {}
    end

    def schema
      @default_schema || AiLens.default_schema
    end

    def add_photo_tag_facet(name, description)
      @custom_photo_tag_facets[name.to_sym] = description
    end

    def photo_tag_facets
      BUILT_IN_FACETS.merge(@custom_photo_tag_facets)
    end
  end
end
