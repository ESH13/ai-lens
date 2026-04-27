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

  # Task 18: standalone image_quality / image_format /
  # max_image_dimension are wired into the variant options used for
  # ActiveStorage preprocessing.
  def test_effective_image_variant_options_derives_from_standalone_knobs
    config = AiLens::Configuration.new
    config.max_image_dimension = 1024
    config.image_quality = 70
    config.image_format = :jpeg
    config.image_variant_options = nil # unset explicit override

    options = config.effective_image_variant_options
    assert_equal [1024, 1024], options[:resize_to_limit]
    assert_equal({ quality: 70 }, options[:saver])
    assert_equal :jpeg, options[:format]
  end

  def test_explicit_image_variant_options_takes_precedence
    config = AiLens::Configuration.new
    config.max_image_dimension = 1024
    config.image_variant_options = { resize_to_limit: [4096, 4096] }

    options = config.effective_image_variant_options
    assert_equal [4096, 4096], options[:resize_to_limit],
      "explicit image_variant_options must override the derived defaults"
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
