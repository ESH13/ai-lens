# frozen_string_literal: true

module AiLens
  class Schema
    attr_reader :fields, :name, :description

    def initialize(name: nil, description: nil)
      @name = name
      @description = description
      @fields = {}
    end

    # DSL method to add a field
    def field(name, type:, description: nil, required: false, default: nil, enum: nil)
      @fields[name.to_sym] = SchemaField.new(
        name,
        type: type,
        description: description,
        required: required,
        default: default,
        enum: enum
      )
    end

    # Get a specific field
    def [](name)
      @fields[name.to_sym]
    end

    # Check if schema has a field
    def has_field?(name)
      @fields.key?(name.to_sym)
    end

    # Get field names
    def field_names
      @fields.keys
    end

    # Get required fields
    def required_fields
      @fields.select { |_, f| f.required? }
    end

    # Get optional fields
    def optional_fields
      @fields.reject { |_, f| f.required? }
    end

    # Generate JSON schema
    def to_json_schema
      properties = {}
      required = []

      @fields.each do |name, field|
        properties[name.to_s] = field.to_json_schema
        required << name.to_s if field.required?
      end

      schema = {
        "type" => "object",
        "properties" => properties
      }

      schema["required"] = required if required.any?
      schema["description"] = description if description

      schema
    end

    # Validate an extracted_attributes hash against this schema.
    # Returns an array of violation hashes; an empty array means the
    # response is valid. Each violation is:
    #   { field: <name>, kind: :missing | :enum | :type, message: <human-readable> }
    #
    # Validation is intentionally lenient about coercion: a string
    # "42" passes integer validation as long as Integer(value) would
    # succeed, since LLMs often emit numbers as strings. Apply the
    # coerced value at write time if you care about strict typing.
    def validate(extracted)
      extracted = extracted.is_a?(Hash) ? extracted : {}
      violations = []

      @fields.each do |name, field|
        key = name.to_s
        value = extracted[key]
        value = extracted[name] if value.nil?

        # Required-field check.
        if field.required? && (value.nil? || (value.respond_to?(:empty?) && value.empty?))
          violations << { field: key, kind: :missing, message: "#{key} is required" }
          next
        end

        # Skip type/enum checks when no value is present and the field
        # is optional.
        next if value.nil?

        # Enum check.
        if field.has_enum? && !field.enum_values.include?(value)
          violations << {
            field: key,
            kind: :enum,
            message: "#{key} must be one of #{field.enum_values.inspect} (got #{value.inspect})"
          }
        end

        # Type-coercibility check.
        unless type_compatible?(field.type, value)
          violations << {
            field: key,
            kind: :type,
            message: "#{key} must be coercible to #{field.type} (got #{value.class.name})"
          }
        end
      end

      violations
    end

    # Generate prompt-friendly field descriptions
    def to_prompt_description
      lines = []

      if description
        lines << description
        lines << ""
      end

      lines << "Extract the following fields:"
      lines << ""

      @fields.each do |_, field|
        lines << "- #{field.to_prompt_description}"
      end

      lines.join("\n")
    end

    # Duplicate schema with modifications. Deep-copies enum_values so
    # mutating the dup's enum array (e.g. `dup[:category].enum_values << :foo`)
    # cannot reach the original schema. Without this every consumer of
    # `enum_values` shared the same array instance — a footgun that
    # silently leaked changes across test runs and host configs.
    def dup
      new_schema = Schema.new(name: name, description: description)
      @fields.each do |name, field|
        new_schema.field(
          name,
          type: field.type,
          description: field.description,
          required: field.required?,
          default: deep_dup_value(field.default_value),
          enum: field.enum_values&.dup
        )
      end
      new_schema
    end

    private

    # Whether a value is compatible with the given schema type. Lenient
    # by design — LLMs often emit numbers as strings, so "42" is
    # considered compatible with :integer if Integer(value) parses.
    def type_compatible?(type, value)
      case type
      when :string, :text
        value.is_a?(String) || value.is_a?(Symbol)
      when :integer
        return true if value.is_a?(Integer)
        return Integer(value, 10).is_a?(Integer) if value.is_a?(String)
        false
      when :float, :decimal
        return true if value.is_a?(Numeric)
        return Float(value).is_a?(Float) if value.is_a?(String)
        false
      when :boolean
        value == true || value == false
      when :date, :datetime
        value.is_a?(String) || value.respond_to?(:strftime)
      when :array
        value.is_a?(Array)
      else
        true
      end
    rescue ArgumentError, TypeError
      false
    end

    # Best-effort deep-dup for field defaults. Hash and Array dup is
    # shallow; for nested structures we'd need a heavier helper, but
    # field defaults are typically scalars, hashes, or arrays of
    # scalars.
    def deep_dup_value(value)
      case value
      when Hash then value.dup.transform_values { |v| deep_dup_value(v) }
      when Array then value.map { |v| deep_dup_value(v) }
      when nil, true, false, Numeric, Symbol then value
      else
        begin
          value.dup
        rescue TypeError
          value
        end
      end
    end

    public

    # Class method to create schema with block
    # Uses instance_eval for DSL - this is a standard Ruby pattern for schema definition
    def self.define(name: nil, description: nil, &block)
      schema = new(name: name, description: description)
      schema.instance_eval(&block) if block_given?  # rubocop:disable Security/Eval -- instance_eval is not eval
      schema
    end
  end
end
