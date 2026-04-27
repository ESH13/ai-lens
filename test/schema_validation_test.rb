# frozen_string_literal: true

require "test_helper"

# Task 17: Schema-level validation of LLM responses. Schema#validate
# returns an array of violation hashes; ProcessIdentificationJob
# consumes them and marks the job :failed when any violation appears.
class SchemaValidationTest < Minitest::Test
  def test_required_field_missing_produces_violation
    schema = AiLens::Schema.define(name: "test") do
      field :name, type: :string, required: true
      field :year, type: :integer
    end

    violations = schema.validate("year" => 2020)
    assert_equal 1, violations.size
    assert_equal "name", violations.first[:field]
    assert_equal :missing, violations.first[:kind]
  end

  def test_enum_violation_recorded
    schema = AiLens::Schema.define(name: "test") do
      field :condition, type: :string, enum: %w[mint poor]
    end

    violations = schema.validate("condition" => "shiny")
    assert_equal 1, violations.size
    assert_equal "condition", violations.first[:field]
    assert_equal :enum, violations.first[:kind]
  end

  def test_type_incompatibility_recorded
    schema = AiLens::Schema.define(name: "test") do
      field :year, type: :integer
    end

    # A non-numeric string should fail the integer-coercibility check.
    violations = schema.validate("year" => "twenty-twenty")
    assert_equal 1, violations.size
    assert_equal :type, violations.first[:kind]
  end

  def test_integer_string_is_coercible
    schema = AiLens::Schema.define(name: "test") do
      field :year, type: :integer
    end

    # Integers commonly arrive as JSON strings from looser LLMs.
    assert_empty schema.validate("year" => "2020")
  end

  def test_valid_response_returns_empty_violations
    schema = AiLens::Schema.define(name: "test") do
      field :name, type: :string, required: true
      field :year, type: :integer
      field :rarity, type: :string, enum: %w[common rare]
    end

    assert_empty schema.validate("name" => "x", "year" => 2020, "rarity" => "rare")
  end

  def test_optional_field_can_be_omitted
    schema = AiLens::Schema.define(name: "test") do
      field :name, type: :string
      field :year, type: :integer
    end

    assert_empty schema.validate("name" => "x")
  end
end

# Integration: ProcessIdentificationJob marks a job :failed when the
# LLM response fails validation, and records the violations in
# error_details.
class ProcessJobValidationTest < Minitest::Test
  def setup
    AiLens.reset_configuration!
    AiLens::Job.delete_all

    unless defined?(ValidatingTestItem)
      Object.const_set(:ValidatingTestItem, Class.new(ActiveRecord::Base) do
        self.table_name = "test_items"
        include AiLens::Identifiable
        identifiable_photos :photos
        define_schema do |s|
          s.field :name, type: :string, required: true
          s.field :year, type: :integer
        end

        def photos
          [Object.new] # any non-empty truthy thing
        end
      end)
    end

    @item = ValidatingTestItem.create!(name: "Original")
  end

  def teardown
    AiLens.reset_configuration!
  end

  def test_job_fails_when_response_violates_schema
    # Override the mock adapter to return a payload missing the
    # required `name` field.
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    instance = AiLens::ProcessIdentificationJob.new
    instance.define_singleton_method(:prepare_images) { |_| ["data:image/jpeg;base64,fake"] }
    bad_adapter = AiLoom.adapter(:openai)
    bad_adapter.define_singleton_method(:analyze_with_images) do |**_|
      AiLoom::MockResponse.new(content: '{"year": 2020}', model: "x", adapter: :openai)
    end
    instance.define_singleton_method(:get_adapter_for_job) { |_| bad_adapter }

    instance.perform(job)

    job.reload
    assert_equal "failed", job.status
    assert_equal "schema_validation_failed", job.error_message
    refute_nil job.error_details["violations"]
    assert_equal "name", job.error_details["violations"].first["field"]
  end

  def test_validation_can_be_disabled_via_configuration
    AiLens.configuration.validate_responses = false

    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    instance = AiLens::ProcessIdentificationJob.new
    instance.define_singleton_method(:prepare_images) { |_| ["data:image/jpeg;base64,fake"] }
    bad_adapter = AiLoom.adapter(:openai)
    bad_adapter.define_singleton_method(:analyze_with_images) do |**_|
      AiLoom::MockResponse.new(content: '{"year": 2020}', model: "x", adapter: :openai)
    end
    instance.define_singleton_method(:get_adapter_for_job) { |_| bad_adapter }

    instance.perform(job)

    job.reload
    assert_equal "completed", job.status, "with validation off, the missing required field is allowed through"
  end
end
