# frozen_string_literal: true

require "test_helper"

class SchemaTest < Minitest::Test
  def test_define_schema_with_block
    schema = AiLens::Schema.define(name: "Test", description: "Test schema") do
      field :name, type: :string, required: true
      field :category, type: :string
      field :value, type: :decimal
    end

    assert_equal "Test", schema.name
    assert_equal "Test schema", schema.description
    assert_equal 3, schema.fields.size
  end

  def test_field_properties
    schema = AiLens::Schema.define(name: "Test") do
      field :name, type: :string, required: true, description: "Item name"
      field :condition, type: :string, enum: %w[New Used Damaged]
    end

    name_field = schema[:name]
    assert name_field.required?
    assert_equal :string, name_field.type
    assert_equal "Item name", name_field.description

    condition_field = schema[:condition]
    assert_equal %w[New Used Damaged], condition_field.enum_values
  end

  def test_to_json_schema
    schema = AiLens::Schema.define(name: "Test") do
      field :name, type: :string, required: true
      field :count, type: :integer
    end

    json_schema = schema.to_json_schema

    assert_equal "object", json_schema["type"]
    assert json_schema["properties"].key?("name")
    assert json_schema["properties"].key?("count")
    assert_includes json_schema["required"], "name"
    refute_includes json_schema["required"], "count"
  end

  def test_field_to_prompt_description
    schema = AiLens::Schema.define(name: "Test") do
      field :condition, type: :string, required: true, description: "Item condition", enum: %w[New Used]
    end

    field = schema[:condition]
    desc = field.to_prompt_description

    assert_includes desc, "condition"
    assert_includes desc, "Item condition"
    assert_includes desc, "New"
    assert_includes desc, "Used"
    assert_includes desc, "[required]"
  end

  def test_has_field
    schema = AiLens::Schema.define(name: "Test") do
      field :name, type: :string
    end

    assert schema.has_field?(:name)
    refute schema.has_field?(:missing)
  end

  def test_field_names
    schema = AiLens::Schema.define(name: "Test") do
      field :name, type: :string
      field :value, type: :decimal
    end

    assert_equal [:name, :value], schema.field_names
  end
end
