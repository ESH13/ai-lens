# frozen_string_literal: true

require "test_helper"

# Tests for AiLens::Feedback covering the auto-reidentification contract:
# creating feedback that signals a problem (not helpful, or with
# corrections) re-enqueues identification, unless the host opts out via
# `skip_auto_reidentify`.
class FeedbackTest < Minitest::Test
  def setup
    AiLens.reset_configuration!
    AiLens::Feedback.delete_all
    AiLens::Job.delete_all

    unless defined?(FeedbackTestItem)
      Object.const_set(:FeedbackTestItem, Class.new(ActiveRecord::Base) do
        self.table_name = "test_items"
        include AiLens::Identifiable
        identifiable_photos :photos
        define_schema do |s|
          s.field :name, type: :string
        end

        # Non-empty so identifiable? is true and identify! reaches the
        # job-create path during reidentification.
        def photos
          [Object.new]
        end
      end)
    end

    @item = FeedbackTestItem.create!(name: "Original")
    @job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :completed,
      completed_at: 1.minute.ago
    )
  end

  def teardown
    AiLens.reset_configuration!
  end

  # Regression: creating feedback marked `helpful: false` triggers a new
  # identification run on the parent identifiable. The reidentification
  # is delegated to identify!, which enqueues a fresh ProcessIdentificationJob.
  def test_unhelpful_feedback_triggers_reidentification
    new_jobs = []
    with_capturing_identify do |captured|
      AiLens::Feedback.create!(job: @job, helpful: false, comments: "wrong item")
      new_jobs = captured
    end

    assert_equal 1, new_jobs.size, "an unhelpful feedback should kick off exactly one new identify! call"
    options = new_jobs.first
    assert_equal "openai", options[:adapter], "reidentification should reuse the original job's adapter"
    assert_match(/wrong item/, options[:user_feedback].to_s,
      "user_feedback passed to identify! should include the new feedback's comments")
  end

  # Regression: feedback that includes suggested_corrections also
  # triggers reidentification, even when marked helpful — the user
  # provided structured edits the LLM should incorporate.
  def test_corrections_trigger_reidentification_even_when_helpful
    new_jobs = []
    with_capturing_identify do |captured|
      AiLens::Feedback.create!(
        job: @job,
        helpful: true,
        suggested_corrections: { "name" => "Correct Name" }
      )
      new_jobs = captured
    end

    assert_equal 1, new_jobs.size,
      "feedback with corrections should reidentify even when marked helpful"
  end

  # Regression for the Track A rename: setting skip_auto_reidentify
  # before save suppresses the after_create_commit reidentification
  # hook. Hosts use this when they want to drive reidentification
  # themselves (e.g. to batch user changes).
  def test_skip_auto_reidentify_suppresses_reidentification
    new_jobs = []
    with_capturing_identify do |captured|
      feedback = AiLens::Feedback.new(job: @job, helpful: false, comments: "skip me")
      feedback.skip_auto_reidentify = true
      feedback.save!
      new_jobs = captured
    end

    assert_empty new_jobs,
      "skip_auto_reidentify should prevent the auto-reidentification from firing"
  end

  # Regression: helpful feedback with no corrections is a positive
  # signal — no reidentification needed.
  def test_helpful_feedback_without_corrections_does_not_reidentify
    new_jobs = []
    with_capturing_identify do |captured|
      AiLens::Feedback.create!(job: @job, helpful: true)
      new_jobs = captured
    end

    assert_empty new_jobs,
      "plain helpful feedback should not trigger a re-identification"
  end

  private

  # Captures every call to FeedbackTestItem#identify! so a test can
  # assert how many reidentifications fired and with what kwargs. The
  # underlying identify! is stubbed out so we don't need ActiveJob /
  # GlobalID wiring.
  def with_capturing_identify
    captured = []
    FeedbackTestItem.class_eval do
      alias_method :_orig_identify!, :identify!
      define_method(:identify!) do |**opts|
        captured << opts
        nil
      end
    end
    begin
      yield(captured)
    ensure
      FeedbackTestItem.class_eval do
        alias_method :identify!, :_orig_identify!
        remove_method :_orig_identify!
      end
    end
  end
end
