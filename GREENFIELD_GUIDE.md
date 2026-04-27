# ai-loom & ai-lens Greenfield Integration Guide

A practical reference for integrating ai-loom and/or ai-lens into a Rails codebase from scratch. Written for developers and AI sessions.

---

## 1. When to Use What

### Decision Tree

- **ai-loom only** -- You need to call LLMs (chat, vision, embeddings, streaming, TTS, tool calling) from your Rails app. You do not need photo identification.
- **ai-lens only** -- Not possible. ai-lens depends on ai-loom.
- **ai-loom + ai-lens** -- You need AI-powered photo identification: extracting structured data from photos using LLM vision, with automatic attribute application, fallback chains, and background processing.

### Feature Table

| Feature | ai-loom | ai-lens |
|---------|---------|---------|
| Chat completions (single and multi-turn) | Yes | -- |
| Streaming responses | Yes | -- |
| Embeddings | Yes | -- |
| Vision / image analysis | Yes | -- |
| Structured extraction (JSON mode) | Yes | -- |
| Text-to-speech | Yes (OpenAI only) | -- |
| Tool/function calling | Yes | -- |
| Task router (map tasks to providers) | Yes | -- |
| Traits (AI personality via YAML) | Yes | -- |
| Skills (sandboxed capabilities) | Yes | -- |
| Prompt builder (composable system prompts) | Yes | -- |
| Conversation tracking (ActiveRecord) | Yes | -- |
| Content guard (violation detection) | Yes | -- |
| Rate limiter (memory/Redis) | Yes | -- |
| Test adapter (no API calls) | Yes | -- |
| Photo identification from images | -- | Yes |
| Configurable extraction schemas | -- | Yes |
| Photo tagging (purpose classification) | -- | Yes |
| Lifecycle callbacks (before/after/success/failure) | -- | Yes |
| Background job processing with stage tracking | -- | Yes |
| User feedback and re-identification | -- | Yes |
| Automatic provider fallback for identification | -- | Yes |
| Encrypted storage of LLM results | -- | Yes |

### Supported Providers

| Provider | Adapter Key | Chat | Stream | Embed | Vision | Tools | TTS |
|----------|-------------|------|--------|-------|--------|-------|-----|
| OpenAI | `:openai` | Yes | Yes | Yes | Yes | Yes | Yes |
| Anthropic | `:anthropic` / `:claude` | Yes | Yes | No | Yes | Yes | No |
| Google Gemini | `:gemini` / `:google` | Yes | Yes | Yes | Yes | Yes | No |
| xAI Grok | `:grok` / `:xai` | Yes | Yes | Yes | Yes | Yes | No |
| Test | `:test` | Yes | Yes | Yes | Yes | No | No |

---

## 2. Installation

### ai-loom Only

Add to your Gemfile:

```ruby
# Local development (path-based)
gem "ai-loom", path: "../ai-loom"

# Deploy (GitHub-based)
gem "ai-loom", github: "your-username/ai-loom", branch: "main"
```

Run:

```bash
bundle install
```

No generators are required for basic ai-loom usage. The Rails Engine auto-loads credentials.

**Optional: Conversation tracking migration**

If you want to persist conversation history with token/cost tracking:

```bash
bin/rails generate ai_loom:conversations
bin/rails db:migrate
```

This creates two migration files: `create_ai_loom_conversations` and `create_ai_loom_conversation_messages`.

### ai-loom + ai-lens

Add both to your Gemfile:

```ruby
# Local development
gem "ai-loom", path: "../ai-loom"
gem "ai-lens", path: "../ai-lens"

# Deploy
gem "ai-loom", github: "your-username/ai-loom", branch: "main"
gem "ai-lens", github: "your-username/ai-lens", branch: "main"
```

Run:

```bash
bundle install
bin/rails generate ai_lens:install
bin/rails db:migrate
```

The `ai_lens:install` generator creates:
- `db/migrate/..._create_ai_lens_jobs.rb` -- the jobs table
- `db/migrate/..._create_ai_lens_feedbacks.rb` -- the feedback table
- `config/initializers/ai_lens.rb` -- configuration file

**ActiveRecord Encryption** (required by ai-lens):

ai-lens encrypts sensitive columns. If you have not configured ActiveRecord encryption:

```bash
bin/rails db:encryption:init
```

Add the output to your credentials file under `active_record_encryption`.

### Credentials Setup

Edit your Rails credentials:

```bash
bin/rails credentials:edit
```

Add API keys for the providers you plan to use:

```yaml
openai:
  api_key: sk-...
  organization_id: org-...     # optional
  model: gpt-4o               # optional, this is the default

anthropic:
  api_key: sk-ant-...
  model: claude-sonnet-4-20250514  # optional, this is the default

gemini:
  api_key: AIza...
  model: gemini-2.0-flash     # optional, this is the default

xai:
  api_key: xai-...
  model: grok-3               # optional, this is the default
```

