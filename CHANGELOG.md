# Changelog

## [0.2.1] - 2026-04-26

### Changed
- **Active Record encryption is now opt-in.** The `encrypts` declarations on
  `AiLens::Job` (`llm_results`, `extracted_attributes`, `user_feedback`) and
  `AiLens::Feedback` (`comments`) are now activated only when the host app
  has configured `Rails.application.config.active_record.encryption.primary_key`.
  Previously these unconditional declarations forced every host app to run
  `bin/rails db:encryption:init` before the gem could boot, even for hosts
  that did not require encryption. Host apps that already configure AR
  encryption see no behavior change.

### Renamed
- **`AiLens::Feedback#reidentify_requested` → `AiLens::Feedback#skip_auto_reidentify`.**
  The previous accessor name shadowed any real `reidentify_requested` DB column
  in the host app, silently preventing persistence of that column. The new name
  is unambiguous: setting `feedback.skip_auto_reidentify = true` before save
  suppresses the gem's `after_create_commit :trigger_reidentification` callback,
  letting the host controller drive re-identification manually.

  **Migration:** Search for `reidentify_requested = true` in your codebase and
  rename to `skip_auto_reidentify = true`. Then run your test suite. The DB
  column (if any) of the same name is unaffected and will now persist correctly.

## [0.2.0] - 2026-04-25

- Renamed from `photo_identification` gem to `ai-lens`.
- Module rename: `PhotoIdentification` → `AiLens`.
- Database table renames: `photo_identification_jobs` → `ai_lens_jobs`,
  `photo_identification_feedbacks` → `ai_lens_feedbacks`.
- Added `on_stage_change` callback for stage tracking.
- Added photo tag set support (note: see KNOWN ISSUES — wiring needs a fix in
  0.3.0 before this is fully usable).
- Now depends on `ai-loom` for the underlying LLM adapter layer.
