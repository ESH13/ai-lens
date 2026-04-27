# frozen_string_literal: true

require "test_helper"

# Task 16 + 22: ai-lens defines a single rooted error hierarchy under
# AiLens::Error so hosts can rescue everything the gem can raise via
# one rescue clause.
class ErrorsTest < Minitest::Test
  def test_base_error_is_standard_error
    assert AiLens::Error < StandardError
  end

  def test_not_implemented_error_subclass
    assert AiLens::NotImplementedError < AiLens::Error
  end

  def test_configuration_error_subclass
    assert AiLens::ConfigurationError < AiLens::Error
  end

  def test_schema_error_subclass
    assert AiLens::SchemaError < AiLens::Error
  end

  def test_validation_error_subclass
    assert AiLens::ValidationError < AiLens::Error
  end

  def test_validation_error_carries_violations
    err = AiLens::ValidationError.new(violations: [{ field: "name", kind: :missing }])
    assert_equal "schema_validation_failed", err.message
    assert_equal [{ field: "name", kind: :missing }], err.violations
  end

  def test_identification_gated_subclass
    assert AiLens::IdentificationGated < AiLens::Error
  end

  # Task 22: Identifiable::NotConfiguredError is rescuable as both
  # AiLens::ConfigurationError and AiLens::Error.
  def test_not_configured_error_reparented_under_configuration_error
    assert AiLens::Identifiable::NotConfiguredError < AiLens::ConfigurationError
    assert AiLens::Identifiable::NotConfiguredError < AiLens::Error
  end

  def test_not_configured_error_rescuable_as_ai_lens_error
    raised = nil
    begin
      raise AiLens::Identifiable::NotConfiguredError, "boom"
    rescue AiLens::Error => e
      raised = e
    end

    assert_equal "boom", raised.message
  end
end
