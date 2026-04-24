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
end
