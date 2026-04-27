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
end