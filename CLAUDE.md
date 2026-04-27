# CLAUDE.md — ai-lens Gem Development Guide

## What is ai-lens?

AI-powered photo identification for Rails. Extracts structured attributes from
photos using LLM vision APIs. Depends on ai-loom for the adapter layer.

## Commands

```bash
bundle exec rake test    # Run all tests
```

## Architecture

- `lib/ai_lens.rb` — Main module, default schema
- `lib/ai_lens/configuration.rb` — Configuration with adapter, schema, image settings
- `lib/ai_lens/identifiable.rb` — ActiveSupport::Concern mixin for models
- `lib/ai_lens/schema.rb` + `schema_field.rb` — Schema DSL
- `lib/ai_lens/schemas/collectibles.rb` — Opt-in collectibles schema
- `lib/ai_lens/prompt_builder.rb` — Prompt generation with photo tags
- `lib/ai_lens/photo_tag_set.rb` — Photo tagging value object
- `lib/ai_lens/process_identification_job.rb` — Background job
- `lib/ai_lens/recover_stuck_jobs_job.rb` — Stuck job recovery
- `lib/ai_lens/errors.rb` — Error hierarchy
- `app/models/ai_lens/job.rb` — Job ActiveRecord model
- `app/models/ai_lens/feedback.rb` — Feedback ActiveRecord model

## Model Landscape Maintenance

ai-lens depends on ai-loom for LLM adapters and models. When ai-loom updates
its DEFAULT_MODELS or model landscape:

1. Update the ai-lens README "Model Landscape" section
2. Update the cost-per-identification table if pricing changed
3. Bump the ai-loom dependency version in the gemspec if needed
4. Update CHANGELOG.md and bump the patch version
5. Run tests
6. Update vendored copies in all consuming codebases

See the ai-loom CLAUDE.md for the full model maintenance procedure.

## Vendoring

This is a private gem. Consuming codebases vendor both ai-loom and ai-lens at
`vendor/gems/`. See the README "Vendoring" section for the correct procedure.
**Always update both gems together** — ai-lens declares a minimum ai-loom version.

## Testing

Tests use Minitest with an in-memory SQLite database. No external API calls.
Run with `bundle exec rake test`.
