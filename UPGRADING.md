# Upgrading ai-lens

This guide walks through breaking changes between minor and major
versions of ai-lens. For the full release notes see
[CHANGELOG.md](CHANGELOG.md).

---

## Upgrading from 0.2.x to 0.3.0

0.3.0 is a hardening release. Most breaking changes turn previously
silent failures into typed errors. The minimum-viable upgrade for a
host that wasn't using any of the affected APIs is just bumping the
version. The sections below cover every change a real-world 0.2.x
host might trip on.

### 1. ai-loom 0.3.0+ is required

ai-lens now requires ai-loom 0.3.0 or newer:

```ruby
# Gemfile
gem "ai-loom", "~> 0.3"
gem "ai-lens", "~> 0.3"
```

Run `bundle update ai-loom ai-lens` together. ai-loom 0.3.0 itself
has breaking changes (most notably the removal of the `:redis`
shortcut for the rate limiter); see ai-loom's CHANGELOG for details.

### 2. `auto_apply` is gone

The `auto_apply` mechanism was always dead code. The install
migration never created the column, so the conditional was always
false on read; meanwhile, the actual apply path ran unconditionally
inside `Job#complete!`. We've removed the dead branch and any
`auto_apply` references from the gem.

**Action:** Most hosts need to do nothing. If you manually added an
`auto_apply` column to your `ai_lens_jobs` table (or its predecessor
`photo_identification_jobs`), drop it:

```ruby
class DropAutoApplyFromAiLensJobs < ActiveRecord::Migration[8.0]
  def change
    remove_column :ai_lens_jobs, :auto_apply, :boolean
  end
end
```

The apply path now runs on every successful job. If you need to
suppress automatic application, gate it via a `before_identify`
callback that returns false, or skip `identify!` entirely from your
controller and apply manually with `item.apply_identification!(job)`.

### 3. `item_mode: :multiple` raises immediately

The four-mode matrix advertised both `photos_mode: :multiple` and
`item_mode: :multiple`, but only the first was implemented. The
second silently behaved like `:single` while still consuming credits.

**Action:** If you have any `identify!(item_mode: :multiple)` calls,
they now raise `AiLens::NotImplementedError` before any job is
created:

```ruby
# Before — silently behaved as :single
job = item.identify!(item_mode: :multiple)

# After — raises AiLens::NotImplementedError
job = item.identify!(item_mode: :multiple)
# => AiLens::NotImplementedError: Multi-item mode is not implemented in 0.3.0...

# Migration: drop the kwarg, since it always behaved as :single anyway
job = item.identify!  # item_mode defaults to :single
```

If you genuinely need multi-item identification (one photo,
multiple distinct items extracted as an array), watch for a future
release; the schema and prompt-builder support is partially in
place, but the round-trip mapping isn't safe yet.

### 4. Default schema is now minimal

Previous versions defaulted to a 17-field collectibles-oriented
schema (`name`, `category`, `manufacturer`, `series`, `variant`,
`brand`, `year`, `condition`, `rarity`, `description`,
`estimated_value_low/high`, `confidence_score`, `counterfeit_risk`,
`featured_photo_index`, `identifying_features`, `notes`). The new
default is just `name`, `description`, `category` (freeform, no
enum), and `notes`.

**Action:** Pick the path that matches your app:

If you relied on the old default and are doing collectibles, opt in
to the bundled schema:

```ruby
# Per-model
class Item < ApplicationRecord
  include AiLens::Identifiable
  identifiable_photos :photos
  define_schema(&AiLens::Schemas::Collectibles.method(:apply))
end

# Or globally
AiLens.configure do |config|
  config.default_schema = AiLens::Schemas::Collectibles.build
end
```

If you've been defining a custom schema with `define_schema do ... end`,
nothing changes — your model-level schema wins over the default.

If you weren't using any of the old default fields (just the four
that survived), your code keeps working.

### 5. `latest_identification` renamed

`latest_identification` previously returned only `:completed` jobs
despite its name. The canonical accessor is now
`latest_completed_identification`. `latest_identification` is kept
with name-true semantics: most recent job of any status.

**Action:** Find every call site that used `latest_identification`
to read extracted attributes or photo tags, and switch to
`latest_completed_identification` for unchanged behavior:

```ruby
# Before — only ever saw completed jobs
job = item.latest_identification
job.parsed_extracted_attributes

# After — preserve old behavior
job = item.latest_completed_identification
job.parsed_extracted_attributes
```

If you want the new "latest of any status" semantics (handy for
"we're working on it" / "we tried and failed" UI), use
`latest_identification` as-is.

### 6. `before_identify` returning false now raises