The ai-loom Rails Engine automatically reads these credentials at boot. No initializer is required for basic usage.

**Manual configuration** (non-Rails or to override credentials):

```ruby
# config/initializers/ai_loom.rb
AiLoom.configure do |config|
  config.openai    = { api_key: ENV["OPENAI_API_KEY"] }
  config.anthropic = { api_key: ENV["ANTHROPIC_API_KEY"] }
  config.gemini    = { api_key: ENV["GEMINI_API_KEY"] }
  config.grok      = { api_key: ENV["XAI_API_KEY"] }
end
```

---

## 3. Quick Start: ai-loom

### 3.1 Simple Chat Completion

```ruby
adapter = AiLoom.adapter(:openai)
response = adapter.complete(prompt: "What is Ruby?")
puts response.content
```

### 3.2 Multi-Turn Conversation

```ruby
adapter = AiLoom.adapter(:anthropic)

messages = [
  { role: "user", content: "What is the capital of France?" },
  { role: "assistant", content: "The capital of France is Paris." },
  { role: "user", content: "What is its population?" }
]

response = adapter.chat(
  messages: messages,
  system_prompt: "You are a helpful geography assistant."
)

puts response.content
```

### 3.3 JSON Mode / Structured Extraction

```ruby
adapter = AiLoom.adapter(:openai)

response = adapter.complete(
  prompt: "List 3 programming languages with their creators.",
  json_mode: true
)

data = response.json_content
# => { "languages" => [{ "name" => "Ruby", "creator" => "Yukihiro Matsumoto" }, ...] }

# Strict parsing (raises AiLoom::InvalidResponseError on failure):
data = response.json_content!
```

For schema-driven extraction:

```ruby
schema = {
  type: "object",
  properties: {
    name: { type: "string" },
    email: { type: "string" },
    company: { type: "string" }
  },
  required: ["name", "email"]
}

response = adapter.extract(
  text: "Hi, I'm Jane Smith from Acme Corp. Reach me at jane@acme.com.",
  schema: schema
)

contact = response.json_content
# => { "name" => "Jane Smith", "email" => "jane@acme.com", "company" => "Acme Corp" }
```

### 3.4 Vision / Image Analysis

```ruby
adapter = AiLoom.adapter(:openai)

response = adapter.analyze_with_images(
  prompt: "Describe what you see in this image.",
  image_urls: ["https://example.com/photo.jpg"],
  json_mode: true
)

puts response.json_content
```

With local files or ActiveStorage attachments:

```ruby
# Local file
data_url = AiLoom::ImageEncoder.encode_file("/path/to/photo.jpg")

# ActiveStorage attachment (resized to 1024x1024 for token efficiency)
data_url = AiLoom::ImageEncoder.encode_attachment(user.avatar)

# Mixed sources (auto-detects URLs, file paths, ActiveStorage)
images = AiLoom::ImageEncoder.normalize_all([
  "https://example.com/image.jpg",
  "/path/to/local/file.png",
  user.avatar
])

response = adapter.analyze_with_images(
  prompt: "Compare these images.",
  image_urls: images
)
```

### 3.5 Streaming

```ruby
adapter = AiLoom.adapter(:openai)

response = adapter.stream(
  messages: [{ role: "user", content: "Write a haiku about Ruby." }],
  system_prompt: "You are a poet."
) do |chunk|
  print chunk  # each token as it arrives
end

puts "\nTotal tokens: #{response.usage[:total_tokens]}"
```

### 3.6 Tool/Function Calling

Define tools:

```ruby
tools = [
  {
    name: "get_weather",
    description: "Get the current weather for a location.",
    parameters: {
      type: "object",
      properties: {
        location: { type: "string", description: "City and state, e.g. San Francisco, CA" },
        unit: { type: "string", enum: ["celsius", "fahrenheit"] }
      },
      required: ["location"]
    }
  }
]
```

Send tools with a chat request:

```ruby
adapter = AiLoom.adapter(:openai)

response = adapter.chat(
  messages: [{ role: "user", content: "What's the weather in Paris?" }],
  tools: tools
)
```

Handle tool calls:

```ruby
if response.tool_use?
  response.tool_calls.each do |tool_call|
    puts tool_call[:id]         # "call_abc123"
    puts tool_call[:name]       # "get_weather"
    puts tool_call[:arguments]  # { "location" => "Paris, France" }
  end
end
```

Build tool results (format varies by provider -- `ToolResult.build` handles this):

```ruby
result = AiLoom::ToolResult.build(
  tool_call_id: "call_abc123",
  content: '{"temperature": 22, "unit": "celsius"}',
  adapter: :openai
)
```

Full multi-turn tool use loop:

