# AGENTS.md — ai-lens

## Model Landscape Freshness Check

Before starting any work on this gem, check the "Last reviewed" date in the
README's "Model Landscape" section. If it is more than 30 days old:

1. Check the ai-loom gem first — it owns the model defaults and landscape
2. If ai-loom was updated, update ai-lens's README Model Landscape section
   to match (pricing, recommended models, cost-per-identification table)
3. Update CHANGELOG.md and bump the patch version
4. Resume your original task

## Vendoring Reminders

When any consuming codebase needs updated gems:
- Always update BOTH ai-loom and ai-lens together
- Always rm -rf then cp -R (never merge old and new)
- Remove .git/, test/, Gemfile.lock from vendored copies
- Host Gemfile must include `require: "ai_loom"` and `require: "ai_lens"`
