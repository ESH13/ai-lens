# ai-lens

AI-powered photo identification for Rails. Drop structured attribute extraction into any ActiveRecord model backed by photos. ai-lens sends images to an LLM, extracts fields you define in a schema, applies them to your model, and classifies each photo by purpose -- all with automatic provider fallback, encrypted storage, lifecycle callbacks, and background job processing.

Built on [ai-loom](https://github.com/your-username/ai-loom) for multi-provider LLM access.

---

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Installation](#installation)
4. [Quick Start](#quick-start)
5. [Configuration](#configuration)
6. [Model Setup](#model-setup)
7. [Schemas](#schemas)
8. [Triggering Identification](#triggering-identification)
9. [Photo Tags](#photo-tags)
10. [Lifecycle Callbacks](#lifecycle-callbacks)
11. [Progress Stages](#progress-stages)
12. [Results](#results)
13. [User Feedback](#user-feedback)
14. [Fallback Adapters](#fallback-adapters)
15. [Custom Prompt Templates](#custom-prompt-templates)
16. [Background Jobs](#background-jobs)
17. [Job Model](#job-model)
18. [Error Handling](#error-handling)
19. [Image Processing](#image-processing)
20. [Upgrading from photo_identification](#upgrading-from-photo_identification)

---

## Overview

ai-lens is a Rails engine that adds AI-powered photo identification to any ActiveRecord model. Point it at an association of photos (ActiveStorage attachments, URLs, or file paths), define a schema describing what you want extracted, and ai-lens handles the rest:

- Sends images to an LLM provider (OpenAI, Anthropic, Gemini, or Grok)
- Extracts structured attributes according to your schema
- Classifies each photo by purpose (identifier, showcase, damage, etc.)
- Applies results back to your model automatically
- Falls back through alternative providers if the primary fails
- Encrypts all LLM responses and user data at rest
- Runs entirely in background jobs with stage-by-stage progress tracking

ai-lens is designed for collectibles, antiques, and valuable items, but works for any domain where you need structured data extracted from photos.

---

## Features

- **Multi-provider LLM support** via ai-loom (OpenAI, Anthropic, Gemini, Grok)
- **Automatic fallback chain** -- if the primary adapter fails, ai-lens tries the next provider in the chain
- **Configurable schemas** -- define exactly which fields to extract, with types, enums, and descriptions
- **Default collectibles schema** with 17 fields (name, category, manufacturer, series, variant, brand, year, condition, rarity, description, value estimates, confidence score, counterfeit risk, featured photo index, identifying features, notes)
- **Per-model custom schemas** -- override the default schema for specific models
- **Photo tagging** -- each photo is classified by six built-in facets plus custom facets and open tagging
- **Lifecycle callbacks** -- before_identify (gate), after_identify, on_success, on_failure, on_stage_change
- **Progress stages** -- seven stages from queued to completed, with callbacks for real-time UI updates
- **Auto-apply** -- extracted attributes are automatically mapped and applied to your model
- **Attribute mapping** -- map extracted field names to your model's column names
- **User feedback loop** -- collect feedback, trigger automatic re-identification with corrections
- **Encrypted storage** -- extracted_attributes, llm_results, user_feedback, and comments are encrypted via ActiveRecord encryption
- **Background processing** -- all identification runs as ActiveJob with configurable queue, retries, and delay
- **Stuck job recovery** -- a recovery job finds and retries jobs stuck in pending/processing state
- **Custom prompt templates** -- YAML/ERB templates with mode-specific prompt keys
- **Image preprocessing** -- ActiveStorage variants for resizing and format conversion before sending to the LLM
- **Router integration** -- use ai-loom's router to select adapters by task

---

## Installation

Add ai-lens and its dependency ai-loom to your Gemfile:

```ruby
gem "ai-loom", "~> 0.2"
gem "ai-lens", "~> 0.2"
```

Run the installer:

```bash
bundle install
bin/rails generate ai_lens:install
bin/rails db:migrate
```

The generator creates:

- `db/migrate/..._create_ai_lens_jobs.rb` -- the jobs table
- `db/migrate/..._create_ai_lens_feedbacks.rb` -- the feedback table
- `config/initializers/ai_lens.rb` -- configuration file

### Credentials

Configure your LLM provider API keys in `config/credentials.yml.enc`:

```yaml
openai:
  api_key: sk-...

anthropic:
  api_key: sk-ant-...

google:
  api_key: AIza...

xai:
  api_key: xai-...
```

### ActiveRecord Encryption

Active Record encryption is opt-in. The `encrypts` calls on `AiLens::Job`
(`extracted_attributes`, `llm_results`, `user_feedback`) and `AiLens::Feedback`
(`comments`) only activate when `Rails.application.config.active_record.encryption.primary_key`
is configured. If your host app has not run `bin/rails db:encryption:init`,
ai-lens stores these columns in plaintext rather than failing to boot.
**For production with sensitive data, configure encryption.**

To enable encryption, generate the keys:

```bash
bin/rails db:encryption:init
```

Add the output to your credentials file under `active_record_encryption`.

---

## Quick Start

```ruby
# app/models/item.rb
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos

  identifiable_photos :photos
end
```

```ruby
# In a controller, console, or background job:
item = Item.find(1)
job = item.identify!

# Check status
item.identifying?          # => true
job.status                 # => "processing"

# After completion
item.identified?           # => true
job = item.latest_completed_identification
job.parsed_extracted_attributes
# => { "name" => "1952 Topps Mickey Mantle", "category" => "trading_card", ... }
```

---

## Configuration

All options with their defaults:

```ruby
# config/initializers/ai_lens.rb
AiLens.configure do |config|
  # Primary LLM adapter
  config.default_adapter = :openai

  # Fallback adapters tried in order if the primary fails
  config.fallback_adapters = [:anthropic, :grok, :gemini]

  # Global schema override (nil uses the built-in collectibles schema)
  config.default_schema = nil

  # Custom prompt template path (nil uses the built-in prompts)
  config.prompt_template = nil

  # Maximum number of photos sent per identification
  config.max_photos = 10

  # ActiveJob queue name
  config.queue_name = :default

  # Maximum retry attempts for retryable errors
  config.max_retries = 3

  # Base retry delay in seconds
  config.retry_delay = 5

  # Maximum image dimension (pixels) for preprocessing
  config.max_image_dimension = 2048

  # JPEG quality for preprocessed images
  config.image_quality = 85

  # Output format for preprocessed images
  config.image_format = :jpeg

  # ActiveStorage variant options applied before sending to the LLM
  config.image_variant_options = { resize_to_limit: [2048, 2048] }

  # Jobs older than this threshold are considered stuck
  config.stuck_job_threshold = 1.hour

  # Logger instance
  config.logger = Rails.logger

  # ai-loom router task name (nil disables router, uses default_adapter)
  config.task = nil

  # Allow the LLM to create tag facets beyond the built-in set
  config.open_photo_tags = false

  # Minimum score threshold for photo tag facets (0.0 to 1.0)
  config.photo_tag_threshold = 0.3
end
```

---

## Model Setup

Include `AiLens::Identifiable` in any ActiveRecord model and configure it with three class methods:

### `identifiable_photos`

Tell ai-lens which association provides the photos. This must be an association or method that returns objects supporting `.download` (ActiveStorage), `.url`, or String paths.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos

  identifiable_photos :photos
end
```

### `identifiable_mapping`

Map extracted schema field names to your model's column names. Fields not in the mapping are applied directly if a matching column exists.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos

  identifiable_photos :photos
  identifiable_mapping(
    name: :title,
    category: :item_type,
    description: :notes,
    estimated_value_low: :price_low,
    estimated_value_high: :price_high
  )
end
```

### Full Model Example

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos

  identifiable_photos :photos

  identifiable_mapping(
    name: :title,
    category: :item_type,
    description: :notes
  )

  define_schema(name: "collectible_item", description: "A collectible item for appraisal") do
    field :name, type: :string, required: true, description: "The name or title of the item"
    field :category, type: :string, description: "Primary category",
      enum: %w[trading_card coin stamp comic_book vinyl_record action_figure other]
    field :year, type: :integer, description: "Year of manufacture or release"
    field :condition, type: :string, description: "Condition assessment",
      enum: %w[mint near_mint excellent good fair poor]
    field :estimated_value_low, type: :decimal, description: "Low estimate in USD"
    field :estimated_value_high, type: :decimal, description: "High estimate in USD"
    field :identifying_features, type: :array, description: "Key identifying features"
  end

  before_identify ->(item) { item.user.credits.positive? }
  on_success ->(item, job) { item.user.decrement!(:credits) }
  on_failure ->(item, job, error) { AdminMailer.identification_failed(item, error).deliver_later }
  on_stage_change ->(item, job, stage) {
    Turbo::StreamsChannel.broadcast_replace_to(
      item, target: "identification_status",
      partial: "items/identification_stage", locals: { stage: stage }
    )
  }
end
```

---

## Schemas

A schema defines the fields the LLM should extract from photos. Each field has a name, type, and optional description, enum constraint, required flag, and default value.

### Default Schema

ai-lens ships with a minimal generic default schema. This is a
**breaking change in 0.3.0** — earlier versions defaulted to a
17-field collectibles schema. Hosts that relied on the collectibles
default should opt in via `AiLens::Schemas::Collectibles` (see below).

| Field | Type | Description |
|---|---|---|
| `name` | string | The name or title of the item |
| `description` | text | Detailed description of the item |
| `category` | string | Freeform category (no enum) |
| `notes` | text | Additional notes or observations |

### Collectibles Schema (opt-in)

For richer collectibles identification, use the bundled
`AiLens::Schemas::Collectibles` schema, which adds 13 more fields
including `manufacturer`, `series`, `variant`, `year`, `condition`
(with enum), `rarity`, `estimated_value_low/high`, `confidence_score`,
`counterfeit_risk`, `featured_photo_index`, `identifying_features`,
and a category enum covering trading cards, sneakers, watches, etc.

**Per-model:**

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable
  identifiable_photos :photos
  define_schema(&AiLens::Schemas::Collectibles.method(:apply))
end
```

**Globally:**

```ruby
AiLens.configure do |config|
  config.default_schema = AiLens::Schemas::Collectibles.build
end
```

#### Collectibles Category Enum

```
trading_card, pokemon_card, sports_card, mtg_card, yugioh_card, coin, stamp,
comic_book, vinyl_record, action_figure, funko_pop, lego_set, board_game,
video_game, sneakers, watch, jewelry, handbag, art_print, figurine, diecast_car,
plush, ornament, pottery, antique, memorabilia, autograph, book, instrument, other
```

#### Collectibles Condition Enum

```
mint, near_mint, excellent, good, fair, poor
```

### Field Types

| Type | JSON Schema Type | Ruby Examples |
|---|---|---|
| `:string` | `"string"` | Short text values |
| `:text` | `"string"` | Long-form text |
| `:integer` | `"integer"` | Whole numbers |
| `:float` | `"number"` | Floating-point numbers |
| `:decimal` | `"number"` | Precise decimal values |
| `:boolean` | `"boolean"` | true/false |
| `:date` | `"string"` | Date values |
| `:datetime` | `"string"` | Date and time values |
| `:array` | `"array"` | Lists of values |

### Per-Model Custom Schema

Override the default schema for a specific model using `define_schema`:

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  define_schema(name: "sneaker", description: "Athletic footwear identification") do
    field :name, type: :string, required: true, description: "Sneaker model name"
    field :brand, type: :string, required: true, description: "Brand name",
      enum: %w[nike adidas jordan new_balance puma reebok other]
    field :colorway, type: :string, description: "Colorway name"
    field :style_code, type: :string, description: "Manufacturer style code"
    field :release_year, type: :integer, description: "Release year"
    field :size, type: :string, description: "Shoe size as printed"
    field :condition, type: :string, enum: %w[deadstock vnds excellent good beater]
    field :estimated_value, type: :decimal, description: "Estimated resale value in USD"
    field :authenticity_indicators, type: :array, description: "Features confirming authenticity"
  end
end
```

### Global Schema Override

Replace the default schema for all models that do not define their own:

```ruby
AiLens.configure do |config|
  config.default_schema = AiLens::Schema.define(
    name: "art_piece",
    description: "Fine art identification"
  ) do
    field :title, type: :string, required: true
    field :artist, type: :string
    field :medium, type: :string
    field :dimensions, type: :string
    field :period, type: :string
    field :estimated_value, type: :decimal
  end
end
```

### Building Schemas Programmatically

```ruby
schema = AiLens::Schema.new(name: "custom")
schema.field :name, type: :string, required: true
schema.field :year, type: :integer

schema.field_names        # => [:name, :year]
schema[:name].type        # => :string
schema[:name].required?   # => true
schema.has_field?(:year)  # => true
schema.required_fields    # => { name: #<SchemaField ...> }
schema.optional_fields    # => { year: #<SchemaField ...> }
schema.to_json_schema     # => { "type" => "object", "properties" => { ... }, "required" => ["name"] }
schema.to_prompt_description  # => "Extract the following fields:\n\n- name (The name) [required]\n..."
```

---

## Triggering Identification

### `identify!`

Call `identify!` on any model that includes `AiLens::Identifiable`:

```ruby
job = item.identify!
```

### Options

```ruby
job = item.identify!(
  adapter: :anthropic,           # Symbol: override the default adapter
  photos_mode: :multiple,        # :single or :multiple
  item_mode: :single,            # :single (only supported value in 0.3.0)
  user_feedback: "This is a 1st edition, not 2nd",  # Corrections from previous attempt
  context: "Found at an estate sale in Vermont"      # Additional context for the LLM
)
```

`adapter:` accepts either a single Symbol or an Array. Pass an Array to set the entire adapter chain in one kwarg — the first entry is primary and the rest are fallbacks, overriding both `default_adapter` and `fallback_adapters` from configuration:

```ruby
job = item.identify!(adapter: [:anthropic, :openai, :gemini])
```

The plural `adapters:` Array form is also accepted as a deprecated alias for back-compat with 0.2.x callers. Prefer `adapter:`.

> **Common typo guard:** Passing a non-Array value via `adapters:` (e.g. `adapters: :openai`) raises `ArgumentError` rather than being silently ignored. Pass single adapters via `adapter:`.

### Mode Combinations

| `photos_mode` | `item_mode` | Behavior |
|---|---|---|
| `:single` | `:single` | One photo, one item (default) |
| `:multiple` | `:single` | Multiple photos of the same item from different angles |

`item_mode: :multiple` is **planned** but not implemented in 0.3.0. Calling `identify!` with `item_mode: :multiple` raises `AiLens::NotImplementedError`. Use `item_mode: :single` (the default) to identify each photo's primary item.

### Status Checking

```ruby
item.identifying?          # => true if any job is pending or processing
item.identified?           # => true if any job has completed successfully
item.identifiable?         # => true if the model has photos available

job.status                 # => "pending", "processing", "completed", or "failed"
job.status_pending?        # => true/false
job.status_processing?     # => true/false
job.status_completed?      # => true/false
job.status_failed?         # => true/false
job.current_stage          # => "analyzing", "extracting", etc.
```

### Preventing Identification

A `before_identify` callback that returns `false` prevents the job
from being created. As of 0.3.0, `identify!` raises
`AiLens::IdentificationGated` in this case so callers can distinguish
"a callback gated this" from "no photos available" (which still
returns `nil`):

```ruby
begin
  job = item.identify!
rescue AiLens::IdentificationGated
  # before_identify said no — show a "buy more credits" CTA, etc.
end

# Returns nil only when there are simply no photos to identify:
item_with_no_photos.identify!  # => nil
```

---

## Photo Tags

Photo tags classify each photo by its purpose and content. The LLM scores every photo against a set of facets, producing a structured understanding of what each photo contributes to the identification.

### What They Are and Why They Matter

When a user uploads five photos of a collectible, those photos serve different purposes: one might show a serial number, another is a beauty shot, another documents damage. Photo tags let you programmatically distinguish these roles, enabling features like automatic hero image selection, identifier extraction, damage reporting, and intelligent photo ordering.

### Built-in Facets

| Facet | Description |
|---|---|
| `identifier` | Contains text, codes, serial numbers useful for deterministic identification |
| `showcase` | Visually appealing, hero-worthy, display-quality photo |
| `detail` | Close-up of specific feature, texture, flaw, or marking |
| `context` | Shows scale, environment, or provenance |
| `damage` | Documents wear, defects, or condition issues |
| `documentation` | Paperwork, receipts, certificates, provenance docs |

### Adding Custom Facets

Register additional facets in the initializer:

```ruby
AiLens.configure do |config|
  config.add_photo_tag_facet :packaging, "Shows original packaging, box, or case"
  config.add_photo_tag_facet :comparison, "Side-by-side comparison with reference item"
end
```

Custom facets are merged with the built-in set and sent to the LLM alongside them.

### Open Tagging

Enable open tagging to let the LLM invent facets beyond the defined set:

```ruby
AiLens.configure do |config|
  config.open_photo_tags = true
end
```

When enabled, the LLM can return additional facets in an `open_tags` array. These appear as novel `lowercase_snake_case` facet names with scores, accessible via `PhotoTagSet#open_tags` and `PhotoTagSet#all_tags`.

### Threshold Configuration

Only facets scoring above the threshold are included:

```ruby
AiLens.configure do |config|
  config.photo_tag_threshold = 0.3  # default
end
```

A threshold of `0.3` means a photo must score at least 30% relevance to a facet for that tag to appear.

### PhotoTagSet Methods

Each photo produces one `AiLens::PhotoTagSet` with these methods:

```ruby
tag_set = item.photo_tag_sets.first

tag_set.photo_index     # => 0 (which photo this refers to)
tag_set.tags            # => [{ facet: "showcase", score: 0.92 }, { facet: "detail", score: 0.45 }]
tag_set.open_tags       # => [{ facet: "vintage_patina", score: 0.7 }] (only with open tagging)
tag_set.all_tags        # => tags + open_tags combined

tag_set.tagged?(:showcase)  # => true
tag_set.tagged?(:damage)    # => false

tag_set.score(:showcase)    # => 0.92
tag_set.score(:damage)      # => 0.0 (returns 0.0 for untagged facets)

tag_set.primary_facet       # => :showcase (highest-scoring facet)
tag_set.facets              # => [:showcase, :detail] (all facets, ordered by score descending)
```

### Accessing Photo Tags from the Model

```ruby
# All photo tag sets from the latest identification
item.photo_tag_sets
# => [#<PhotoTagSet photo_index: 0, ...>, #<PhotoTagSet photo_index: 1, ...>, ...]

# Tags for a specific photo by index
item.photo_tags_for(0)
# => #<PhotoTagSet photo_index: 0, tags: [...], open_tags: [...]>

# Tags for a specific photo object
photo = item.photos.first
item.photo_tags_for(photo)
# => #<PhotoTagSet ...>
```

### Usage Examples

**Ordering photos by showcase quality:**

```ruby
ordered = item.photo_tag_sets
  .sort_by { |pts| -pts.score(:showcase) }
  .map { |pts| item.photos[pts.photo_index] }
```

**Selecting the hero image:**

```ruby
hero_index = item.photo_tag_sets
  .max_by { |pts| pts.score(:showcase) }
  &.photo_index

hero_photo = item.photos[hero_index] if hero_index
```

**Finding photos with identifiers (serial numbers, codes):**

```ruby
identifier_photos = item.photo_tag_sets
  .select { |pts| pts.tagged?(:identifier) }
  .map { |pts| item.photos[pts.photo_index] }
```

**Detecting damage photos:**

```ruby
damage_photos = item.photo_tag_sets
  .select { |pts| pts.tagged?(:damage) }
  .sort_by { |pts| -pts.score(:damage) }
```

**Discovering novel facets (open tagging):**

```ruby
novel_facets = item.photo_tag_sets
  .flat_map(&:open_tags)
  .group_by { |t| t[:facet] }
  .transform_values { |tags| tags.map { |t| t[:score] }.max }
# => { "vintage_patina" => 0.7, "handwritten_label" => 0.85 }
```

---

## Lifecycle Callbacks

Register callbacks at the class level. Each callback receives the model instance and, where applicable, the job and error.

> **These are not Rails-style callbacks.** ai-lens callbacks
> (`before_identify`, `after_identify`, `on_success`, `on_failure`,
> `on_stage_change`) are simple proc / method-symbol hooks. They do
> **not** support `:if`, `:unless`, `:only`, `:except`, `:prepend`, or
> any other Rails callback options. They do not participate in
> `ActiveSupport::Callbacks` chains, cannot be reordered, and cannot
> be skipped via `skip_callback`. They are registered on the class
> with `class_attribute` storage and run in registration order.
>
> If you need conditional execution, gate inside the proc:
>
> ```ruby
> before_identify ->(item) {
>   return true unless item.user.subscribed?
>   item.user.credits.positive?
> }
> ```
>
> If you need a "skip this callback" mechanism, set state on the
> instance and check it inside the callback. Real Rails callback
> semantics (with `:if`/`:unless`) may arrive in a future major
> version; for now treat these as plain proc hooks.

### `before_identify`

Runs before the job is created. Return `false` to prevent identification.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  # Block form
  before_identify ->(item) { item.user.credits.positive? }

  # Method name form
  before_identify :check_credits

  private

  def check_credits
    user.credits.positive?
  end
end
```

### `after_identify`

Runs after the job record is created and enqueued, but before processing begins.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  after_identify ->(item, job) {
    Rails.logger.info "Identification job #{job.id} enqueued for item #{item.id}"
  }
end
```

### `on_success`

Runs after the job completes successfully and attributes have been applied.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  on_success ->(item, job) {
    item.user.decrement!(:credits)
    ItemMailer.identification_complete(item).deliver_later
  }
end
```

### `on_failure`

Runs when the job fails after exhausting all adapters.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  on_failure ->(item, job, error) {
    ErrorTracker.notify(error, item_id: item.id, job_id: job.id)
  }
end
```

### `on_stage_change`

Runs every time the job transitions to a new processing stage. Ideal for real-time UI updates.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  on_stage_change ->(item, job, stage) {
    Turbo::StreamsChannel.broadcast_replace_to(
      item,
      target: "identification_progress",
      partial: "items/identification_stage",
      locals: { stage: stage, job: job }
    )
  }
end
```

### Multiple Callbacks

You can register multiple callbacks of the same type. They run in registration order.

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  identifiable_photos :photos

  on_success ->(item, job) { item.user.decrement!(:credits) }
  on_success ->(item, job) { item.broadcast_replace }
  on_success ->(item, job) { Analytics.track("identification_complete", item_id: item.id) }
end
```

---

## Progress Stages

Each identification job moves through seven stages, tracked in the `current_stage` column:

```ruby
AiLens::Job::STAGES
# => ["queued", "encoding", "analyzing", "extracting", "validating", "applying", "completed"]
```

| Stage | Description |
|---|---|
| `queued` | Job picked up by the worker |
| `encoding` | Photos are being preprocessed and encoded for the LLM |
| `analyzing` | Images sent to the LLM, waiting for response |
| `extracting` | Parsing structured data from the LLM response |
| `validating` | Validating extracted data against the schema |
| `applying` | Applying extracted attributes to the model |
| `completed` | Identification finished successfully |

### Updating Stages

Stages are updated internally by `ProcessIdentificationJob`. Each call to `update_stage!` persists the stage and fires `on_stage_change` callbacks:

```ruby
job.update_stage!("analyzing")
job.current_stage  # => "analyzing"
```

### Real-Time UI Integration

Combine `on_stage_change` with Turbo Streams for live progress:

```ruby
# app/models/item.rb
on_stage_change ->(item, job, stage) {
  Turbo::StreamsChannel.broadcast_replace_to(
    item,
    target: "identification_progress",
    partial: "items/identification_stage",
    locals: { stage: stage, stages: AiLens::Job::STAGES }
  )
}
```

```erb
<%# app/views/items/_identification_stage.html.erb %>
<div id="identification_progress">
  <% AiLens::Job::STAGES.each do |s| %>
    <span class="<%= s == stage ? 'active' : (AiLens::Job::STAGES.index(s) < AiLens::Job::STAGES.index(stage) ? 'done' : '') %>">
      <%= s.humanize %>
    </span>
  <% end %>
</div>
```

---

## Results

### Accessing Extracted Attributes

After a successful identification, access the extracted data:

```ruby
job = item.latest_completed_identification

# Parsed hash from encrypted JSON
job.parsed_extracted_attributes
# => {
#   "name" => "1993 Upper Deck Derek Jeter Rookie",
#   "category" => "sports_card",
#   "year" => 1993,
#   "condition" => "near_mint",
#   "estimated_value_low" => 150.0,
#   "estimated_value_high" => 300.0,
#   "confidence_score" => 0.87,
#   "counterfeit_risk" => 0.05,
#   "featured_photo_index" => 0,
#   "identifying_features" => ["hologram sticker", "card number SP3", "factory seal"],
#   "notes" => "PSA grading recommended for this card"
# }

# Raw LLM response (also encrypted)
job.parsed_llm_results
```

### Auto-Apply

Extracted attributes are automatically applied to the model upon successful job completion. The mapping defined by `identifiable_mapping` controls how field names are translated:

```ruby
# Extracted: { "name" => "...", "category" => "..." }
# Mapping:   { name: :title, category: :item_type }
# Result:    item.title = "...", item.item_type = "..."
```

Fields without a mapping entry are applied directly if the model responds to a setter of the same name. Only keys defined in the schema are applied — unknown keys returned by the LLM (e.g. `photo_tags`) are ignored.

### Manual Apply

To re-apply attributes from any completed job:

```ruby
item.apply_identification!(job)  # => true on success, false if job not completed or no data
```

### Latest Identification

```ruby
# Most recent successfully completed job (ordered by completed_at desc).
# Use this when you want extracted attributes / photo tag data.
job = item.latest_completed_identification

# Most recent identification job regardless of status — pending,
# processing, completed, or failed (ordered by created_at desc). Use
# this when you want to surface "we're working on it" / "we tried and
# failed" UI states.
job = item.latest_identification
```

**0.3.0 rename:** `latest_identification` previously returned only
completed jobs despite its name. The canonical accessor for "the
latest completed identification" is now
`latest_completed_identification`. `latest_identification` still
exists with name-true semantics — most recent job of any status. If
you used `latest_identification` to read extracted attributes, switch
to `latest_completed_identification` to preserve the old behavior.

### Job Attributes

```ruby
job.adapter              # => "anthropic" (the adapter that succeeded)
job.photos_mode          # => "multiple"
job.item_mode            # => "single"
job.context              # => "Found at an estate sale"
job.user_feedback        # => "This is a 1st edition"
job.schema_snapshot      # => { "type" => "object", "properties" => { ... } }
job.duration             # => 4.2 (seconds, nil if not finished)
job.retry?               # => true (if user_feedback is present)
job.started_at           # => 2026-04-24 10:00:00
job.completed_at         # => 2026-04-24 10:00:04
```

---

## User Feedback

The `AiLens::Feedback` model lets users report whether an identification was helpful and suggest corrections.

### Creating Feedback

```ruby
feedback = job.feedbacks.create!(
  helpful: false,
  comments: "The year is wrong, this is from 1952 not 1953",
  suggested_corrections: { "year" => 1952, "condition" => "good" }
)
```

### Helpful / Unhelpful

```ruby
# Scopes
AiLens::Feedback.helpful        # => helpful: true
AiLens::Feedback.not_helpful    # => helpful: false
AiLens::Feedback.with_corrections  # => has suggested_corrections
AiLens::Feedback.recent         # => ordered by created_at desc
```

### Automatic Re-identification

When feedback is created with `helpful: false` or with `suggested_corrections`, ai-lens automatically triggers a new identification on the same item, passing the combined feedback text to the LLM:

```ruby
# This triggers a new identify! call automatically
job.feedbacks.create!(
  helpful: false,
  comments: "Wrong card identified",
  suggested_corrections: { "name" => "1952 Topps Mickey Mantle #311" }
)
```

The new identification receives combined feedback from up to five most recent feedback records for the item, so the LLM can incorporate all corrections.

### Suppressing Auto-Reidentification

If your controller handles re-identification manually, set `skip_auto_reidentify`
to suppress the automatic trigger:

```ruby
feedback = job.feedbacks.build(
  helpful: false,
  comments: "Wrong item"
)
feedback.skip_auto_reidentify = true
feedback.save!

# Now handle re-identification yourself
item.identify!(user_feedback: feedback.feedback_text)
```

This accessor was renamed from `reidentify_requested` in 0.2.1 because the
previous name shadowed any real `reidentify_requested` DB column in the host
app, silently preventing persistence of that column.

### Combined Feedback Text

```ruby
feedback.feedback_text
# => "User comments: The year is wrong\nSuggested corrections: year: 1952, condition: good"
```

---

## Fallback Adapters

ai-lens automatically falls through a chain of LLM providers when the primary adapter fails.

### Simple Mode

Use a single adapter with the default fallback chain:

```ruby
AiLens.configure do |config|
  config.default_adapter = :openai
  config.fallback_adapters = [:anthropic, :grok, :gemini]
end

# OpenAI fails -> tries Anthropic -> tries Grok -> tries Gemini -> fails
item.identify!
```

### Router Mode

Use ai-loom's router to select the adapter by task:

```ruby
AiLens.configure do |config|
  config.task = :photo_identification
end

# ai-loom's router picks the adapter for the :photo_identification task
item.identify!
```

If the router raises an `AiLoom::AdapterError`, ai-lens falls back to the `default_adapter`.

### Per-Call Fallback Chain

Override the entire adapter chain for a single call:

```ruby
job = item.identify!(adapters: [:anthropic, :openai, :gemini])
# Anthropic is primary, OpenAI and Gemini are fallbacks
```

### Inspecting Tried Adapters

After a job completes (especially via fallback), inspect which adapters were attempted:

```ruby
job = item.latest_completed_identification
job.adapter  # => "grok" (the adapter that succeeded)

# All adapters that were tried
job.error_details&.dig("tried_adapters")
# => ["openai", "anthropic", "grok"]
```

---

## Custom Prompt Templates

Override ai-lens's built-in prompts with a YAML file containing ERB templates.

### YAML Format

```yaml
# config/identification_prompts.yml
system_prompt: |
  You are an expert gemologist specializing in precious stones.
  Always respond with valid JSON.

# Default prompt used when no mode-specific key matches
prompt: |
  Identify the gemstone in the photo.
  <%= schema_description %>
  <% if has_context %>
  Context: <%= context %>
  <% end %>

# Mode-specific prompts
single_photo_single_item: |
  Analyze this single photo of a gemstone.
  <%= schema_description %>

single_photo_multiple_item: |
  Analyze this photo showing multiple gemstones. Return an "items" array.
  <%= schema_description %>

multiple_photo_single_item: |
  These photos show the same gemstone from different angles.
  <%= schema_description %>

multiple_photo_multiple_item: |
  These photos show multiple gemstones. Return an "items" array.
  <%= schema_description %>
```

### Configuration

```ruby
AiLens.configure do |config|
  config.prompt_template = Rails.root.join("config/identification_prompts.yml")
end
```

### ERB Variables

These variables are available in templates:

| Variable | Type | Description |
|---|---|---|
| `schema` | `AiLens::Schema` | The schema object |
| `schema_description` | `String` | Human-readable field descriptions |
| `schema_fields` | `Hash` | Map of field name to `SchemaField` |
| `context` | `String/nil` | User-provided context |
| `user_feedback` | `String/nil` | Feedback from previous attempt |
| `has_context` | `Boolean` | Whether context is present |
| `has_feedback` | `Boolean` | Whether user_feedback is present |
| `photos_mode` | `Symbol` | `:single` or `:multiple` |
| `item_mode` | `Symbol` | `:single` or `:multiple` |

### Template Helper Methods

| Method | Returns |
|---|---|
| `single_photo?` | `true` if photos_mode is `:single` |
| `multiple_photos?` | `true` if photos_mode is `:multiple` |
| `single_item?` | `true` if item_mode is `:single` |
| `multiple_items?` | `true` if item_mode is `:multiple` |

### Mode Keys

The prompt key is determined by the mode combination as `{photos_mode}_photo_{item_mode}_item`. If no matching key exists, ai-lens falls back to the `prompt` key, then `default`, then the built-in prompt.

---

## Background Jobs

### ProcessIdentificationJob

The main job that processes identifications. It handles the full lifecycle: encoding images, building prompts, calling the LLM, parsing results, applying attributes, and running callbacks.

**Retry behavior:**

| Error Type | Strategy | Attempts |
|---|---|---|
| `AiLoom::RateLimitError` | Polynomial backoff | `max_retries` (default 3) |
| `AiLoom::TimeoutError` | Fixed delay (`retry_delay`) | `max_retries` (default 3) |
| `AiLoom::AuthenticationError` | Discarded immediately | 0 |
| Other `AiLoom::AdapterError` | Falls back to next adapter | All adapters in chain |
| Unexpected errors | Fails the job | 0 |

**Queue configuration:**

```ruby
AiLens.configure do |config|
  config.queue_name = :identification  # default is :default
  config.max_retries = 5
  config.retry_delay = 10
end
```

### RecoverStuckJobsJob

Finds jobs stuck in `pending` or `processing` state for longer than `stuck_job_threshold` and retries them with the next adapter in the fallback chain. If all adapters have been tried, the job is marked as failed.

**Scheduling:**

Add to your scheduler (e.g., `solid_queue.yml`, `sidekiq-cron`, or `whenever`):

```ruby
# solid_queue.yml
recurring:
  recover_stuck_ai_lens_jobs:
    class: AiLens::RecoverStuckJobsJob
    schedule: every 15 minutes
```

```ruby
# Or trigger manually
AiLens::RecoverStuckJobsJob.perform_later
```

```ruby
# Or from a cron-style scheduler
AiLens::RecoverStuckJobsJob.perform_later  # recommended: run every 15 minutes
```

---

## Job Model

`AiLens::Job` is an ActiveRecord model stored in the `ai_lens_jobs` table.

### Database Columns

| Column | Type | Description |
|---|---|---|
| `identifiable_type` | string | Polymorphic type (e.g., "Item") |
| `identifiable_id` | integer | Polymorphic ID |
| `adapter` | string | LLM adapter used (or that succeeded) |
| `photos_mode` | string | "single" or "multiple" |
| `item_mode` | string | "single" or "multiple" |
| `context` | text | Additional context for the LLM |
| `user_feedback` | text | Feedback from a previous attempt (encrypted) |
| `schema_snapshot` | json | Schema as JSON at time of job creation |
| `status` | string | "pending", "processing", "completed", "failed" |
| `current_stage` | string | Current processing stage |
| `started_at` | datetime | When processing began |
| `completed_at` | datetime | When processing finished |
| `extracted_attributes` | text | Extracted data as JSON (encrypted) |
| `llm_results` | text | Raw LLM response (encrypted) |
| `error_message` | string | Error message if failed |
| `error_details` | json | Error details, tried adapters, fallback info |
| `created_at` | datetime | Record creation time |
| `updated_at` | datetime | Last update time |

### Scopes

```ruby
AiLens::Job.pending_or_processing  # status is pending or processing
AiLens::Job.completed              # status is completed
AiLens::Job.failed                 # status is failed
AiLens::Job.stuck                  # pending/processing and created > 1 hour ago
AiLens::Job.recent                 # ordered by created_at desc
```

### Encryption

Four columns are encrypted via `ActiveRecord::Encryption` when the host app
has configured encryption (see [ActiveRecord Encryption](#activerecord-encryption)):

- `AiLens::Job#extracted_attributes` -- the structured data extracted by the LLM
- `AiLens::Job#llm_results` -- the full raw response from the LLM
- `AiLens::Job#user_feedback` -- user-provided feedback text
- `AiLens::Feedback#comments` -- user comments on a feedback record

These columns are stored as `text` in the database to support encryption. Use the parsed methods to access them as hashes:

```ruby
job.parsed_extracted_attributes  # => { "name" => "...", ... }
job.parsed_llm_results           # => { "content" => "...", ... }
```

#### JSON columns are not encrypted

`AiLens::Feedback#suggested_corrections` is declared as `t.json` in the
install migration. Active Record encryption does **not** support
JSON-typed columns — the encryption layer returns its ciphertext as a
string, which Postgres rejects when writing back to a `json` column. So
this column remains plaintext even when the host has configured Active
Record encryption.

If your application needs `suggested_corrections` encrypted, change
the column type to `t.text` and serialize the hash to JSON yourself
before assigning. The data-migration risk for an existing database
made it inappropriate to flip this in 0.3.0; this note is here so the
contract is unambiguous.

### Parsed Methods

```ruby
job.parsed_extracted_attributes  # JSON string -> Hash, returns {} on parse error
job.parsed_llm_results           # JSON string -> Hash, returns {} on parse error
job.photo_tag_sets               # Array of PhotoTagSet from llm_results["photo_tags"]
job.photo_tags_for(0)            # PhotoTagSet for photo at index 0
job.duration                     # Float seconds between started_at and completed_at
job.retry?                       # true if user_feedback is present
job.adapters_to_try              # [primary_adapter] + fallback_adapters, deduped
```

---

## Error Handling

### AiLens Error Hierarchy

All errors raised by ai-lens descend from `AiLens::Error < StandardError`,
so a host can catch every gem-defined failure with one rescue clause:

```ruby
begin
  item.identify!
rescue AiLens::Error => e
  # any ai-lens failure
end
```

| Error | Raised when |
|---|---|
| `AiLens::Error` | Base class — catch this to rescue any ai-lens failure |
| `AiLens::ConfigurationError` | Host-side configuration is missing or invalid |
| `AiLens::Identifiable::NotConfiguredError` | `identifiable_photos` not declared on a model (subclass of `ConfigurationError`) |
| `AiLens::SchemaError` | A `Schema` is malformed |
| `AiLens::ValidationError` | An LLM response failed schema validation; `#violations` lists the failures |
| `AiLens::NotImplementedError` | A feature requested is not yet implemented (e.g. `item_mode: :multiple` in 0.3.0) |
| `AiLens::IdentificationGated` | A `before_identify` callback returned false |

### Error Types from ai-loom

| Error | Behavior |
|---|---|
| `AiLoom::RateLimitError` | Retried with polynomial backoff |
| `AiLoom::TimeoutError` | Retried after `retry_delay` seconds |
| `AiLoom::AuthenticationError` | Job discarded immediately (bad API key) |
| `AiLoom::AdapterError` | Falls back to next adapter in chain |

### Retry Behavior

Retries are handled at two levels:

1. **ActiveJob retries** -- `RateLimitError` and `TimeoutError` are retried by ActiveJob up to `max_retries` times.
2. **Adapter fallback** -- any `AdapterError` (including after ActiveJob retries are exhausted) triggers the fallback chain. Each adapter in the chain gets one attempt.

### Failure Inspection

When a job fails:

```ruby
job = item.ai_lens_jobs.failed.last

job.error_message   # => "All adapters exhausted"
job.error_details   # => { "error_class" => "AiLoom::RateLimitError", "tried_adapters" => ["openai", "anthropic", "grok"] }
job.status_failed?  # => true
```

The `on_failure` callback fires with the error message:

```ruby
on_failure ->(item, job, error) {
  Sentry.capture_message(error, extra: { job_id: job.id, details: job.error_details })
}
```

---

## Image Processing

ai-lens preprocesses images before sending them to the LLM using ActiveStorage variants.

### Variant Options

```ruby
AiLens.configure do |config|
  # Resize to fit within 2048x2048, maintaining aspect ratio
  config.image_variant_options = { resize_to_limit: [2048, 2048] }
end
```

### Format Conversion

Convert HEIC or other formats to JPEG before sending:

```ruby
AiLens.configure do |config|
  config.image_variant_options = {
    resize_to_limit: [2048, 2048],
    format: :jpeg
  }
end
```

When a `format` key is present in variant options, ai-lens uses the correct MIME type (`image/jpeg`) regardless of the original file's content type. This is important for HEIC images from iPhones.

### Dimension Limits

The standalone preprocessing knobs are wired into the variant options
ai-lens passes to ActiveStorage. Configure them individually:

```ruby
AiLens.configure do |config|
  config.max_image_dimension = 2048  # resizes to fit within N x N
  config.image_quality = 85          # JPEG quality (1-100), passed to libvips/ImageMagick saver
  config.image_format = :jpeg        # output format coercion (HEIC -> JPEG, etc.)
end
```

These three values produce a variant equivalent to:

```ruby
{ resize_to_limit: [max_image_dimension, max_image_dimension],
  saver: { quality: image_quality },
  format: image_format }
```

Anything you set explicitly via `config.image_variant_options` takes
precedence over these defaults — so you can override individual keys
without losing the others.

### Supported Photo Types

ai-lens handles several photo source types:

- **ActiveStorage attachments** with variant support -- preprocessed via variants, then downloaded and base64-encoded
- **ActiveStorage attachments** without variant support -- downloaded and base64-encoded directly
- **Objects responding to `.url`** -- the URL is passed to the LLM directly
- **String file paths or URLs** -- normalized via `AiLoom::ImageEncoder`

If variant processing fails for any photo, ai-lens falls back to the original image and logs a warning.

---

## Upgrading from photo_identification

If you are upgrading from an earlier version named `photo_identification`, follow these steps:

### Module Rename

Replace all references to the old module name:

```ruby
# Before
include PhotoIdentification::Identifiable

# After
include AiLens::Identifiable
```

### Table Renames

Create a migration to rename the database tables:

```ruby
class RenamePhotoIdentificationTables < ActiveRecord::Migration[8.0]
  def change
    rename_table :photo_identification_jobs, :ai_lens_jobs
    rename_table :photo_identification_feedbacks, :ai_lens_feedbacks
  end
end
```

### Configuration

```ruby
# Before
PhotoIdentification.configure do |config|
  # ...
end

# After
AiLens.configure do |config|
  # ...
end
```

### Initializer

Replace `config/initializers/photo_identification.rb` with `config/initializers/ai_lens.rb`. Run the generator to create the new initializer, then copy your custom settings:

```bash
bin/rails generate ai_lens:install
```

The generator will not overwrite existing migrations, so you only need the initializer from this step.

### Class References

| Before | After |
|---|---|
| `PhotoIdentification::Job` | `AiLens::Job` |
| `PhotoIdentification::Feedback` | `AiLens::Feedback` |
| `PhotoIdentification::Schema` | `AiLens::Schema` |
| `PhotoIdentification::ProcessIdentificationJob` | `AiLens::ProcessIdentificationJob` |
| `PhotoIdentification::RecoverStuckJobsJob` | `AiLens::RecoverStuckJobsJob` |

---

## License

ai-lens is released under the [MIT License](LICENSE.txt).