```ruby
adapter = AiLoom.adapter(:openai)
messages = [{ role: "user", content: "What's the weather in Paris and London?" }]

loop do
  response = adapter.chat(messages: messages, tools: tools)

  unless response.tool_use?
    puts response.content
    break
  end

  # Add assistant message with tool calls to history
  messages << { role: "assistant", content: response.content }

  # Execute each tool call and add results
  response.tool_calls.each do |tool_call|
    result = execute_tool(tool_call[:name], tool_call[:arguments])
    messages << AiLoom::ToolResult.build(
      tool_call_id: tool_call[:id],
      content: result.to_json,
      adapter: :openai
    )
  end
end
```

---

## 4. Quick Start: ai-lens

### 4.1 Model Setup

```ruby
# app/models/item.rb
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos

  identifiable_photos :photos

  identifiable_mapping(
    name: :title,
    category: :item_type,
    description: :notes
  )
end
```

The default schema extracts 17 fields suited for collectibles (name, category, year, condition, estimated values, etc.). See section 5.8 for custom schemas.

### 4.2 Trigger Identification

```ruby
item = Item.find(1)
job = item.identify!
```

With options:

```ruby
job = item.identify!(
  adapter: :anthropic,
  photos_mode: :multiple,
  item_mode: :single,
  context: "Found at an estate sale in Vermont"
)
```

### 4.3 Check Results

```ruby
item.identifying?          # => true (pending or processing)
item.identified?           # => true (completed successfully)

job = item.latest_identification
job.status                 # => "completed"

job.parsed_extracted_attributes
# => { "name" => "1952 Topps Mickey Mantle", "category" => "trading_card", ... }
```

Extracted attributes are automatically written to the model on job completion, using the mapping defined in `identifiable_mapping`. Only keys declared in the schema are applied to the host model.

### 4.4 Handle Callbacks

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos
  identifiable_photos :photos

  before_identify ->(item) { item.user.credits.positive? }

  on_success ->(item, job) {
    item.user.decrement!(:credits)
  }

  on_failure ->(item, job, error) {
    ErrorTracker.notify(error, item_id: item.id)
  }

  on_stage_change ->(item, job, stage) {
    Turbo::StreamsChannel.broadcast_replace_to(
      item, target: "identification_status",
      partial: "items/identification_stage", locals: { stage: stage }
    )
  }
end
```

---

## 5. Progressive Feature Adoption

Each subsection is self-contained. Adopt any feature independently.

### 5.1 Task Router

**When:** You call different LLMs for different tasks (e.g., creative writing on Anthropic, embeddings on OpenAI).

**Configuration:**

```ruby
# config/initializers/ai_loom.rb
AiLoom.configure do |config|
  config.router.route :creative_writing,
    primary: :anthropic,
    fallbacks: [:openai, :gemini]

  config.router.route :code_generation,
    primary: :openai,
    fallbacks: [:anthropic]

  config.router.route :embedding,
    primary: :openai,
    fallbacks: [:gemini]

  config.router.route :vision,
    primary: :gemini,
    fallbacks: [:openai, :grok]
end
```

**Usage:**

```ruby
# Get the primary adapter for a task
adapter = AiLoom.router.for(:creative_writing)
response = adapter.complete(prompt: "Write a short story about a robot.")

# Check which provider is primary
AiLoom.router.primary(:creative_writing)
# => :anthropic

# Get the full fallback chain
AiLoom.router.fallback_chain(:creative_writing)
# => [:anthropic, :openai, :gemini]

# Implement fallback logic
def chat_with_fallback(task, **kwargs)
  AiLoom.router.fallback_chain(task).each do |adapter_name|
    adapter = AiLoom.adapter(adapter_name)
    next unless adapter.available?
    return adapter.chat(**kwargs)
  rescue AiLoom::AdapterError
    next
  end
  raise "All adapters failed for #{task}"
end
```

**ai-lens router integration:**

```ruby
# config/initializers/ai_lens.rb
AiLens.configure do |config|
  config.task = :photo_identification
end

# config/initializers/ai_loom.rb
AiLoom.configure do |config|
  config.router.route :photo_identification,
    primary: :openai,
    fallbacks: [:anthropic, :gemini]
end
```

### 5.2 Traits (AI Personality)

**When:** You want configurable AI personalities with guardrails defined in YAML files.

**Create a trait file** at `config/ai_loom/traits/brand_voice.yml`:

```yaml
name: brand_voice
personality:
  - Warm and encouraging, like a knowledgeable friend
  - Uses clear, jargon-free language
  - Celebrates user progress with genuine enthusiasm
anti_traits:
  - Never use corporate buzzwords or filler phrases
  - Never be condescending or patronizing
  - Never make promises about future features
prompt_fragments:
  identity: |
    You are the voice of Acme, a developer tools company.
    You speak as a helpful colleague, not a corporate entity.
  boundaries: |
    You only discuss topics related to software development and our products.
    Redirect off-topic questions politely.
  style_guide: |
    - Use active voice
    - Keep sentences under 20 words
    - Use code examples instead of lengthy explanations
```

**Load and use:**

```ruby
trait = AiLoom::Trait.load(:brand_voice)

