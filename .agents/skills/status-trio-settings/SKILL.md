---
name: status-trio-settings
description: Use when a Status Trio development task needs specific settings enabled to be testable — creating or updating a per-worktree `.dev-profile.json`, enabling a feature plus its parents, or checking dependencies/conflicts/permissions before building a dev app. Provides the generated settings schema, feature/capability/action registries, the dev-profile JSON schema, and dependency rules.
---

# Status Trio Settings

This skill lets a development agent start a per-worktree development build already
in the state a task needs — without touching production defaults, without
`defaults write`, and without enabling unrelated monitoring.

All reference data is generated from the source registry
(`SettingsSemanticCatalog` → `SettingsSchemaExporter`). Treat the JSON as
authoritative and do not hand-edit it.

## Progressive disclosure — read only what the task needs

| You need | Read |
|---|---|
| The exact id/type/options/conditions of a setting | `references/settings-schema.json` (or one module file) |
| A feature and its parent chain / required mutations | `references/feature-registry.json` |
| Whether the environment supports something (`ui.liquidGlass`, `hardware.hasBattery`, `permission.bluetooth`, `helper.ready`, …) | `references/capability-registry.json` |
| One-shot operations (check updates, charge to full, install helper) | `references/action-registry.json` |
| The `.dev-profile.json` structure to validate against | `references/dev-profile.schema.json` |
| Dependency / conflict / connected-change rules in prose | `references/dependency-rules.md` |
| Worked profile examples | `references/examples.md` |
| One module's settings at a glance | `references/modules/<module>.md` |

Modules: `general`, `panel`, `icon`, `hardware`, `battery`, `bluetooth`, `audio`, `brightness`.
See `references/index.md` for the generated index.

## Workflow

1. **Understand the task.** Which feature is being built or fixed? Which surface
   must be visible/active to test it?
2. **Find the feature and settings.** Look in `feature-registry.json` first —
   prefer enabling a *feature* over setting many raw preferences.
3. **Check dependencies and conflicts.** Every feature's `requires` are parent
   features; enabling it also emits their `mutations`. Check `constraints` in the
   setting's schema entry (e.g. dual-ring primary/secondary must differ → `swap`).
4. **Check permissions and side effects before adding anything.** A setting whose
   `accessPolicy.developmentProfile` is `false` (login item, helper, power
   automation, privacy consent, shortcuts, device identities) must NOT be put in a
   dev profile. A profile that tries is rejected, not partially applied.
5. **Write the minimal `.dev-profile.json`** in the current worktree (see
   `examples.md`). Declare features first; add exact preference overrides only
   when needed; use `mutations` for collection edits (`add`/`remove`/`merge`/…).
6. **Validate it.** Match `dev-profile.schema.json`, and ensure ids resolve
   (`settings-schema.json` / `feature-registry.json`). Unknown ids or a schema
   version newer than the app are rejected.
7. **Build the dev app.** `bash scripts/build-worktree.sh release no-open` (or the
   repo's normal dev build). If `.dev-profile.json` exists, the build embeds it
   (development identity only) and the app applies it at launch.
8. **Verify.** On launch the app logs the applied operations. Confirm the target
   feature is directly testable; do not enable unrelated monitoring.

## Hard rules

- Prefer a **Feature** over raw preference edits.
- **Only enable what the task needs.** Do not turn on background history or extra
  sampling that the task does not require.
- Never put restricted / system-side-effect / privacy settings in a profile.
- Never use `defaults write` to bypass this architecture.
- Never change production defaults for a dev task.
- Deleting `.dev-profile.json` stops auto-application next launch; it does not
  reset already-changed settings.

## What is generated vs. hand-written

- Generated: `settings-schema.json`, `feature-registry.json`,
  `capability-registry.json`, `action-registry.json`, `dev-profile.schema.json`,
  `modules/*.md`, `index.md`.
- Hand-written: this `SKILL.md`, `dependency-rules.md`, `examples.md`.

To regenerate after changing the registry, run the schema exporter (see
`references/index.md`).
