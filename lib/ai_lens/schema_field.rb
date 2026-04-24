# frozen_string_literal: true

module AiLens
  class SchemaField
    VALID_TYPES = %i[string text integer float decimal boolean date datetime array].freeze

    attr_reader :name, :type, :description, :required, :default_value, :enum_values

    def initialize(name, type:, description: nil, required: false, default: nil, enum: nil)
      @name = name.to_sym
      @type = validate_type(type)
      @description = description
      @required = required
      @default_value = default
      @enum_values = enum
    end

    def required?
      @required
    end

    def optional?
      !required?
    end

    def has_enum?
      !@enum_values.nil? && !@enum_values.empty?
    end

    def has_default?
      !@default_value.nil?
    end

    # Generate JSON schema fragment for this field
    def to_json_schema
      schema = {
        "type" => json_type,
        "description" => description
      }

      if has_enum?
        schema["enum"] = enum_values
      end

      schema
    end

    # Generate prompt description for this field
    def to_prompt_description
      parts = ["#{name}"]

      if description
        parts << "(#{description})"
      end

      if has_enum?
        parts << "- must be one of: #{enum_values.join(', ')}"
      end

      if required?
        parts << "[required]"
      end

      parts.join(" ")
    end

    private

    def validate_type(type)
      type = type.to_sym
      unless VALID_TYPES.include?(type)
        raise ArgumentError, "Invalid field type: #{type}. Valid types: #{VALID_TYPES.join(', ')}"
      end
      type
    end

    def json_type
      case type
      when :string, :text then "string"
      when :integer then "integer"
      when :float, :decimal then "number"
      when :boolean then "boolean"
      when :date, :datetime then "string"
      when :array then "array"
      else "string"
      end
    end
  end
end