trait.name               # => "brand_voice"
trait.personality         # => ["Warm and encouraging...", ...]
trait.anti_traits         # => ["Never use corporate buzzwords...", ...]
trait.prompt_fragments    # => { "identity" => "You are...", ... }
```

**Use as a system prompt:**

```ruby
system_prompt = <<~PROMPT
  #{trait.prompt_fragments["identity"]}

  ## Personality
  #{trait.personality.map { |p| "- #{p}" }.join("\n")}

  ## Rules
  #{trait.anti_traits.map { |a| "- #{a}" }.join("\n")}
PROMPT

response = adapter.complete(prompt: user_message, system_prompt: system_prompt)
```

**Compose multiple traits:**

```ruby
composer = AiLoom::TraitComposer.new(:brand_voice, :support_agent)

composer.personality     # merged, deduplicated array from both traits
composer.anti_traits     # merged, deduplicated array from both traits
composer.fragment(:identity)  # first non-empty fragment for this key
```

**Custom load path:**

```ruby
AiLoom::Trait.load_path = Rails.root.join("config", "traits").to_s
```

**Cache control:**

```ruby
AiLoom::Trait.reset_cache!
```

### 5.3 Skills (Sandboxed AI Abilities)

**When:** You want the LLM to execute actions in your app via tool use / function calling.

**Define a skill:**

```ruby
# app/skills/search_docs_skill.rb
class SearchDocsSkill < AiLoom::Skill
  def skill_name
    "search_docs"
  end

  def description
    "Search the documentation for relevant articles."
  end

  def input_schema
    {
      type: "object",
      properties: {
        query: { type: "string", description: "Search query" },
        limit: { type: "integer", description: "Max results to return" }
      },
      required: ["query"]
    }
  end

  def authorized?(context = {})
    context[:user]&.can_search_docs?
  end

  def execute!(params, context = {})
    results = DocsSearch.call(params["query"], limit: params["limit"] || 5)
    { content: results.map(&:to_h) }
  end
end
```

**Register the skill:**

```ruby
# config/initializers/skills.rb
AiLoom::SkillRegistry.register(SearchDocsSkill)
```

**Generate tool definitions for the LLM:**

```ruby
tool_defs = AiLoom::SkillRegistry.tool_definitions(user: current_user)
# => [{ name: "search_docs", description: "Search the...", input_schema: { ... } }]
```

**Send tool definitions to the LLM, handle tool calls, execute skills:**

```ruby
adapter = AiLoom.adapter(:openai)
executor = AiLoom::SkillExecutor.new(context: { user: current_user })
tool_defs = AiLoom::SkillRegistry.tool_definitions(user: current_user)
messages = [{ role: "user", content: "Find docs about authentication" }]

loop do
  response = adapter.chat(messages: messages, tools: tool_defs)

  unless response.tool_use?
    puts response.content
    break
  end

  messages << { role: "assistant", content: response.content }

  response.tool_calls.each do |tool_call|
    result = executor.execute(tool_call[:name], tool_call[:arguments])
    messages << AiLoom::ToolResult.build(
      tool_call_id: tool_call[:id],
      content: result[:content].to_json,
      adapter: :openai
    )
  end
end

# Side effects collected from all executions
executor.side_effects
```

### 5.4 Prompt Builder

**When:** You are building complex system prompts from multiple sources (traits, skills, context, security rules).

```ruby
prompt = AiLoom::PromptBuilder.new
  .traits(:brand_voice, :support_agent)
  .skills(context: { user: current_user })
  .injection_shield
  .context(:current_page, "User is viewing the billing settings page.")
  .context(:user_plan, "Pro plan, active since January 2024.")
  .section(:custom_rules, "Always suggest the FAQ before escalating to support.")
  .build

adapter.complete(prompt: user_message, system_prompt: prompt)
```

**How it works:**

1. `.traits(:brand_voice, :support_agent)` -- loads named traits and adds sections for `:identity`, `:boundaries`, `:personality`, `:anti_traits`, `:style_guide` from their YAML fragments.
2. `.skills(context:)` -- queries `SkillRegistry` for available tool definitions, adds an `:available_tools` section.
3. `.injection_shield` -- adds a `:security` section with rules against prompt injection, persona override, and instruction leaking.
4. `.context(name, content)` -- adds an arbitrary named section.
5. `.section(name, content)` -- adds a named section (also accepts a block).
6. `.build` -- joins all sections into a single string.
7. `.to_h` -- returns `{ section_name: content }` for inspection.

**Real-world example:**

```ruby
builder = AiLoom::PromptBuilder.new

builder.section(:identity, "You are Acme Assistant, a helpful support bot.")
builder.section(:rules) { "Always be polite. Never share internal data." }
builder.traits(:brand_voice)
builder.skills(context: { user: current_user })
builder.injection_shield
builder.context(:session, "User has been active for 12 minutes.")

