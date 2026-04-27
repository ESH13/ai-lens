# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def test_default_configuration
    config = AiLens::Configuration.new

    assert_equal :openai, config.default_adapter
    assert_equal [:anthropic, :grok, :gemini], config.fallback_adapters
    assert_equal 10, config.max_photos
  end

  def test_configure_block
    AiLens.configure do |config|
      config.default_adapter = :anthropic
      config.fallback_adapters = [:openai, :gemini]
      config.max_photos = 10
    end

    assert_equal :anthropic, AiLens.configuration.default_adapter
    assert_equal [:openai, :gemini], AiLens.configuration.fallback_adapters
    assert_equal 10, AiLens.configuration.max_photos

    # Reset for other tests
    AiLens.configure do |config|
      config.default_adapter = :openai
      config.fallback_adapters = [:anthropic, :grok, :gemini]
      config.max_photos = 10
    end
  end

  def test_default_schema_configuration
    AiLens.configure do |config|
      config.default_schema = AiLens::Schema.define(name: "Custom") do
        field :custom_field, type: :string
      end
    end

    assert_equal "Custom", AiLens.configuration.default_schema.name

    # Reset
    AiLens.configure do |config|
      config.default_schema = nil
    end
  end
end
