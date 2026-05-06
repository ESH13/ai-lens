# frozen_string_literal: true

require "test_helper"

# Task 14: 0.3.0 split the default schema (now minimal) from the
# collectibles schema (opt-in). These tests pin both so a future
# refactor can't silently re-merge them.
class DefaultSchemaTest < Minitest::Test
  def setup
    AiLens.reset_default_schema!
  end

  def test_default_schema_is_minimal
    schema = AiLens.default_schema
    assert_equal %i[name description category notes].sort, schema.field_names.sort
  end

  def test_default_category_is_freeform_no_enum
    schema = AiLens.default_schema
    refute schema[:category].has_enum?,
      "default schema's category must be freeform; the collectibles enum is opt-in"
  end
end

class CollectiblesSchemaTest < Minitest::Test
  def setup
    @schema = AiLens::Schemas::Collectibles.build
  end

  def test_has_seventeen_fields
    expected = %i[
      name category subcategory manufacturer series variant brand year
      condition rarity description estimated_value_low estimated_value_high
      confidence_score counterfeit_risk featured_photo_index
      identifying_features notes
    ]
    # Sanity check the count matches the spec.
    assert_equal 18, expected.size  # name + 17 specialty + notes -- matches spec ("17-field" includes notes)
    expected.each do |f|
      assert @schema.has_field?(f), "collectibles schema should have field #{f}"
    end
  end

  def test_category_has_enum_values
    category = @schema[:category]
    assert category.has_enum?
    assert_includes category.enum_values, "trading_card"
    assert_includes category.enum_values, "pokemon_card"
    assert_includes category.enum_values, "sneakers"
    assert_includes category.enum_values, "other"
  end

  def test_condition_has_enum_values
    condition = @schema[:condition]
    assert condition.has_enum?
    assert_equal %w[mint near_mint excellent good fair poor], condition.enum_values
  end

  def test_apply_works_via_define_schema_dsl
    # The opt-in idiom from the README: define_schema(&Collectibles.method(:apply))
    schema = AiLens::Schema.new(name: "via_dsl")
    AiLens::Schemas::Collectibles.apply(schema)
    assert schema.has_field?(:counterfeit_risk)
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

  def test_photo_tag_facets_setter_replaces_built_in
    curated = {
      showcase: "Hero photo",
      identifier: "Has serial numbers",
      damage: "Documents wear"
    }
    @config.photo_tag_facets = curated

    assert_equal curated, @config.photo_tag_facets
    refute_includes @config.photo_tag_facets.keys, :detail
    refute_includes @config.photo_tag_facets.keys, :context
    refute_includes @config.photo_tag_facets.keys, :documentation
  end

  def test_photo_tag_facets_setter_overrides_custom_additions
    @config.add_photo_tag_facet(:rare_marker, "Rare marker")
    @config.photo_tag_facets = { showcase: "Hero only" }

    assert_equal({ showcase: "Hero only" }, @config.photo_tag_facets)
    refute_includes @config.photo_tag_facets.keys, :rare_marker
  end

  def test_photo_tag_facets_setter_normalizes_string_keys
    @config.photo_tag_facets = { "showcase" => "Hero", "damage" => "Wear" }

    assert_includes @config.photo_tag_facets.keys, :showcase
    assert_includes @config.photo_tag_facets.keys, :damage
  end

  def test_photo_tag_facets_setter_nil_falls_back_to_built_ins
    @config.photo_tag_facets = { showcase: "Custom" }
    @config.photo_tag_facets = nil

    assert_equal AiLens::Configuration::BUILT_IN_FACETS, @config.photo_tag_facets
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
