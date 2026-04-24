# frozen_string_literal: true

module AiLens
  class Configuration
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

    # Whether to auto-apply extracted attributes on success
    attr_accessor :auto_apply

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

    def initialize
      @default_adapter = :openai
      @fallback_adapters = [:anthropic, :grok, :gemini]  # Updated order per plan
      @default_schema = nil # Will use AiLens.default_schema
      @prompt_template = nil # Host app provides custom template
      @max_photos = 10  # Send all photos per plan decision
      @auto_apply = true
      @queue_name = :default
      @max_retries = 3
      @retry_delay = 5
      @max_image_dimension = 2048
      @image_quality = 85
      @image_format = :jpeg
      @image_variant_options = { resize_to_limit: [2048, 2048] }
      @stuck_job_threshold = 1.hour
      @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
    end

    def schema
      @default_schema || AiLens.default_schema
    end
  end
end
