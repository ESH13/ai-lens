# frozen_string_literal: true

require "test_helper"

# Host model used as the polymorphic identifiable for Job tests
class TestItem < ActiveRecord::Base
  include AiLens::Identifiable

  identifiable_photos :photos

  define_schema do |s|
    s.field :name, type: :string
    s.field :category, type: :string
  end

  def photos
    []
  end
end

class JobTest < Minitest::Test
  def setup
    AiLens.reset_configuration!
    AiLens::Job.delete_all
    @item = TestItem.create!(name: "Original")
  end

  def teardown
    AiLens.reset_configuration!
  end

  # Task 1: greenfield migration has no auto_apply column. Creating a Job
  # must not crash — the gem should not reference auto_apply at all.
  def test_create_does_not_reference_auto_apply_column
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    assert_predicate job, :persisted?
    refute job.respond_to?(:auto_apply)
  end

  # Task 4: Job.stuck must respect AiLens.configuration.stuck_job_threshold,
  # not a hardcoded 1.hour.
  def test_stuck_scope_respects_configured_threshold
    AiLens.configuration.stuck_job_threshold = 5.minutes

    old_job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :processing
    )
    old_job.update_columns(updated_at: 10.minutes.ago, created_at: 10.minutes.ago)

    fresh_job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :processing
    )
    fresh_job.update_columns(updated_at: 1.minute.ago, created_at: 1.minute.ago)

    stuck_ids = AiLens::Job.stuck.pluck(:id)
    assert_includes stuck_ids, old_job.id
    refute_includes stuck_ids, fresh_job.id
  end

  # Task 2: photo_tags is in the LLM JSON content (extracted_attributes),
  # not in the provider envelope. parsed_photo_tags must read it from there
  # so the photo tag set wiring is not silently empty.
  def test_parsed_photo_tags_reads_from_extracted_attributes
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    extracted = {
      "name" => "Identified Name",
      "photo_tags" => [
        { "photo_index" => 0, "tags" => [{ "facet" => "showcase", "score" => 0.9 }] }
      ]
    }

    job.complete!(extracted_attributes: extracted, llm_results: {})

    photo_tags = job.send(:parsed_photo_tags)
    assert_equal 1, photo_tags.size
    assert_equal 0, photo_tags.first["photo_index"]

    # And the convenience accessor (photo_tag_sets) is populated as a result.
    refute_empty job.photo_tag_sets
    assert_equal 0, job.photo_tag_sets.first.photo_index
  end

  # Task 2 + Task 3: the schema-fields-only filter ensures photo_tags is not
  # written to the host model even when the host happens to have a setter.
  def test_photo_tags_are_not_applied_to_host_model
    # Define a TestItem-like class that exposes a photo_tags writer.
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema do |s|
        s.field :name, type: :string
      end

      attr_accessor :photo_tags

      def photos
        []
      end
    end
    Object.const_set(:TestItemWithPhotoTags, klass) unless defined?(TestItemWithPhotoTags)

    item = TestItemWithPhotoTags.create!(name: "Original")
    item.photo_tags = "untouched"

    job = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending
    )

    extracted = {
      "name" => "Identified",
      "photo_tags" => [{ "photo_index" => 0, "tags" => [] }]
    }

    job.complete!(extracted_attributes: extracted, llm_results: {})

    item.reload
    assert_equal "Identified", item.name
    # photo_tags is an attr_accessor only — it survives because nothing wrote to it.
    # Crucially, apply_identification! must not have called photo_tags=.
    assert_equal "untouched", item.photo_tags
  end

  # Task 5: item_mode: :multiple is not implemented in 0.3.0. Calling
  # identify! with :multiple must raise immediately, before any work is
  # enqueued, so callers fail fast with a clear message.
  def test_identify_with_multiple_item_mode_raises_not_implemented
    assert_raises(AiLens::NotImplementedError) do
      @item.identify!(item_mode: :multiple)
    end

    # No job should have been created or enqueued
    assert_equal 0, AiLens::Job.where(identifiable: @item).count
  end

  def test_identify_not_implemented_message_is_helpful
    error = assert_raises(AiLens::NotImplementedError) do
      @item.identify!(item_mode: :multiple)
    end

    assert_match(/multi/i, error.message)
    assert_match(/0\.3\.0|item_mode|single/i, error.message)
  end

  # Task 21: a before_identify that returns false now raises
  # AiLens::IdentificationGated. Previously identify! returned nil for
  # both this path and "no photos", which made the two cases
  # indistinguishable to callers.
  def test_identify_raises_when_before_identify_returns_false
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema do |s|
        s.field :name, type: :string
      end
      before_identify ->(_item) { false }

      def photos
        []
      end
    end
    Object.const_set(:GatedTestItem, klass) unless defined?(GatedTestItem)

    item = GatedTestItem.create!(name: "x")
    assert_raises(AiLens::IdentificationGated) do
      item.identify!
    end
  end

  # Task 21: when there are simply no photos attached, identify! still
  # returns nil. This is the documented "nothing to do" path.
  def test_identify_returns_nil_when_no_photos
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema do |s|
        s.field :name, type: :string
      end

      def photos
        []
      end
    end
    Object.const_set(:NoPhotoTestItem, klass) unless defined?(NoPhotoTestItem)

    item = NoPhotoTestItem.create!(name: "x")
    assert_nil item.identify!
    assert_equal 0, AiLens::Job.where(identifiable_id: item.id).count
  end

  # Task 6: ProcessIdentificationJob.retry_on previously interpolated
  # AiLens.configuration.max_retries at class-load time, freezing the value
  # before any host-app initializer ran. The runtime configuration must
  # be honored. Same for retry_delay (passed to wait:).
  def test_max_retries_reads_runtime_configuration
    AiLens.configuration.max_retries = 7
    assert_equal 7, AiLens::ProcessIdentificationJob.send(:configured_max_retries)

    AiLens.configuration.max_retries = 2
    assert_equal 2, AiLens::ProcessIdentificationJob.send(:configured_max_retries)
  end

  def test_retry_delay_reads_runtime_configuration
    AiLens.configuration.retry_delay = 30
    assert_equal 30, AiLens::ProcessIdentificationJob.send(:configured_retry_delay)

    AiLens.configuration.retry_delay = 5
    assert_equal 5, AiLens::ProcessIdentificationJob.send(:configured_retry_delay)
  end

  # Task 11: parsed_extracted_attributes is memoized so repeated calls
  # don't re-run JSON.parse on every access.
  def test_parsed_extracted_attributes_memoizes
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending,
      extracted_attributes: { "name" => "Cached" }.to_json
    )

    parse_calls = 0
    JSON.singleton_class.alias_method(:_orig_parse, :parse)
    JSON.define_singleton_method(:parse) do |*a, **kw|
      parse_calls += 1
      JSON._orig_parse(*a, **kw)
    end

    begin
      first = job.parsed_extracted_attributes
      second = job.parsed_extracted_attributes
      assert_equal "Cached", first["name"]
      assert_equal "Cached", second["name"]
      assert_equal 1, parse_calls, "JSON.parse should run once across two reads"
    ensure
      JSON.singleton_class.alias_method(:parse, :_orig_parse)
      JSON.singleton_class.remove_method(:_orig_parse)
    end
  end

  # Task 11: writing extracted_attributes resets the memo so a later
  # read sees the new value.
  def test_parsed_extracted_attributes_memo_resets_on_write
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending,
      extracted_attributes: { "name" => "First" }.to_json
    )

    assert_equal "First", job.parsed_extracted_attributes["name"]

    job.extracted_attributes = { "name" => "Second" }.to_json
    assert_equal "Second", job.parsed_extracted_attributes["name"]
  end

  # Task 11: parsed_llm_results memoizes too, with the same write-reset
  # contract.
  def test_parsed_llm_results_memoizes_and_resets
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending,
      llm_results: { "raw" => "first" }.to_json
    )

    assert_equal "first", job.parsed_llm_results["raw"]

    job.llm_results = { "raw" => "second" }.to_json
    assert_equal "second", job.parsed_llm_results["raw"]
  end

  # Task 8: complete! is atomic. If apply_identification! raises (host
  # model validation failure, etc.), the status update must roll back so
  # we don't leave a job marked :completed without applying its
  # attributes to the host.
  def test_complete_rolls_back_when_apply_identification_raises
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema do |s|
        s.field :name, type: :string
      end

      def photos
        []
      end

      # Simulate a host model where apply_identification! raises (e.g.
      # because the extracted attribute fails a host-side validation).
      def apply_identification!(_job)
        raise ActiveRecord::RecordInvalid.new(self), "boom"
      end
    end
    Object.const_set(:TestItemRaisingApply, klass) unless defined?(TestItemRaisingApply)

    item = TestItemRaisingApply.create!(name: "Original")
    job = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      job.complete!(extracted_attributes: { "name" => "After" }, llm_results: {})
    end

    job.reload
    assert_equal "pending", job.status, "job should be rolled back to pending after apply raised"
    assert_nil job.completed_at, "completed_at should not be set when apply raised"
  end

  # Task 8: on_success callbacks must run OUTSIDE the transaction so a
  # non-DB error in a callback (or a callback that itself opens a new
  # transaction) does not roll back the completed job.
  def test_complete_runs_on_success_outside_transaction
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema do |s|
        s.field :name, type: :string
      end

      cattr_accessor :on_success_saw_status

      on_success ->(item, job) {
        # When this fires, the transaction must already be committed:
        # a fresh read should see status_completed.
        self.on_success_saw_status = AiLens::Job.find(job.id).status
      }

      def photos
        []
      end
    end
    Object.const_set(:TestItemSuccessCallback, klass) unless defined?(TestItemSuccessCallback)

    item = TestItemSuccessCallback.create!(name: "Original")
    job = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending
    )

    job.complete!(extracted_attributes: { "name" => "After" }, llm_results: {})

    assert_equal "completed", klass.on_success_saw_status
  end

  # Task 3: a non-schema key is ignored even if the host has a setter for it.
  def test_apply_identification_only_writes_schema_fields
    item = TestItem.create!(name: "Before", title: "Original Title")
    job = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending
    )

    # `title` is NOT in the test schema, but TestItem has a `title=` writer.
    extracted = { "name" => "After", "title" => "LLM-injected Title" }
    job.complete!(extracted_attributes: extracted, llm_results: {})

    item.reload
    assert_equal "After", item.name
    assert_equal "Original Title", item.title
  end

  # Regression: complete! applies extracted attributes through the
  # `identifiable_mapping` so a schema field can be renamed onto a
  # different host model attribute (e.g., schema `name` → host `title`).
  # Without this, mappings declared on the host model would be ignored
  # and apply_identification! would silently no-op for renamed fields.
  def test_complete_applies_attributes_through_identifiable_mapping
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema do |s|
        s.field :name, type: :string
      end

      # Map LLM's `name` onto host model's `title` column.
      identifiable_mapping(name: :title)

      def photos
        []
      end
    end
    Object.const_set(:MappedTestItem, klass) unless defined?(MappedTestItem)

    item = MappedTestItem.create!(name: "Original Name", title: "Original Title")
    job = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending
    )

    job.complete!(
      extracted_attributes: { "name" => "Identified Item" },
      llm_results: {}
    )

    item.reload
    assert_equal "Identified Item", item.title,
      "schema field `name` should be mapped onto host attribute `title`"
    assert_equal "Original Name", item.name,
      "the unmapped attribute `name` on the host should be untouched"
  end

  # Task 23: `latest_completed_identification` is the canonical accessor for
  # the most recent successfully completed job. `latest_identification`
  # is now name-true: returns the most recent job regardless of status.
  def test_latest_completed_identification_returns_only_completed_jobs
    item = TestItem.create!(name: "Original")

    AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :failed
    )
    completed = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :completed,
      completed_at: 1.minute.ago
    )
    pending = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending
    )

    # Latest completed: only the :completed job qualifies.
    assert_equal completed.id, item.latest_completed_identification.id
    # Latest overall (name-true): the most recently created job, which
    # is `pending`.
    assert_equal pending.id, item.latest_identification.id
  end

  # Task 23: when there are no completed jobs, latest_completed_identification
  # returns nil — but latest_identification can still surface a pending or
  # failed job.
  def test_latest_completed_identification_nil_when_no_completed_jobs
    item = TestItem.create!(name: "Original")
    failed = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :failed
    )

    assert_nil item.latest_completed_identification
    assert_equal failed.id, item.latest_identification.id
  end

  # Task 25: identify! accepts `adapter:` as either Symbol or Array.
  # The Array form sets primary + fallback chain in one kwarg.
  def test_identify_accepts_adapter_as_symbol
    item = adapter_test_item
    with_stubbed_perform_later do
      job = item.identify!(adapter: :anthropic)
      assert_equal "anthropic", job.adapter
    end
  end

  def test_identify_accepts_adapter_as_array
    item = adapter_test_item
    with_stubbed_perform_later do
      job = item.identify!(adapter: [:grok, :openai, :gemini])
      assert_equal "grok", job.adapter
      # The remainder is stashed as fallback chain in error_details.
      assert_equal ["openai", "gemini"], job.error_details["fallback_adapters"]
    end
  end

  # Task 25: a non-Array, non-nil value passed to `adapters:` is the
  # classic typo (`adapters: :openai`). Previously silently ignored;
  # now raises ArgumentError so the mistake is caught at the call
  # site before any work is enqueued.
  def test_identify_raises_argument_error_when_adapters_is_not_array
    item = adapter_test_item
    error = assert_raises(ArgumentError) do
      item.identify!(adapters: :openai)
    end
    assert_match(/adapters:/, error.message)
    assert_match(/Array/, error.message)

    # No job should have been created.
    assert_equal 0, AiLens::Job.where(identifiable_id: item.id).count
  end

  # Task 25: the deprecated `adapters:` Array form still works for
  # callers migrating from 0.2.x.
  def test_identify_still_accepts_deprecated_adapters_array
    item = adapter_test_item
    with_stubbed_perform_later do
      job = item.identify!(adapters: [:anthropic, :openai])
      assert_equal "anthropic", job.adapter
    end
  end

  private

  # Shared helper for adapter-arg tests. Returns a TestItem subclass
  # whose `photos` is non-empty so `identifiable?` returns true and
  # identify! reaches the job-create path.
  def adapter_test_item
    @adapter_test_klass ||= begin
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "test_items"
        include AiLens::Identifiable
        identifiable_photos :photos
        define_schema { |s| s.field :name, type: :string }

        def photos
          [Object.new]
        end
      end
      Object.const_set(:AdapterArgTestItem, klass) unless defined?(AdapterArgTestItem)
      AdapterArgTestItem
    end
    @adapter_test_klass.create!(name: "x")
  end

  # ActiveJob serialization needs GlobalID, which the in-memory
  # SQLite schema doesn't wire. Stub perform_later for tests that
  # only need to reach the create-job path.
  def with_stubbed_perform_later
    AiLens::ProcessIdentificationJob.singleton_class.alias_method(:_orig_perform_later, :perform_later)
    AiLens::ProcessIdentificationJob.define_singleton_method(:perform_later) { |_j| :enqueued }
    yield
  ensure
    AiLens::ProcessIdentificationJob.singleton_class.alias_method(:perform_later, :_orig_perform_later)
    AiLens::ProcessIdentificationJob.singleton_class.remove_method(:_orig_perform_later)
  end
end