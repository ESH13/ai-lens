# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "active_support"
require "active_support/concern"
require "active_job"
require "ai_lens"
require "minitest/autorun"

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