system_prompt = builder.build
sections_hash = builder.to_h
```

### 5.5 Content Guard

**When:** You need to detect and block certain types of LLM output (legal advice, medical advice, financial advice, competitor mentions, etc.).

**Default rules** (legal, medical, financial advice detection):

```ruby
guard = AiLoom::ContentGuard.default

guard.violates?("You should consult a lawyer about this.")
# => true

guard.violations("You should consult a lawyer and you should invest in stocks.")
# => [:legal_advice, :financial_advice]

clean = guard.sanitize("You could sue them for damages.")
# => "For legal matters, please consult a qualified attorney."
```

**Custom rules:**

```ruby
guard = AiLoom::ContentGuard.new

guard.add_rule(
  category: :competitor_mention,
  patterns: ["Competitor Corp", /rival\s+product/i],
  replacement: "Please contact our sales team for comparisons."
)

guard.add_rule(
  category: :profanity,
  patterns: [/\bbadword\b/i],
  replacement: ""
)

guard.violates?("Have you tried Competitor Corp?")
# => true

guard.violations("Have you tried Competitor Corp?")
# => [:competitor_mention]
```

String patterns are automatically wrapped as case-insensitive word-boundary regexps. Regexp patterns are used as-is.

**Global configuration:**

```ruby
AiLoom.configure do |config|
  config.content_guard = AiLoom::ContentGuard.default
end
```

### 5.6 Rate Limiter

**When:** You need to prevent abuse of LLM calls (per-user, per-endpoint, etc.).

**Memory backend** (single-process):

```ruby
limiter = AiLoom::RateLimiter.new(backend: :memory)

limiter.check!("user:42:chat", limit: 10, window: 60)
# => 1 (current count within window)
```

**Handle limit exceeded:**

```ruby
begin
  limiter.check!("user:42:chat", limit: 10, window: 60)
rescue AiLoom::RateLimiter::LimitExceeded => e
  e.key     # => "user:42:chat"
  e.limit   # => 10
  e.window  # => 60
  e.count   # => 11
  render json: { error: "Too many requests. Try again in #{e.window} seconds." }, status: 429
end
```

**Redis backend** (multi-process/multi-server):

```ruby
limiter = AiLoom::RateLimiter.new(backend: :redis)
```

Uses `Redis.current` with sorted sets. Keys auto-expire after the window duration.

**Reset (memory backend only):**

```ruby
backend = AiLoom::RateLimiter::MemoryBackend.new
limiter = AiLoom::RateLimiter.new(backend: backend)

backend.reset!("user:42:chat")  # reset one key
backend.reset!                   # reset all keys
```

**Global configuration:**

```ruby
AiLoom.configure do |config|
  config.rate_limiter = AiLoom::RateLimiter.new(backend: :memory)
end
```

### 5.7 Conversation Tracking

**When:** You want to persist conversation history with token counts, cost estimation, and windowed history.

**Install migration:**

```bash
bin/rails generate ai_loom:conversations
bin/rails db:migrate
```

**Set up models:**

```ruby
# app/models/conversation.rb
class Conversation < ApplicationRecord
  include AiLoom::Conversational
end

# app/models/conversation_message.rb
class ConversationMessage < ApplicationRecord
  include AiLoom::ConversationMessageMethods
end
```

The `Conversational` concern sets `table_name` to `ai_loom_conversations` and configures the `belongs_to :threadable` polymorphic association and `has_many :messages`.

**Record messages:**

```ruby
conversation = Conversation.create!(threadable: current_user)

# Record an inbound (user) message
conversation.record_inbound!(content: "How do I reset my password?")

# Send to LLM
response = adapter.chat(
  messages: conversation.history,
  system_prompt: system_prompt
)

# Record the outbound (assistant) response
conversation.record_outbound!(
  content: response.content,
  tokens_input: response.usage[:prompt_tokens],
  tokens_output: response.usage[:completion_tokens],
  model: response.model,
  cost_cents: calculate_cost(response)
)
```

**History with window:**

```ruby
messages = conversation.history           # uses default window (20 messages)
messages = conversation.history(window: 10)  # override window size
```

Consecutive messages with the same role are automatically merged to satisfy provider APIs that require alternating roles.

**Cost tracking:**

```ruby
conversation.total_tokens       # sum of all input + output tokens
conversation.total_cost_cents   # sum of estimated_cost_cents across messages
```

**Configure cost calculator:**

```ruby
AiLoom.configure do |config|
  config.cost_calculator = ->(model, input_tokens, output_tokens) {
    case model
    when /gpt-4o/ then ((input_tokens * 2.5) + (output_tokens * 10.0)) / 1_000_000 * 100
    when /claude/ then ((input_tokens * 3.0) + (output_tokens * 15.0)) / 1_000_000 * 100
    else 0
    end
  }
end
```

**Lifecycle:**

```ruby
conversation.mark_completed!
conversation.mark_failed!(error: "Provider timeout")

