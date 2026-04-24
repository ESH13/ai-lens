# frozen_string_literal: true

require "erb"
require "yaml"

module AiLens
  class PromptBuilder
    attr_reader :schema, :context, :user_feedback, :photos_mode, :item_mode

    def initialize(schema:, context: nil, user_feedback: nil, photos_mode: :single, item_mode: :single)
      @schema = schema
      @context = context
      @user_feedback = user_feedback
      @photos_mode = photos_mode.to_sym
      @item_mode = item_mode.to_sym
    end

    def build
      if custom_template?
        build_from_template
      else
        build_default
      end
    end

    def system_prompt
      if custom_template? && template_content["system_prompt"]
        render_template(template_content["system_prompt"])
      else
        default_system_prompt
      end
    end

    # Class method for convenience
    def self.build(schema:, context: nil, user_feedback: nil, photos_mode: :single, item_mode: :single)
      new(
        schema: schema,
        context: context,
        user_feedback: user_feedback,
        photos_mode: photos_mode,
        item_mode: item_mode
      ).build
    end

    private

    def custom_template?
      AiLens.configuration.prompt_template.present?
    end

    def template_content
      @template_content ||= load_template
    end

    def load_template
      path = AiLens.configuration.prompt_template
      return {} unless path

      if path.respond_to?(:read)
        content = path.read
      elsif File.exist?(path.to_s)
        content = File.read(path.to_s)
      else
        return {}
      end

      if path.to_s.end_with?(".yml", ".yaml")
        YAML.safe_load(content, permitted_classes: [Symbol]) || {}
      else
        { "prompt" => content }
      end
    end

    def build_from_template
      # Select the appropriate prompt key based on mode combination
      prompt_key = determine_prompt_key
      template = template_content[prompt_key] || template_content["prompt"] || template_content["default"]

      if template
        render_template(template)
      else
        build_default
      end
    end

    def determine_prompt_key
      # Support mode-specific prompts like "single_photo_single_item"
      "#{photos_mode}_photo_#{item_mode}_item"
    end

    def render_template(template)
      # Create binding with all context variables
      binding_context = TemplateContext.new(
        schema: schema,
        context: context,
        user_feedback: user_feedback,
        photos_mode: photos_mode,
        item_mode: item_mode,
        schema_description: schema.to_prompt_description,
        schema_fields: schema.fields,
        has_feedback: user_feedback.present?,
        has_context: context.present?
      )

      ERB.new(template, trim_mode: "-").result(binding_context.get_binding)
    end

    def build_default
      parts = []

      parts << system_instruction
      parts << ""
      parts << schema.to_prompt_description
      parts << ""
      parts << output_format_instruction
      parts << ""
      parts << photo_tag_instructions

      if context.present?
        parts << ""
        parts << context_section
      end

      if user_feedback.present?
        parts << ""
        parts << feedback_section
      end

      parts.join("\n")
    end

    def default_system_prompt
      <<~PROMPT
        You are an expert appraiser and identifier specializing in collectibles, antiques, and valuable items.
        You analyze photos to identify items and extract structured information.
        Always respond with valid JSON matching the requested schema.
        Be thorough but concise in your descriptions.
        If you cannot determine a value with confidence, use null rather than guessing.
      PROMPT
    end

    def system_instruction
      case [photos_mode, item_mode]
      when [:single, :single]
        "Analyze the provided photo and identify the single item shown."
      when [:single, :multiple]
        "Analyze the provided photo and identify all items shown. Return an array of items."
      when [:multiple, :single]
        "Analyze all the provided photos together. They show the same item from different angles."
      when [:multiple, :multiple]
        "Analyze all the provided photos. They may show multiple items. Return an array of items."
      else
        "Analyze the provided photo(s) and identify the item(s) shown."
      end + "\nExtract all relevant information according to the schema below."
    end

    def output_format_instruction
      if item_mode == :multiple
        <<~INSTRUCTION
          Respond with a JSON object containing an "items" array.
          Each item in the array should have the fields from the schema.
          Use null for any fields where the information cannot be determined from the photos.
        INSTRUCTION
      else
        <<~INSTRUCTION
          Respond with a JSON object containing the extracted fields.
          Use null for any fields where the information cannot be determined from the photos.
          Ensure all values match the expected types.
        INSTRUCTION
      end
    end

    def context_section
      <<~CONTEXT
        Additional context provided by the user:
        #{context}
      CONTEXT
    end

    def photo_tag_instructions
      config = AiLens.configuration
      facets = config.photo_tag_facets
      threshold = config.photo_tag_threshold

      instructions = "For each photo provided, classify it by the following tag facets. " \
        "Score each facet from 0.0 to 1.0 based on how strongly the photo serves that purpose. " \
        "Only include facets with scores above #{threshold}.\n\n" \
        "Tag Facets:\n"

      facets.each do |name, desc|
        instructions += "- #{name}: #{desc}\n"
      end

      if config.open_photo_tags
        instructions += "\nIf you observe qualities in a photo that don't fit any of the defined tag facets " \
          "above, include them in an \"open_tags\" array with a descriptive facet name " \
          "(lowercase_snake_case) and a score."
      end

      instructions += "\n\nInclude a \"photo_tags\" array in your JSON response alongside \"extracted_attributes\". " \
        "Each entry should have: photo_index (integer), tags (array of {facet, score})"

      if config.open_photo_tags
        instructions += ", and open_tags (array of {facet, score}) for any novel facets"
      end

      instructions += "."

      instructions
    end

    def feedback_section
      <<~FEEDBACK
        User feedback from a previous identification attempt (please incorporate these corrections):
        #{user_feedback}
      FEEDBACK
    end

    # Helper class to provide clean binding for ERB templates
    class TemplateContext
      attr_reader :schema, :context, :user_feedback, :photos_mode, :item_mode,
                  :schema_description, :schema_fields, :has_feedback, :has_context

      def initialize(attrs = {})
        attrs.each do |key, value|
          instance_variable_set("@#{key}", value)
        end
      end

      def get_binding
        binding
      end

      # Helper methods available in templates
      def single_photo?
        photos_mode == :single
      end

      def multiple_photos?
        photos_mode == :multiple
      end

      def single_item?
        item_mode == :single
      end

      def multiple_items?
        item_mode == :multiple
      end
    end
  end
end
