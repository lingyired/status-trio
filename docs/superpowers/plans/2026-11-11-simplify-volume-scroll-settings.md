# Simplify panel volume-scroll settings

I'm using the writing-plans skill to create the implementation plan.

## Goal

Sliders (output volume, display brightness, input gain) always adjust on scroll,
with no setting. Replace the two old scroll settings with one option, default off,
that lets scrolling empty summary-page areas adjust output volume. Detail pages
never adjust volume. Existing installs keep their prior preference.

## Decisions

- Storage: new key `popupPanelScrollAdjustsVolume` (Bool, default false). Legacy
  keys `popupScrollAdjustsVolume` / `popupVolumeScrollScope` become migration
  sources only.
- Migration: stored new value wins. Otherwise old installs derive
  `legacyMaster && legacyScope == .panel` (absent values use old defaults
  `true` / `.panel`), so untouched old installs default on; fresh installs
  default off.
- New option applies to the summary route only.

## File structure

- `Sources/StatusTrioCore/Settings/SettingsStore.swift` — remove the two
  published properties and defaults keys; add `popupPanelScrollAdjustsVolume`,
  the pure resolver and existing-install detection.
- `Sources/StatusTrioCore/Presentation/Panel/PanelScrollVolumeFallback.swift`
  (new) — pure fallback decision.
- `Sources/StatusTrioCore/UI/StatusBarController.swift` — drop the master guard;
  route sliders unconditionally; gate step 3 with the new helper.
- `Sources/StatusTrioCore/UI/Settings/AudioSectionView.swift` — one toggle.
- `Sources/StatusTrioCore/Localization/LocalizationKey.swift` + 12
  `Resources/*.lproj/Localizable.strings` — drop 6 old keys, add 2.
- `Sources/StatusTrioCore/Models/PopupVolumeScrollScope.swift` — delete.
- Tests — rewrite `SettingsStoreTests` scroll cases + migration cases, update
  `SettingsViewTests` pane-split assertions, add resolver tests to
  `PopupVolumeScrollAdjustmentTests`.

## Tasks

1. `SettingsStore`: replace constants/properties/init; add resolver + install
   detection. Tests: default off, legacy master off -> off, legacy slider-only ->
   off, untouched old install -> on, fresh -> off, stored new wins.
2. New `PanelScrollVolumeFallback.allows(...)` + unit tests (summary on -> true;
   four detail routes -> false; disabled -> false; volume unavailable -> false).
3. `StatusBarController`: remove master guard, use helper for step 3.
4. `AudioSectionView`: single toggle; delete scope menu + label helper.
5. Localization: remove 6 keys, add 2 in all 12 locales (en first).
6. Delete `PopupVolumeScrollScope.swift` and its `LocalizationKey` cases/tests.
7. Verify: `bash scripts/verify-local.sh full` before delivery; build a dev bundle
   for manual testing.

## Verification

- `bash scripts/verify-local.sh full` (state/migration change).
- Manual dev bundle: sliders scroll with the new toggle off; summary empty-area
  scroll only when on; detail pages never change volume.