Conversation.active      # scope
Conversation.completed   # scope
Conversation.failed      # scope
```

### 5.8 Photo Tags (ai-lens)

**When:** You want photos classified by how they should be used (showcase, identifier, detail, damage, etc.).

**Built-in facets:**

| Facet | Description |
|-------|-------------|
| `identifier` | Contains text, codes, serial numbers for deterministic identification |
| `showcase` | Visually appealing, hero-worthy, display-quality photo |
| `detail` | Close-up of specific feature, texture, flaw, or marking |
| `context` | Shows scale, environment, or provenance |
| `damage` | Documents wear, defects, or condition issues |
| `documentation` | Paperwork, receipts, certificates, provenance docs |

**Configuration:**

```ruby
# config/initializers/ai_lens.rb
AiLens.configure do |config|
  # Add custom facets
  config.add_photo_tag_facet :packaging, "Shows original packaging, box, or case"
  config.add_photo_tag_facet :comparison, "Side-by-side comparison with reference item"

  # Allow the LLM to invent additional facets
  config.open_photo_tags = true

  # Minimum score threshold (0.0 to 1.0)
  config.photo_tag_threshold = 0.3
end
```

**Access tags after identification:**

```ruby
item.photo_tag_sets
# => [#<PhotoTagSet photo_index: 0, ...>, #<PhotoTagSet photo_index: 1, ...>, ...]

tag_set = item.photo_tags_for(0)
tag_set.tagged?(:showcase)     # => true
tag_set.score(:showcase)       # => 0.92
tag_set.primary_facet          # => :showcase
tag_set.facets                 # => [:showcase, :detail]
```

**Order photos by showcase quality:**

```ruby
ordered = item.photo_tag_sets
  .sort_by { |pts| -pts.score(:showcase) }
  .map { |pts| item.photos[pts.photo_index] }
```

**Select the hero image:**

```ruby
hero_index = item.photo_tag_sets
  .max_by { |pts| pts.score(:showcase) }
  &.photo_index

hero_photo = item.photos[hero_index] if hero_index
```

**Find photos with identifiers:**

```ruby
identifier_photos = item.photo_tag_sets
  .select { |pts| pts.tagged?(:identifier) }
  .map { |pts| item.photos[pts.photo_index] }
```

### 5.9 Text-to-Speech

**When:** You want to generate audio from text.

```ruby
adapter = AiLoom.adapter(:openai)

adapter.supports_tts?  # => true

audio_data = adapter.text_to_speech(
  text: "Hello, welcome to our application!",
  voice: "nova",          # options: alloy, echo, fable, nova, onyx, shimmer
  model: "tts-1"          # default: tts-1
)

File.binwrite("welcome.mp3", audio_data)
```

Only the OpenAI adapter supports TTS.

### 5.10 xAI Responses API (Web Search)

**When:** You want to use Grok's native web search to answer questions with real-time information.

```ruby
grok = AiLoom.adapter(:grok)

response = grok.responses_chat(
  input: [{ role: "user", content: "What happened in tech news today?" }],
  instructions: "Summarize the top 3 stories.",
  tools: [{ type: "web_search" }]
)

puts response.content

# Access citations from web search results
response.citations.each do |citation|
  puts "#{citation["title"]}: #{citation["url"]}"
end
```

The `responses_chat` method returns a standard `AiLoom::Response` with `citations` populated from `url_citation` annotations in the output.

---

## 6. Testing

### Test Adapter Setup

```ruby
# test/test_helper.rb or spec/rails_helper.rb
AiLoom.configure { |c| c.default_adapter = :test }
```

### Queuing Responses

```ruby
test = AiLoom.adapter(:test)

# Queue a single response
test.queue_response("Paris is the capital of France.", model: "test-gpt", usage: { total_tokens: 10 })

# Queue multiple simple responses
test.queue_responses("Response 1", "Response 2", "Response 3")

# Queue a JSON response
test.queue_response('{"answer": 42}')

# Queue a response with tool calls
test.queue_response("", tool_calls: [
  { id: "call_1", name: "get_weather", arguments: { "location" => "Paris" } }
])
```

### Making Calls and Asserting

```ruby
response = test.complete(prompt: "What is the capital of France?")
response.content  # => "Paris is the capital of France."
response.model    # => "test-gpt"

# Inspect recorded requests
test.requests.length     # => 1
test.last_request        # => { messages: [...], system_prompt: nil, tools: nil, model: nil, json_mode: false }
```

### Default Behavior

When the queue is empty, the test adapter returns `"Test response"`.

### Reset Between Tests

```ruby
# Always reset in setup/teardown to avoid cross-test contamination
test.reset!
test.requests    # => []
```

### Full Test Example

```ruby
RSpec.describe MyAiService do
  let(:adapter) { AiLoom.adapter(:test) }

  before do
    AiLoom.configure { |c| c.default_adapter = :test }
    adapter.reset!
  end

  it "classifies user input" do
    adapter.queue_response('{"intent": "greeting"}')

    result = MyAiService.new(adapter: adapter).classify("Hello!")

    expect(result).to eq("greeting")
    expect(adapter.last_request[:messages]).to eq([
      { role: "user", content: "Hello!" }
    ])
    expect(adapter.last_request[:json_mode]).to be true
  end
