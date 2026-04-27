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
end