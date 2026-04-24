# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record"

module AiLens
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Creates the AiLens migrations and initializer"

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def create_jobs_migration
        migration_template(
          "create_ai_lens_jobs.rb.erb",
          "db/migrate/create_ai_lens_jobs.rb"
        )
      end

      def create_feedbacks_migration
        # Sleep to ensure different timestamp
        sleep 1
        migration_template(
          "create_ai_lens_feedbacks.rb.erb",
          "db/migrate/create_ai_lens_feedbacks.rb"
        )
      end

      def create_initializer
        template "initializer.rb.erb", "config/initializers/ai_lens.rb"
      end

      def show_readme
        readme "README" if behavior == :invoke
      end

      private

      def migration_version
        "[#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}]"
      end
    end
  end
end
