# frozen_string_literal: true

require "test_helper"

# Tests for ProcessIdentificationJob.perform that exercise the
# image-caching guarantee (Task 10), tried_adapters preservation
# (Task 12), and unavailable-adapter skipping (Task 13).
class ProcessIdentificationJobTest < Minitest::Test
  def setup
    AiLens.reset_configuration!
    AiLens::Job.delete_all

    unless defined?(JobTestItem)
      Object.const_set(:JobTestItem, Class.new(ActiveRecord::Base) do
        self.table_name = "test_items"
        include AiLens::Identifiable
        identifiable_photos :photos
        define_schema do |s|
          s.field :name, type: :string
        end

        # Simulate a single attached photo so prepare_images returns
        # something non-empty.
        def photos
          [FakePhoto.new]
        end
      end)
    end

    unless defined?(FakePhoto)
      Object.const_set(:FakePhoto, Class.new do
        def respond_to?(name, include_private = false)
          %i[variant download content_type].include?(name) || super
        end
      end)
    end

    @item = JobTestItem.create!(name: "Original")
  end

  def teardown
    AiLens.reset_configuration!
  end

  # Task 10: when the primary adapter returns success?=false (a soft
  # failure), the fallback path must reuse the image_urls and
  # prompt_builder the primary path already built — no double encoding.
  def test_image_preparation_runs_once_when_falling_back
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    AiLens.configuration.fallback_adapters = [:anthropic]

    prepared = 0
    instance = AiLens::ProcessIdentificationJob.new
    instance.define_singleton_method(:prepare_images) do |_identifiable|
      prepared += 1
      ["data:image/jpeg;base64,fake"]
    end

    # Primary adapter "fails" (success?=false), fallback succeeds. Use
    # a custom adapter mock that returns soft-fail for openai, success
    # for anthropic.
    AiLoom.singleton_class.alias_method(:_orig_adapter, :adapter)
    AiLoom.define_singleton_method(:adapter) do |name|
      adapter = AiLoom._orig_adapter(name)
      if name.to_sym == :openai
        adapter.define_singleton_method(:analyze_with_images) do |**_|
          AiLoom::MockResponse.new(content: "", model: "x", adapter: name)
        end
      end
      adapter
    end

    begin
      instance.perform(job)
    ensure
      AiLoom.singleton_class.alias_method(:adapter, :_orig_adapter)
      AiLoom.singleton_class.remove_method(:_orig_adapter)
    end

    assert_equal 1, prepared, "images should be encoded exactly once across primary + fallback"
  end

  # Task 12: when the fallback path records tried_adapters in
  # error_details and the outer rescue then fires (e.g. an unrelated
  # error after the loop), the merged error_details must preserve
  # tried_adapters rather than overwriting them.
  def test_tried_adapters_preserved_when_outer_rescue_fires
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending,
      error_details: { "tried_adapters" => %w[openai anthropic] }
    )

    instance = AiLens::ProcessIdentificationJob.new
    # Simulate a runtime error after fallbacks were already recorded.
    instance.define_singleton_method(:prepare_images) do |_|
      raise StandardError, "downstream blew up"
    end

    instance.perform(job)

    job.reload
    assert_equal "failed", job.status
    assert_equal %w[openai anthropic], job.error_details["tried_adapters"],
      "tried_adapters from a prior fallback pass must survive a later fail!"
    assert_equal "StandardError", job.error_details["error_class"]
  end

  # Code-review fix: when a fallback adapter succeeds, the job's
  # current_stage must follow the same progression as a primary
  # success — extracting -> (validating) -> applying -> completed.
  # Previously the fallback path completed the job without emitting
  # any stage updates, so on_stage_change subscribers saw the stage
  # frozen at "analyzing" even though the work finished.
  def test_fallback_success_updates_current_stage_to_completed
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )
    AiLens.configuration.fallback_adapters = [:anthropic]
    AiLens.configuration.validate_responses = false

    instance = AiLens::ProcessIdentificationJob.new
    instance.define_singleton_method(:prepare_images) { |_| ["data:image/jpeg;base64,fake"] }

    # Primary raises an AdapterError (the rescue-driven fallback
    # path). Fallback returns a healthy response.
    AiLoom.singleton_class.alias_method(:_orig_adapter, :adapter)
    AiLoom.define_singleton_method(:adapter) do |name|
      adapter = AiLoom._orig_adapter(name)
      case name.to_sym
      when :openai
        adapter.define_singleton_method(:analyze_with_images) do |**_|
          raise AiLoom::AdapterError, "primary boom"
        end
      when :anthropic
        adapter.define_singleton_method(:available?) { true }
      end
      adapter
    end

    begin
      instance.perform(job)
    ensure
      AiLoom.singleton_class.alias_method(:adapter, :_orig_adapter)
      AiLoom.singleton_class.remove_method(:_orig_adapter)
    end

    job.reload
    assert_equal "completed", job.status
    assert_equal "completed", job.current_stage,
      "fallback success must end with current_stage = 'completed' just like primary success"
    assert_equal "anthropic", job.adapter,
      "fallback adapter that succeeded should be recorded as the job's adapter"
  end

  # Task 13: unavailable fallback adapters are skipped. The chain
  # advances to the next adapter rather than counting the unavailable
  # one as a failed attempt.
  def test_unavailable_fallback_adapters_are_skipped
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )
    AiLens.configuration.fallback_adapters = [:anthropic, :grok]

    # Stub adapter retrieval: anthropic is unavailable, grok is fine.
    AiLoom.singleton_class.alias_method(:_orig_adapter, :adapter)
    AiLoom.define_singleton_method(:adapter) do |name|
      adapter = AiLoom._orig_adapter(name)
      case name.to_sym
      when :anthropic
        adapter.define_singleton_method(:available?) { false }
      when :grok
        adapter.define_singleton_method(:available?) { true }
      else
        adapter.define_singleton_method(:available?) { true }
      end
      adapter
    end

    instance = AiLens::ProcessIdentificationJob.new
    instance.define_singleton_method(:prepare_images) { |_| ["data:image/jpeg;base64,fake"] }

    # Primary fails, anthropic is skipped, grok succeeds.
    primary_adapter = AiLoom.adapter(:openai)
    primary_adapter.define_singleton_method(:analyze_with_images) do |**_|
      AiLoom::MockResponse.new(content: "", model: "x", adapter: :openai)
    end
    instance.define_singleton_method(:get_adapter_for_job) { |_| primary_adapter }

    begin
      instance.perform(job)
    ensure
      AiLoom.singleton_class.alias_method(:adapter, :_orig_adapter)
      AiLoom.singleton_class.remove_method(:_orig_adapter)
    end

    job.reload
    tried = job.error_details["tried_adapters"]
    refute_includes tried, "anthropic", "unavailable adapter should not be recorded as tried"
    assert_includes tried, "grok"
  end
end
