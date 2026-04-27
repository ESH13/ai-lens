# Changelog

All notable changes to ai-lens are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-04-26

0.3.0 is a hardening release. The headline change is that the gem now
fails fast (and audibly) where it used to fail silently:
unimplemented modes, callback gating, schema violations, malformed
adapter kwargs, and stuck jobs all now raise typed errors with clear
messages instead of returning `nil` or producing empty data.

See [UPGRADING.md](UPGRADING.md) for a step-by-step migration guide
from 0.2.x.

### Breaking

- **`auto_apply` mechanism removed.** The column was always
  uninitialized in the install migration, so the auto-apply branch
  was dead code: extracted attributes were applied unconditionally
  regardless of the column value. The gem no longer references
  `auto_apply`. Hosts that did not run with this column (the only
  supported configuration) see no behavior change. Hosts who added
  the column manually should drop it; the apply path runs on every
  successful job.
- **`item_mode: :multiple` raises `AiLens::NotImplementedError`.**
  The four-mode matrix advertised single/multiple combinations on
  both `photos_mode` and `item_mode`, but the multi-item branch
  silently behaved like `:single` while consuming credits. Calling
  `identify!(item_mode: :multiple)` now raises before any job is
  created or callback fires. Only `item_mode: :single` is supported.
- **Default schema is now minimal.** Previous versions defaulted to
  a 17-field collectibles-oriented schema. The default is now
  `name` / `description` / `category` / `notes`, with no enum on
  `category`. Hosts that relied on the old default should opt in via
  `AiLens::Schemas::Collectibles` (see README, "Collectibles
  Schema").
- **`identify!` raises `AiLens::IdentificationGated`** when a
  `before_identify` callback returns false. The previous contract
  returned `nil` for both this case and "no photos available", so
  callers had no way to distinguish them. `nil` is still returned
  when there are simply no photos to identify.
- **`latest_identification` renamed to `latest_completed_identification`.**
  The old name implied "latest overall" but actually filtered to
  `:completed`. The canonical accessor is now
  `latest_completed_identification` (most recent successful job,
  ordered by `completed_at`). `latest_identification` is preserved
  with name-true semantics: most recent job of any status, ordered
  by `created_at`. Hosts calling `latest_identification` to read
  extracted attributes should switch to
  `latest_completed_identification` to preserve old behavior.
- **`identify!(adapters:)` validates the kwarg shape.** Passing a
  non-Array, non-nil value (the classic typo `adapters: :openai`)
  was previously dropped on the floor. It now raises `ArgumentError`
  with a message pointing the caller at `adapter:` for single
  adapters.
- **Requires ai-loom 0.3.0+.** ai-loom dropped the `:redis` shortcut
  and tightened a few of its own contracts; ai-lens has been updated
  to track those changes.

### Added

- **`AiLens::Error` hierarchy.** All gem-defined errors descend from
  `AiLens::Error < StandardError`, so a host can `rescue
  AiLens::Error` to catch every ai-lens failure with one clause.
  Subclasses: `ConfigurationError`, `SchemaError`, `ValidationError`,
  `IdentificationGated`, `NotImplementedError`.
  `Identifiable::NotConfiguredError` is now a subclass of
  `ConfigurationError`. Existing rescues that catch `StandardError`
  still work.
- **`AiLens::IdentificationGated`** raised by `identify!` when a
  `before_identify` callback returns false (see "Breaking" above).
- **`AiLens::Schemas::Collectibles`** module exposing the legacy
  17-field schema as opt-in. Use
  `define_schema(&AiLens::Schemas::Collectibles.method(:apply))`
  per-model, or
  `config.default_schema = AiLens::Schemas::Collectibles.build`
  globally.
- **`Schema#validate(extracted)`** validates an extracted-attribute
  Hash against the schema. Required-field, enum, and type-coercibility
  checks all produce structured `{field, kind, message}` violation
  hashes.
- **`config.validate_responses`** (default `true`) gates the new
  schema validation step inside `ProcessIdentificationJob`. When
  validation fails, the job is marked `:failed` with violations in
  `error_details["violations"]`, and the `on_failure` callback runs
  with a `ValidationError`. Hosts that want the LLM's raw response
  applied regardless of shape can set this to `false`.
- **Image preprocessing knobs are wired.** `max_image_dimension`,
  `image_quality`, and `image_format` now feed into ActiveStorage
  variant options. They were documented but unused before. Anything
  set via `config.image_variant_options` still wins per-key, so
  existing configurations keep working.
- **`AiLens.reset_default_schema!`** test/dev helper to clear the
  cached default schema between configurations.
- **`identify!(adapter:)` accepts an Array** for the full chain
  (primary + fallbacks) in one kwarg. The plural `adapters:` form
  is kept as a deprecated alias.

### Changed

- **`Job#complete!` is atomic.** Status update + `apply_identification!`
  now run inside a single transaction. A host-side validation error
  during apply rolls the job back to `:pending` rather than leaving
  it `:completed` with no host mutation. `on_success` callbacks run
  **outside** the transaction so they can safely enqueue jobs,
  broadcast Turbo Streams, etc.
- **`Job#start_processing!` is concurrency-safe.** The transition is
  a conditional UPDATE gated on `status = 'pending'`, so two workers
  racing for the same record cannot both transition. The losing
  caller returns `false` and `ProcessIdentificationJob#perform`
  bails out cleanly.
- **`config.max_retries` and `config.retry_delay` are read at
  runtime.** `ProcessIdentificationJob.retry_on` previously
  interpolated these at class-load time, freezing them before the
  host-app initializer ran. Hosts that set non-default values via
  `AiLens.configure` now see their values honored.
- **Stuck-job recovery counts attempts.** `RecoverStuckJobsJob`
  records `recovery_attempts` in `error_details` and gives up after
  `MAX_RECOVERY_ATTEMPTS` (default 3), so a consistently re-stalling
  job no longer cycles in the queue forever.
- **Image preparation is computed once per job.** Previously the
  fallback path re-encoded every photo for each adapter attempt.
  The encoded payload is cached across primary + fallback attempts.
- **`Job#parsed_extracted_attributes` and `#parsed_llm_results` are
  memoized.** `JSON.parse` runs at most once per attribute read;
  writing the underlying attribute invalidates the memo.
- **`Schema#dup` deep-copies** `enum_values` and field defaults so
  mutating a duplicated schema cannot reach into the original.
- **The fallback chain skips unavailable adapters.** Adapters whose
  `available?` returns false (missing API key, etc.) are no longer
  burned as a wasted attempt.
- **Outer rescues in `ProcessIdentificationJob` merge into existing
  `error_details`** rather than replacing them, so `tried_adapters`
  recorded by the fallback path survives the final `fail!`.
- **`Job.stuck` honors `config.stuck_job_threshold`.** Previously
  hardcoded to 1 hour regardless of host configuration.
- **`apply_identification!` filters by schema fields only.** Keys
  the LLM returned that aren't declared in the active schema (e.g.
  `photo_tags`, `items`) are no longer applied to the host model
  even if the host has a matching writer. This prevents LLM output
  from silently overwriting unrelated host state.
