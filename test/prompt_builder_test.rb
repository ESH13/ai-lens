# frozen_string_literal: true

require "test_helper"

class PromptBuilderTest < Minitest::Test
  def setup
    @schema = AiLens::Schema.define(name: "Test") do
      field :name, type: :string, required: true, description: "Item name"
      field :category, type: :string, description: "Item category"
    end
  end

  def test_build_system_prompt
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.system_prompt

    assert_includes prompt, "expert"
    assert_includes prompt, "JSON"
  end

  def test_build_user_prompt
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.build

    assert_includes prompt, "name"
    assert_includes prompt, "category"
    assert_includes prompt, "Item name"
  end

  def test_user_prompt_with_feedback
    builder = AiLens::PromptBuilder.new(schema: @schema, user_feedback: "This is a vintage item")
    prompt = builder.build

    assert_includes prompt, "vintage item"
  end

  def test_user_prompt_with_context
    builder = AiLens::PromptBuilder.new(schema: @schema, context: "Collection of toys")
    prompt = builder.build

    assert_includes prompt, "Collection of toys"
  end

  def test_includes_field_descriptions
    builder = AiLens::PromptBuilder.new(schema: @schema)
    prompt = builder.build

    assert_includes prompt, "Item name"
    assert_includes prompt, "Item category"
  end

  def test_template_context_exposes_photo_tag_instructions
    schema = AiLens::Schema.define(name: "test") { |s| s.field :name, type: :string }
    ctx = AiLens::PromptBuilder::TemplateContext.new(
      schema: schema,
      schema_description: "Extract: name",
      schema_fields: schema.fields,
      has_feedback: false,
      has_context: false,
      photos_mode: :single,
      item_mode: :single
    )

    result = ctx.photo_tag_instructions

    assert_includes result, "Tag Facets:"
    assert_includes result, "identifier:"
    assert_includes result, "showcase:"
    assert_includes result, "photo_tags"
  end

  def test_template_context_include_photo_tags_query
    schema = AiLens::Schema.define(name: "test") { |s| s.field :name, type: :string }
    ctx = AiLens::PromptBuilder::TemplateContext.new(
      schema: schema, schema_description: "x", schema_fields: schema.fields,
      has_feedback: false, has_context: false, photos_mode: :single, item_mode: :single
    )

    assert ctx.include_photo_tags?
  end
end
