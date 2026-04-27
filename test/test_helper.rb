# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "active_support"
require "active_support/concern"
require "active_record"
require "active_job"
require "ai_lens"
require "minitest/autorun"

# In-memory SQLite for Job/Feedback model tests
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  self.verbose = false

  create_table :ai_lens_jobs do |t|
    t.references :identifiable, polymorphic: true, null: false, index: true
    t.string :adapter, null: false
    t.string :photos_mode, null: false, default: "single"
    t.string :item_mode, null: false, default: "single"
    t.text :context
    t.text :user_feedback
    t.json :schema_snapshot
    t.string :status, null: false, default: "pending"
    t.string :current_stage
    t.datetime :started_at
    t.datetime :completed_at
    t.text :extracted_attributes
    t.text :llm_results
    t.string :error_message
    t.json :error_details
    t.timestamps
  end

  create_table :ai_lens_feedbacks do |t|
    t.references :job, null: false, index: true
    t.boolean :helpful
    t.text :comments
    t.json :suggested_corrections
    t.timestamps
  end

  # Host model used for testing AiLens::Identifiable behavior
  create_table :test_items do |t|
    t.string :name
    t.string :title
    t.string :category
    t.timestamps
  end
end

# Load AR-dependent models now that the schema exists
require "ai_lens/identifiable"
require_relative "../app/models/ai_lens/job"
require_relative "../app/models/ai_lens/feedback"

# Mock AiLoom for testing without actual API calls
module AiLoom
  class << self
    def adapter(name)
      MockAdapter.new(name)
    end

    def configure
      yield Configuration.new
    end
  end

  class Configuration
    attr_accessor :openai, :anthropic, :gemini, :grok, :default_adapter
  end

  class MockAdapter
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def analyze_with_images(prompt:, image_urls:, system_prompt: nil)
      MockResponse.new(
        content: '{"name": "Test Item", "category": "Electronics", "description": "A test item"}',
        model: "mock-model",
        adapter: name
      )
    end
  end

  class MockResponse
    attr_reader :content, :model, :adapter

    def initialize(content:, model:, adapter:)
      @content = content
      @model = model
      @adapter = adapter
    end

    def success?
      !content.nil? && !content.empty?
    end

    def json_content
      JSON.parse(content)
    rescue JSON::ParserError
      nil
    end
  end

  class ImageEncoder
    def self.normalize_all(images, **options)
      images.map { |img| "data:image/jpeg;base64,mock" }
    end
  end

  class AdapterError < StandardError; end
  class AuthenticationError < AdapterError; end
  class RateLimitError < AdapterError; end
  class TimeoutError < AdapterError; end
end