- **`photo_tags` are read from extracted_attributes.** The provider
  envelope and the LLM JSON content are different shapes;
  `parsed_photo_tags` now reads from the LLM content where the
  field actually lives, so `photo_tag_sets` is no longer silently
  empty.

### Fixed

- `ai-lens.gemspec` now uses real authors / email / homepage and
  references the actual `LICENSE.txt` filename in the `spec.files`
  glob (was `MIT-LICENSE`).

### Removed

- `auto_apply` configuration / column / branch (see "Breaking").
- The `:multiple` entry from the documented `item_mode` matrix
  (see "Breaking").

### Documentation

- New [UPGRADING.md](UPGRADING.md) walking 0.2.x → 0.3.0 callers
  through every breaking change with concrete diffs.
- README "Error Handling" section documents the full
  `AiLens::Error` hierarchy.
- README "Lifecycle Callbacks" section explicitly notes that ai-lens
  callbacks are simple proc hooks, NOT Rails `ActiveSupport::Callbacks`.
  They do not support `:if`, `:unless`, `skip_callback`, or callback
  ordering. Gate conditionally inside the proc.
- README "Latest Identification" section documents the
  `latest_completed_identification` / `latest_identification` rename
  with name-true semantics for both.
- README "Triggering Identification" documents `adapter:` accepting
  Symbol or Array, and that `adapters:` is a deprecated alias.
- `Configuration#default_schema=` (writable) vs `#schema` (read-only
  resolver) is documented on both, so future contributors don't try
  to "consolidate" them and break the fallback chain.
- `Feedback#suggested_corrections` is `t.json` and remains plaintext
  even when the host has configured Active Record encryption — AR
  encryption doesn't support JSON-typed columns. README's Encryption
  section spells this out and points hosts who need encryption to
  change the column type.
- README documents `RecoverStuckJobsJob` scheduling for Solid Queue,
  sidekiq-cron, whenever, and a fallback `after_initialize` lock
  pattern.

## [0.2.1] - 2026-04-26

### Changed

- **Active Record encryption is now opt-in.** The `encrypts`
  declarations on `AiLens::Job` (`llm_results`, `extracted_attributes`,
  `user_feedback`) and `AiLens::Feedback` (`comments`) are activated
  only when the host app has configured
  `Rails.application.config.active_record.encryption.primary_key`.
  Previously these unconditional declarations forced every host app to
  run `bin/rails db:encryption:init` before the gem could boot, even
  for hosts that did not require encryption. Host apps that already
  configure AR encryption see no behavior change.

### Renamed

- **`AiLens::Feedback#reidentify_requested` → `AiLens::Feedback#skip_auto_reidentify`.**
  The previous accessor name shadowed any real `reidentify_requested`
  DB column in the host app, silently preventing persistence of that
  column. The new name is unambiguous: setting
  `feedback.skip_auto_reidentify = true` before save suppresses the
  gem's `after_create_commit :trigger_reidentification` callback,
  letting the host controller drive re-identification manually.

  **Migration:** Search for `reidentify_requested = true` in your
  codebase and rename to `skip_auto_reidentify = true`. Then run your
  test suite. The DB column (if any) of the same name is unaffected
  and will now persist correctly.

## [0.2.0] - 2026-04-25

- Renamed from `photo_identification` gem to `ai-lens`.
- Module rename: `PhotoIdentification` → `AiLens`.
- Database table renames: `photo_identification_jobs` →
  `ai_lens_jobs`, `photo_identification_feedbacks` →
  `ai_lens_feedbacks`.
- Added `on_stage_change` callback for stage tracking.
- Added photo tag set support (note: see KNOWN ISSUES — wiring needs
  a fix in 0.3.0 before this is fully usable).
- Now depends on `ai-loom` for the underlying LLM adapter layer.
