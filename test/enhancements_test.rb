# frozen_string_literal: true

require "test_helper"

class EnhancedSchemaTest < Minitest::Test
  def setup
    # Reset cached default schema
    AiLens.instance_variable_set(:@default_schema, nil)
  end

  def test_default_schema_has_manufacturer
    schema = AiLens.default_schema
    assert schema.has_field?(:manufacturer)
    assert_equal :string, schema[:manufacturer].type
  end

  def test_default_schema_has_series
    schema = AiLens.default_schema
    assert schema.has_field?(:series)
    assert_equal :string, schema[:series].type
  end

  def test_default_schema_has_variant
    schema = AiLens.default_schema
    assert schema.has_field?(:variant)
    assert_equal :string, schema[:variant].type
  end

  def test_default_schema_has_counterfeit_risk
    schema = AiLens.default_schema
    assert schema.has_field?(:counterfeit_risk)
    assert_equal :float, schema[:counterfeit_risk].type
  end

  def test_default_schema_has_featured_photo_index
    schema = AiLens.default_schema
    assert schema.has_field?(:featured_photo_index)
    assert_equal :integer, schema[:featured_photo_index].type
  end

  def test_category_has_enum_values
    schema = AiLens.default_schema
    category = schema[:category]
    assert category.has_enum?
    assert_includes category.enum_values, "trading_card"
    assert_includes category.enum_values, "pokemon_card"
    assert_includes category.enum_values, "sneakers"
    assert_includes category.enum_values, "other"
  end

  def test_condition_has_enum_values
    schema = AiLens.default_schema
    condition = schema[:condition]
    assert condition.has_enum?
    assert_equal %w[mint near_mint excellent good fair poor], condition.enum_values
  end
end

class EnhancedConfigurationTest < Minitest::Test
  def setup
    @config = AiLens::Configuration.new
  end

  def test_task_defaults_to_nil
    assert_nil @config.task
  end

  def test_task_is_settable
    @config.task = :identification
    assert_equal :identification, @config.task
  end

  def test_open_photo_tags_defaults_to_false
    refute @config.open_photo_tags
  end

  def test_photo_tag_threshold_defaults_to_0_3
    assert_in_delta 0.3, @config.photo_tag_threshold
  end

  def test_photo_tag_facets_returns_built_in_facets
    facets = @config.photo_tag_facets
    assert_includes facets.keys, :identifier
    assert_includes facets.keys, :showcase
    assert_includes facets.keys, :detail
    assert_includes facets.keys, :context
    assert_includes facets.keys, :damage
    assert_includes facets.keys, :documentation
  end

  def test_add_photo_tag_facet
    @config.add_photo_tag_facet(:custom_tag, "A custom description")
    facets = @config.photo_tag_facets
    assert_includes facets.keys, :custom_tag
    assert_equal "A custom description", facets[:custom_tag]
  end

  def test_add_photo_tag_facet_with_string_name
    @config.add_photo_tag_facet("string_tag", "Description")
    assert_includes @config.photo_tag_facets.keys, :string_tag
  end

  def test_custom_facets_merge_with_built_in
    @config.add_photo_tag_facet(:special, "Special facet")
    facets = @config.photo_tag_facets
    # Should have both built-in and custom
    assert facets.size > AiLens::Configuration::BUILT_IN_FACETS.size
    assert_includes facets.keys, :identifier  # built-in
    assert_includes facets.keys, :special     # custom
  end
end

class PromptBuilderPhotoTagsTest < Minitest::Test
  def setup
    @schema = AiLens::Schema.define(name: "Test") do
      field :name, type: :string, required: true, description: "Item name"
    end
    AiLens.reset_configuration!
  end

  def teardown
    AiLens.reset_configuration!
  end

  def test_build_includes_photo_tag_instructions
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.build

    assert_includes prompt, "tag facets"
    assert_includes prompt, "identifier"
    assert_includes prompt, "showcase"
    assert_includes prompt, "photo_tags"
  end

  def test_photo_tag_instructions_includes_threshold
    AiLens.configuration.photo_tag_threshold = 0.5
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.build

    assert_includes prompt, "0.5"
  end

  def test_photo_tag_instructions_includes_custom_facets
    AiLens.configuration.add_photo_tag_facet(:rarity_indicator, "Shows rarity markers")
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.build

    assert_includes prompt, "rarity_indicator"
    assert_includes prompt, "Shows rarity markers"
  end

  def test_photo_tag_instructions_with_open_tags_enabled
    AiLens.configuration.open_photo_tags = true
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.build

    assert_includes prompt, "open_tags"
  end

  def test_photo_tag_instructions_without_open_tags
    AiLens.configuration.open_photo_tags = false
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.send(:photo_tag_instructions)

    refute_includes prompt, "open_tags"
  end
end

class StageTrackingTest < Minitest::Test
  def test_job_stages_constant
    # AiLens::Job is an ActiveRecord model, so we check the constant is defined
    # by reading the source directly
    stages = %w[queued encoding analyzing extracting validating applying completed]
    job_source = File.read(File.expand_path("../app/models/ai_lens/job.rb", __dir__))
    stages.each do |stage|
      assert_includes job_source, stage, "Job source should include stage '#{stage}'"
    end
    assert_includes job_source, "STAGES"
    assert_includes job_source, "update_stage!"
    assert_includes job_source, "current_stage"
  end
end