end
```

### Testing Tool Calls

```ruby
it "handles tool calls" do
  adapter.queue_response("", tool_calls: [
    { id: "call_1", name: "get_weather", arguments: { "location" => "Paris" } }
  ])
  adapter.queue_response("The weather in Paris is 22C.")

  response = adapter.chat(messages: [{ role: "user", content: "Weather?" }], tools: tools)
  expect(response.tool_use?).to be true
  expect(response.tool_calls.first[:name]).to eq("get_weather")
end
```

### Testing Photo Identification (ai-lens)

Mock the adapter to avoid real API calls:

```ruby
RSpec.describe Item do
  before do
    AiLoom.configure { |c| c.default_adapter = :test }
    adapter = AiLoom.adapter(:test)
    adapter.reset!
    adapter.queue_response({
      name: "Test Item",
      category: "trading_card",
      year: 1993,
      condition: "near_mint"
    }.to_json)
  end

  it "identifies the item" do
    item = items(:with_photos)
    perform_enqueued_jobs do
      item.identify!
    end
    expect(item.reload.identified?).to be true
  end
end
```

---

## 7. Credential Setup Reference

### Rails Credentials Format

```bash
bin/rails credentials:edit
```

```yaml
openai:
  api_key: sk-...
  organization_id: org-...          # optional
  model: gpt-4o                    # optional (default: gpt-4o)
  embedding_model: text-embedding-3-small  # optional

anthropic:
  api_key: sk-ant-...
  model: claude-sonnet-4-20250514       # optional (default: claude-sonnet-4-20250514)

gemini:
  api_key: AIza...
  model: gemini-2.0-flash          # optional (default: gemini-2.0-flash)

xai:
  api_key: xai-...
  model: grok-3                    # optional (default: grok-3)
```

### Initializer Format (Override or Non-Rails)

```ruby
# config/initializers/ai_loom.rb
AiLoom.configure do |config|
  config.openai    = { api_key: ENV["OPENAI_API_KEY"], model: "gpt-4o" }
  config.anthropic = { api_key: ENV["ANTHROPIC_API_KEY"], model: "claude-sonnet-4-20250514" }
  config.gemini    = { api_key: ENV["GEMINI_API_KEY"], model: "gemini-2.0-flash" }
  config.grok      = { api_key: ENV["XAI_API_KEY"], model: "grok-3" }

  config.default_adapter = :openai   # default: :openai
  config.timeout         = 60       # default: 60 seconds
  config.max_tokens      = 4096     # default: 4096
  config.temperature     = 0.2      # default: 0.2
end
```

### Engine Auto-Loading

The ai-loom Rails Engine reads credentials automatically during initialization:

| Credentials Key | Adapter | Fallback Key |
|-----------------|---------|--------------|
| `openai.api_key` | OpenAI | -- |
| `anthropic.api_key` | Anthropic | -- |
| `google.api_key` | Gemini | -- |
| `xai.api_key` | Grok | `xai_api_key` |

If you have already set credentials via `AiLoom.configure`, the engine will not overwrite them.

### Checking Availability

```ruby
AiLoom.available_adapters
# => [:openai, :anthropic, :gemini]

AiLoom.adapter(:openai).available?
# => true
```

---

## 8. Common Patterns

### Credit/Quota Gating Before LLM Calls

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos
  identifiable_photos :photos

  before_identify ->(item) {
    unless item.user.credits.positive?
      item.errors.add(:base, "No credits remaining")
      false
    end
  }

  on_success ->(item, job) {
    item.user.decrement!(:credits)
  }
end
```

For ai-loom direct calls:

```ruby
def ask_ai(user, prompt)
  raise "No credits" unless user.credits.positive?

  response = AiLoom.default_adapter.complete(prompt: prompt)
  user.decrement!(:credits)
  response
end
```

### Background Job with Retry Logic

```ruby
class AiSummaryJob < ApplicationJob
  queue_as :ai

  retry_on AiLoom::RateLimitError, wait: :polynomially_longer, attempts: 5
  retry_on AiLoom::TimeoutError, wait: 10.seconds, attempts: 3
  retry_on AiLoom::ServiceUnavailableError, wait: 30.seconds, attempts: 3
  discard_on AiLoom::AuthenticationError

  def perform(article)
    adapter = AiLoom.adapter(:anthropic)
    response = adapter.summarize(text: article.body, max_length: 100)
    article.update!(summary: response.content)
  end
end
```

### Turbo Stream Broadcasting from Callbacks

