# frozen_string_literal: true

require_relative "lib/ai_lens/version"

Gem::Specification.new do |spec|
  spec.name = "ai-lens"
  spec.version = AiLens::VERSION
  spec.authors = ["Your Name"]
  spec.email = ["your.email@example.com"]

  spec.summary = "AI-powered photo identification for Rails"
  spec.description = "Extract structured attributes from photos using multiple LLM providers with configurable schemas, lifecycle callbacks, and automatic fallback."
  spec.homepage = "https://github.com/your-username/ai-lens"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "rails", ">= 7.0", "< 9.0"
  spec.add_dependency "ai-loom", ">= 0.2.0"

  spec.add_development_dependency "minitest"
  spec.add_development_dependency "sqlite3"
end
