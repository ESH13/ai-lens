# frozen_string_literal: true

require "test_helper"

# Regression for the Track A encryption-opt-in change. Earlier
# revisions of ai-lens called `encrypts :llm_results` (etc.)
# unconditionally at class-load time. That coupled gem boot to
# Active Record encryption being configured: a host without
# encryption credentials saw an InvalidConfigurationError before
# the gem could load.
#
# 0.3.0 makes encryption opt-in: `encrypts` is only called when
# Rails.application.config.active_record.encryption.primary_key is
# present. The test suite itself runs with no Rails app and no
# encryption configured — the fact that ai-lens, Job, and Feedback
# load at all is the proof. These tests pin that contract so a
# future refactor that re-introduces unconditional `encrypts` calls
# fails loudly.
class EncryptionOptInTest < Minitest::Test
  def test_ai_lens_loads_without_encryption_configured
    # If unconditional `encrypts` was reintroduced, requiring the
    # gem (already done in test_helper) would have raised before we
    # got here. So if we reach this assertion, the gem booted clean.
    assert defined?(AiLens), "AiLens should be loaded"
    assert defined?(AiLens::Job), "AiLens::Job should be loaded"
    assert defined?(AiLens::Feedback), "AiLens::Feedback should be loaded"
  end

  def test_job_does_not_declare_encrypted_attributes_without_config
    # Without encryption configured, AR's encrypted_attributes
    # registry should be empty for AiLens::Job. If a future change
    # called `encrypts` unconditionally, this set would be populated.
    encrypted = AiLens::Job.encrypted_attributes || []
    assert_empty encrypted,
      "AiLens::Job should not register encrypted attributes when encryption is not configured"
  end

  def test_feedback_does_not_declare_encrypted_attributes_without_config
    encrypted = AiLens::Feedback.encrypted_attributes || []
    assert_empty encrypted,
      "AiLens::Feedback should not register encrypted attributes when encryption is not configured"
  end

  # Reads/writes to the formerly-encrypted columns are plain
  # ActiveRecord operations when encryption is off. This catches a
  # subtle regression where a host without encryption sees the
  # gem try to decrypt a plaintext value and raise.
  def test_extracted_attributes_round_trips_without_encryption
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "test_items"
      include AiLens::Identifiable
      identifiable_photos :photos
      define_schema { |s| s.field :name, type: :string }

      def photos
        []
      end
    end
    Object.const_set(:EncryptionOptInTestItem, klass) unless defined?(EncryptionOptInTestItem)

    item = EncryptionOptInTestItem.create!(name: "x")
    job = AiLens::Job.create!(
      identifiable: item,
      adapter: "openai",
      status: :pending,
      extracted_attributes: { "name" => "Plain" }.to_json
    )

    assert_equal "Plain", job.parsed_extracted_attributes["name"]
    assert_equal "Plain", AiLens::Job.find(job.id).parsed_extracted_attributes["name"]
  end
end