```ruby
class Item < ApplicationRecord
  include AiLens::Identifiable

  has_many_attached :photos
  identifiable_photos :photos

  on_stage_change ->(item, job, stage) {
    Turbo::StreamsChannel.broadcast_replace_to(
      item,
      target: "identification_progress",
      partial: "items/identification_stage",
      locals: { stage: stage, stages: AiLens::Job::STAGES }
    )
  }

  on_success ->(item, job) {
    Turbo::StreamsChannel.broadcast_replace_to(
      item,
      target: "item_details",
      partial: "items/details",
      locals: { item: item }
    )
  }
end
```

### Multi-Adapter Fallback Chains

```ruby
def chat_with_fallback(task, **kwargs)
  AiLoom.router.fallback_chain(task).each do |adapter_name|
    adapter = AiLoom.adapter(adapter_name)
    next unless adapter.available?
    return adapter.chat(**kwargs)
  rescue AiLoom::AdapterError
    next
  end
  raise "All adapters failed for #{task}"
end

# Usage
response = chat_with_fallback(:creative_writing,
  messages: [{ role: "user", content: "Write a poem." }]
)
```

### Cost Tracking with Configurable Pricing

```ruby
AiLoom.configure do |config|
  config.cost_calculator = ->(model, input_tokens, output_tokens) {
    rates = {
      /gpt-4o/     => { input: 2.5,  output: 10.0 },
      /gpt-4o-mini/ => { input: 0.15, output: 0.60 },
      /claude/     => { input: 3.0,  output: 15.0 },
      /gemini/     => { input: 0.075, output: 0.30 },
      /grok/       => { input: 3.0,  output: 15.0 }
    }

    rate = rates.find { |pattern, _| model.match?(pattern) }&.last
    return 0 unless rate

    ((input_tokens * rate[:input]) + (output_tokens * rate[:output])) / 1_000_000 * 100
  }
end
```

---

## 9. Troubleshooting

### "API key not configured"

The adapter cannot find credentials. Check:

1. `bin/rails credentials:edit` -- verify the key exists under the correct provider key (`openai`, `anthropic`, `gemini`, `xai`).
2. `AiLoom.adapter(:openai).available?` -- returns `false` if credentials are missing.
3. If using an initializer, ensure it runs before the code that uses the adapter.

### Rate Limit Errors

Use `retry_on` in background jobs:

```ruby
retry_on AiLoom::RateLimitError, wait: :polynomially_longer, attempts: 5
```

The error includes `retry_after` (seconds) from the provider when available:

```ruby
rescue AiLoom::RateLimitError => e
  sleep(e.retry_after || 60)
  retry
end
```

### Timeout Errors

Increase the timeout in configuration:

```ruby
AiLoom.configure do |config|
  config.timeout = 120  # default is 60 seconds
end
```

Or per-call with a longer-running model.

### JSON Mode Returns Non-JSON

Use `json_content!` for strict parsing -- it raises `AiLoom::InvalidResponseError` on failure instead of returning `nil`:

```ruby
data = response.json_content!  # raises on invalid JSON
```

If the LLM consistently returns non-JSON even with `json_mode: true`, add explicit instructions in the system prompt: `"Respond with valid JSON only. No markdown fences."`

### Photo Identification Stuck in Processing

Check for stuck jobs:

```ruby
AiLens::Job.stuck.count
```

Schedule the recovery job to run periodically:

```ruby
# solid_queue.yml
recurring:
  recover_stuck_ai_lens_jobs:
    class: AiLens::RecoverStuckJobsJob
    schedule: every 15 minutes
```

Or trigger manually:

```ruby
AiLens::RecoverStuckJobsJob.perform_later
```

Configure the stuck threshold:

```ruby
AiLens.configure do |config|
  config.stuck_job_threshold = 1.hour  # default
end
```

### Test Adapter Returns Unexpected Results

1. Check queue order -- responses are consumed in the order they were queued.
2. Call `reset!` in test setup/teardown to clear the queue and request history.
3. When the queue is empty, the adapter returns `"Test response"` -- if you see this, you have not queued enough responses.

```ruby
before do
  adapter = AiLoom.adapter(:test)
  adapter.reset!
  adapter.queue_response("Expected response")
end
```

### ai-lens before_identify Returning nil

When `before_identify` returns `false`, `identify!` returns `nil` and no job is created. Check that your gate logic is correct:

```ruby
before_identify ->(item) { item.user.credits.positive? }
```

### Error Hierarchy Reference

All errors inherit from `AiLoom::AdapterError`:

```
AiLoom::AdapterError
  AiLoom::AuthenticationError       # invalid API key
  AiLoom::RateLimitError            # provider rate limit (has retry_after)
  AiLoom::TimeoutError              # request timeout
  AiLoom::InvalidRequestError       # bad request parameters
  AiLoom::ContentFilterError        # content blocked by safety filters
  AiLoom::InvalidResponseError      # unparseable response (has raw_response)
  AiLoom::ContentPolicyError        # model refused the request
  AiLoom::ServiceUnavailableError   # provider API is down
```

Catch `AiLoom::AdapterError` to handle all LLM errors in one rescue clause.
