# Changelog

## [0.3.0] - unreleased

### Breaking
- **Default schema is now minimal.** Previous versions defaulted to a
  17-field collectibles-oriented schema. The default is now
  `name`/`description`/`category`/`notes` with no enum on `category`.
  Hosts that relied on the old default should opt in via
  `AiLens::Schemas::Collectibles` (see README, "Collectibles Schema").
- **`identify!` now raises `AiLens::IdentificationGated`** when a
  `before_identify` callback returns false. The previous contract
  returned `nil` for both this case and "no photos available", so
  callers had no way to distinguish them. `nil` is still returned
  when there are simply no photos to identify.

### Added
- `AiLens::Error` hierarchy: `ConfigurationError`, `SchemaError`,
  `ValidationError`, `IdentificationGated`. `Identifiable::NotConfiguredError`
  is now a subclass of `ConfigurationError`. See README, "Error Handling".
- `Schema#validate(extracted)` for validating LLM responses against
  the schema. Required-field, enum, and type-coercibility checks all
  produce structured `{field, kind, message}` violation hashes.
- `config.validate_responses` (default `true`) gates the new
  validating-stage check inside `ProcessIdentificationJob`.
- `AiLens::Schemas::Collectibles` module exposing the legacy 17-field
  schema as opt-in. Use `define_schema(&AiLens::Schemas::Collectibles.method(:apply))`
  per-model or `config.default_schema = AiLens::Schemas::Collectibles.build`
  globally.
- `AiLens.reset_default_schema!` for tests/dev.

### Changed
- `Job#complete!` now wraps the status update + `apply_identification!`
  in a single transaction. A host-side validation error during apply
  rolls the job back to `:pending` rather than leaving it `:completed`
  with no host mutation. `on_success` callbacks run **outside** the
  transaction so they can safely enqueue jobs, broadcast Turbo
  Streams, etc.
- `Job#start_processing!` is a conditional UPDATE gated on
  `status = 'pending'` so two workers racing for the same record
  cannot both transition. The losing caller returns `false` and
  `ProcessIdentificationJob#perform` bails out.
- Stuck-job recovery counts `recovery_attempts` in `error_details`
  and gives up after `MAX_RECOVERY_ATTEMPTS` (default 3) so a
  consistently re-stalling job no longer cycles in the queue
  forever.
- Image preparation runs at most once across primary + fallback
  adapter attempts. Previously the fallback path re-encoded every
  photo.
- `Job#parsed_extracted_attributes` and `#parsed_llm_results` memoize
  their `JSON.parse` result; mutating the underlying attribute
  invalidates the memo.
- `Schema#dup` deep-copies `enum_values` and field defaults so
  mutating a duplicated schema cannot reach into the original.
- `image_quality`, `image_format`, and `max_image_dimension`
  configuration values are now wired into ActiveStorage variant
  options. Previously documented but unused.
- The fallback chain skips adapters where `available?` returns
  false, so unconfigured providers no longer waste an attempt.
- Outer rescues in `ProcessIdentificationJob` merge into existing
  `error_details` rather than replacing them, so `tried_adapters`
  recorded by the fallback path survives the final `fail!`.

### Documentation
- `Feedback#suggested_corrections` is `t.json` and remains plaintext
  even when the host has configured Active Record encryption — AR
  encryption doesn't support JSON-typed columns. README's Encryption
  section spells this out and points hosts who need encryption to
  change the column type.
- Real authors/email/homepage in `ai-lens.gemspec`. Replaced
  `MIT-LICENSE` with the actual `LICENSE.txt` filename in the
  `spec.files` glob.

## [0.2.1] - 2026-04-26

### Changed
- **Active Record encryption is now opt-in.** The `encrypts` declarations on
  `AiLens::Job` (`llm_results`, `extracted_attributes`, `user_feedback`) and
  `AiLens::Feedback` (`comments`) are now activated only when the host app
  has configured `Rails.application.config.active_record.encryption.primary_key`.
  Previously these unconditional declarations forced every host app to run
  `bin/rails db:encryption:init` before the gem could boot, even for hosts
  that did not require encryption. Host apps that already configure AR
  encryption see no behavior change.

### Renamed
- **`AiLens::Feedback#reidentify_requested` → `AiLens::Feedback#skip_auto_reidentify`.**
  The previous accessor name shadowed any real `reidentify_requested` DB column
  in the host app, silently preventing persistence of that column. The new name
  is unambiguous: setting `feedback.skip_auto_reidentify = true` before save
  suppresses the gem's `after_create_commit :trigger_reidentification` callback,
  letting the host controller drive re-identification manually.

  **Migration:** Search for `reidentify_requested = true` in your codebase and
  rename to `skip_auto_reidentify = true`. Then run your test suite. The DB
  column (if any) of the same name is unaffected and will now persist correctly.

## [0.2.0] - 2026-04-25

- Renamed from `photo_identification` gem to `ai-lens`.
- Module rename: `PhotoIdentification` → `AiLens`.
- Database table renames: `photo_identification_jobs` → `ai_lens_jobs`,
  `photo_identification_feedbacks` → `ai_lens_feedbacks`.
- Added `on_stage_change` callback for stage tracking.
- Added photo tag set support (note: see KNOWN ISSUES — wiring needs a fix in
  0.3.0 before this is fully usable).
- Now depends on `ai-loom` for the underlying LLM adapter layer.
