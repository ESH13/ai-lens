# frozen_string_literal: true

module AiLens
  # Base class for every gem-defined error. Host apps can rescue
  # AiLens::Error to catch any failure originating in ai-lens code,
  # without having to enumerate the subclasses.
  class Error < StandardError; end

  # Raised when a feature is requested that is not implemented in the
  # current version (e.g. item_mode: :multiple in 0.3.0).
  class NotImplementedError < Error; end

  # Raised when host-app configuration is missing or invalid. Examples:
  # `identifiable_photos` not declared on a model that includes
  # `AiLens::Identifiable`; required ai-loom credentials missing for the
  # selected adapter; an invalid `prompt_template` path.
  class ConfigurationError < Error; end

  # Raised when a Schema is malformed — e.g. an unknown field type, a
  # field-level constraint that contradicts the LLM's response shape,
  # or any other schema-side authoring mistake.
  class SchemaError < Error; end

  # Raised when an LLM response fails schema validation. Carries the
  # list of violations on `#violations` (array of {field, kind,
  # message} hashes) so the host can surface the failure clearly.
  class ValidationError < Error
    attr_reader :violations

    def initialize(message = "schema_validation_failed", violations: [])
      super(message)
      @violations = violations
    end
  end

  # Raised by Identifiable#identify! when a before_identify callback
  # returns false. The previous contract returned nil for both
  # "callback gated" and "no photos available", so callers had no way
  # to tell them apart. 0.3.0 raises this for the gate path and keeps
  # nil for "no photos."
  class IdentificationGated < Error; end
end
