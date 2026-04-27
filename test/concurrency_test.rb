# frozen_string_literal: true

require "test_helper"

# Tests that exercise concurrency-safety guarantees on Job state
# transitions and stuck-job recovery (Task 9).
class ConcurrencyTest < Minitest::Test
  def setup
    AiLens.reset_configuration!
    AiLens::Job.delete_all

    unless defined?(ConcurrencyTestItem)
      Object.const_set(:ConcurrencyTestItem, Class.new(ActiveRecord::Base) do
        self.table_name = "test_items"
        include AiLens::Identifiable
        identifiable_photos :photos
        define_schema do |s|
          s.field :name, type: :string
        end

        def photos
          []
        end
      end)
    end

    @item = ConcurrencyTestItem.create!(name: "Original")
  end

  def teardown
    AiLens.reset_configuration!
  end

  # Task 9: start_processing! must be a conditional update so two
  # workers racing for the same job cannot both transition it to
  # :processing. Exactly one wins; the other returns false.
  def test_start_processing_is_conditional
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    # First call wins.
    assert job.start_processing!
    assert_equal "processing", job.reload.status

    # Second call is a no-op: status is no longer :pending, so the
    # conditional UPDATE affects 0 rows.
    refute job.start_processing!
  end

  def test_start_processing_returns_false_when_job_already_completed
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :completed
    )

    refute job.start_processing!
    assert_equal "completed", job.reload.status
  end

  # Task 9: simulate two workers grabbing the same in-memory record and
  # racing into start_processing!. Only one transition should land in
  # the database. SQLite serializes writes so we cannot truly run this
  # in parallel, but the conditional-UPDATE pattern is what protects
  # against the race; verifying that two sequential calls (with the
  # same in-memory record) only mutate state once is the deterministic
  # equivalent.
  def test_two_callers_with_same_record_only_transition_once
    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :pending
    )

    # Two in-memory copies of the same DB row, as two workers would have.
    a = AiLens::Job.find(job.id)
    b = AiLens::Job.find(job.id)

    a_won = a.start_processing!
    b_won = b.start_processing!

    assert [a_won, b_won].count(true) == 1, "exactly one caller should win"
    assert_equal "processing", AiLens::Job.find(job.id).status
  end

  # Task 9: stuck-job recovery counts attempts and gives up after
  # MAX_RECOVERY_ATTEMPTS so a job that keeps re-stalling does not
  # re-enter the queue forever.
  def test_recovery_caps_attempts_and_marks_failed
    AiLens.configuration.stuck_job_threshold = 1.minute
    AiLens.configuration.fallback_adapters = []

    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :processing,
      error_details: {
        "recovery_attempts" => AiLens::RecoverStuckJobsJob::MAX_RECOVERY_ATTEMPTS,
        "tried_adapters" => ["openai"]
      }
    )
    job.update_columns(created_at: 10.minutes.ago, updated_at: 10.minutes.ago)

    AiLens::RecoverStuckJobsJob.new.perform

    job.reload
    assert_equal "failed", job.status
    assert_match(/Recovery exhausted/, job.error_message)
  end

  # Task 9: under the cap, recovery flips status back to :pending and
  # records an incremented recovery_attempts counter.
  def test_recovery_increments_attempts_under_cap
    AiLens.configuration.stuck_job_threshold = 1.minute
    AiLens.configuration.fallback_adapters = [:anthropic]

    job = AiLens::Job.create!(
      identifiable: @item,
      adapter: "openai",
      status: :processing,
      error_details: { "recovery_attempts" => 0, "tried_adapters" => ["openai"] }
    )
    job.update_columns(created_at: 10.minutes.ago, updated_at: 10.minutes.ago)

    # Stub perform_later — ActiveJob serialization requires a GlobalID
    # adapter, which the in-memory test schema doesn't ship. We only
    # care that the job state was updated for the next attempt; the
    # actual enqueue is a thin tail call.
    AiLens::ProcessIdentificationJob.singleton_class.alias_method(:_orig_perform_later, :perform_later)
    AiLens::ProcessIdentificationJob.define_singleton_method(:perform_later) { |_j| :enqueued }
    begin
      AiLens::RecoverStuckJobsJob.new.perform
    ensure
      AiLens::ProcessIdentificationJob.singleton_class.alias_method(:perform_later, :_orig_perform_later)
      AiLens::ProcessIdentificationJob.singleton_class.remove_method(:_orig_perform_later)
    end

    job.reload
    assert_equal "pending", job.status
    assert_equal 1, job.error_details["recovery_attempts"]
    assert_equal "anthropic", job.adapter
    assert_includes job.error_details["tried_adapters"], "anthropic"
  end
end
