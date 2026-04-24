# frozen_string_literal: true

module AiLens
  class Engine < ::Rails::Engine
    isolate_namespace AiLens

    config.generators do |g|
      g.test_framework :minitest, fixture: true
    end

    initializer "ai_lens.load_defaults" do
      # Load default configuration if not already configured
      ActiveSupport.on_load(:active_record) do
        # Models can now include AiLens::Identifiable
      end
    end
  end
end