Previously, `identify!` returned `nil` for both "callback gated this"
and "no photos available", so callers had no way to distinguish them.

**Action:** Catch `AiLens::IdentificationGated` if your UI needs to
show a "buy more credits" / "subscribe to use this feature" CTA:

```ruby
# Before — silent nil for both gated and no-photos cases
job = item.identify!
return render :no_credits unless job  # but maybe it was no photos!

# After — distinguish the two paths
begin
  job = item.identify!
rescue AiLens::IdentificationGated
  return render :no_credits
end

return render :upload_photos unless job  # nil now means no photos
```

### 7. `identify!(adapters:)` validates the kwarg shape

A common typo — `adapters: :openai` (Symbol where Array is expected)
— was previously dropped on the floor, falling through to the
configured default adapter without any signal.

**Action:** If you typo'd this, the new `ArgumentError` will tell
you immediately. Fix the call to use `adapter:` for single adapters:

```ruby
# Before — silently used config.default_adapter
item.identify!(adapters: :openai)

# After — raises ArgumentError; fix the typo
item.identify!(adapter: :openai)
```

The plural `adapters:` form remains a valid alias for an Array
chain. `adapter:` itself now also accepts an Array, so you can pass
the whole chain via either kwarg.

### 8. Error hierarchy expanded

ai-lens now defines `AiLens::Error < StandardError` as the umbrella
base class. All gem-defined errors descend from it.

**Action:** Hosts catching `AiLens::Identifiable::NotConfiguredError`
should consider switching to `AiLens::ConfigurationError` for
broader coverage:

```ruby
# Before — only catches one specific config mistake
begin
  item.identify!
rescue AiLens::Identifiable::NotConfiguredError => e
  ...
end

# After — catches every config-related failure ai-lens raises
begin
  item.identify!
rescue AiLens::ConfigurationError => e
  ...
end

# Or catch every ai-lens failure with one clause
begin
  item.identify!
rescue AiLens::Error => e
  ...
end
```

`NotConfiguredError` is still raised in the same places; it's just
now reparented under `ConfigurationError`. Existing rescues that
catch `StandardError` continue to work unchanged.

### 9. Schema validation is on by default

LLM responses are now validated against the active schema before
`apply_identification!` runs. Required-field, enum, and
type-coercibility checks produce structured violation hashes. A
failed validation marks the job `:failed` with violations in
`error_details["violations"]` and fires `on_failure` with an
`AiLens::ValidationError`.

**Action:** No code changes are needed for the happy path. If you
relied on the old behavior of accepting any LLM output (e.g. for
debugging or for a permissive prompt-only UX), turn validation off:

```ruby
AiLens.configure do |config|
  config.validate_responses = false
end
```

If your `on_failure` callback is logging exceptions, expect to see
`AiLens::ValidationError` in addition to whatever you saw before.
Inspect `error.violations` for the structured failures.

### 10. Photo tags now actually populate

`parsed_photo_tags` previously read from the wrong layer of the
response (the provider envelope rather than the LLM JSON content),
so `item.photo_tag_sets` was silently empty for most hosts.

**Action:** If you were reading `item.photo_tag_sets` /
`item.photo_tags_for(...)` and getting empty arrays, those now
return real data on completed jobs. Make sure your view code can
handle non-empty results — otherwise no change needed.

### 11. Lifecycle callbacks are not Rails-style

This isn't a code-level break — it's a documentation clarification.
ai-lens callbacks (`before_identify`, `after_identify`, `on_success`,
`on_failure`, `on_stage_change`) are simple proc / method-symbol
hooks. They do **not** support `:if`, `:unless`, callback ordering
options, `skip_callback`, or any other `ActiveSupport::Callbacks`
features.

**Action:** If you have ever written `before_identify ..., if: ...`
expecting Rails semantics, that option was being ignored. Move the
guard inside the proc:

```ruby
# Doesn't work — :if is silently ignored
before_identify :check_credits, if: :subscribed?

# Works
before_identify ->(item) {
  return true unless item.user.subscribed?
  item.user.credits.positive?
}
```

### 12. `auto_apply` column drop is the only DB-level change

If you've never manually added the `auto_apply` column, you don't
need a migration. The 0.3.0 schema is otherwise compatible with
0.2.x.

---

## Upgrading from 0.2.0 to 0.2.1

See the [0.2.1 entry in CHANGELOG.md](CHANGELOG.md#021---2026-04-26)
for full notes. The notable change is
`Feedback#reidentify_requested` → `Feedback#skip_auto_reidentify`.

---

## Upgrading from `photo_identification` to ai-lens 0.2.0

See the "Upgrading from photo_identification" section in
[README.md](README.md). 0.2.0 was the rename release; 0.3.0 builds
on top of it.
