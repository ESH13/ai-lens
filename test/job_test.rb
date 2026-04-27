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
end