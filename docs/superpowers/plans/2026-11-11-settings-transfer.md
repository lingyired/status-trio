# Settings Transfer Implementation Plan

**Goal:** Implement issue #320: versioned JSON preferences export/import, optional matched device settings, durable pre-import backup and undo.

**Architecture:** Explicit allowlisted settings descriptors read live state, validate complete input before mutation, and apply through existing published setters. A transfer session stages a preview, saves a backup before applying, and restores through the same setters. The General pane owns file selection and confirmation, not serialization logic.

**Tech Stack:** Swift, Foundation Codable, CryptoKit, Combine, SwiftUI; macOS 13+.

## Confirmed scope

- Default export/import contains portable preferences and language; device configuration is opt-in.
- Exclude login registration, Helper installation/approval, analytics and device consent, global shortcut, onboarding and development previews.
- JSON includes schemaVersion=1, exportedAt and appVersion. Reject unsupported versions or malformed documents without mutation. Missing fields preserve current values; unknown fields warn; invalid known values fall back to defaults with a preview warning.
- Optional device entries use SHA-256 identity tokens, not raw UIDs/addresses/serials. Match only currently known devices, skip unmatched entries, and never transfer BLE/Apple trust or consent.
- Before import save an atomic backup in Application Support; abort on backup failure. Offer undo and file-based recovery. Do not add reset-to-defaults.
- Existing published property paths update both Menu Bar and Dock. Do not replace live store objects or change rendering.

## Baseline

Branch `feat/issue-320-settings-transfer`, base `dcc84cc2` (latest origin/main at start). Clean main checkout reused; no new worktree needed. No remote publishing or GUI launch is part of implementation.

## Task 1: Portable catalog and device matching

Files: `Settings/SettingsTransferValue.swift`, `Settings/SettingsPreferenceCatalog.swift`, `Settings/SettingsDeviceArchive.swift`, small setter bridge in `SettingsStore.swift`, corresponding tests.

Interfaces:
- `SettingsTransferValue: Codable, Equatable, Sendable`: null, bool(Bool), number(Double), string(String), array([Self]), object([String: Self]).
- `SettingsPreferenceCatalog.snapshot(_ store: SettingsStore) -> [String: SettingsTransferValue]`.
- `SettingsPreferenceCatalog.prepare(_ values: [String: SettingsTransferValue]) -> (values: [String: SettingsTransferValue], warnings: [String])`; no mutation.
- `SettingsPreferenceCatalog.apply(_ values: [String: SettingsTransferValue], to store: SettingsStore)`; published setters.
- `SettingsDeviceInventory`: sets outputUIDs, inputUIDs, displayIDs, bluetoothAddresses, betterDisplayUUIDs; empty defaults.
- `SettingsDeviceArchive.snapshot(_ store: SettingsStore) -> [String: SettingsTransferValue]`.
- `SettingsDeviceArchive.prepare(_:inventory:)` returns validated, locally matched values and warnings; `apply(_:to:)` applies those values.

- [ ] Add behavioral tests for preference roundtrip, finite ranges, strict boolean/enum/color validation, exclusions, subset preservation, matched/unmatched devices and identifier privacy.
- [ ] Run focused filter and observe missing-feature failure.
- [ ] Implement allowlist catalog and device bridge; no new background tasks or permissions.
- [ ] Run focused tests until green.

## Task 2: Document and safe import session

Files: `Settings/SettingsTransferDocument.swift`, `Settings/SettingsTransferSession.swift`, `Tests/StatusTrioCoreTests/SettingsTransferTests.swift`.

Interfaces: `SettingsTransferDocument` versioned Codable envelope; `SettingsTransferSession` stages previews and owns backup URL, import and undo, receiving live SettingsStore and Localization.

- [ ] Test readable roundtrip, unsupported/zero versions, corrupt/oversized files, missing/unknown fields, language validation, zero mutation before confirmation, failed backup abort, backup recovery and undo.
- [ ] Run tests to observe failure, implement envelope and session, rerun focused tests.
- [ ] Backups capture full current local settings (including disconnected devices); undo bypasses current-inventory filtering only for that session's trusted backup.

## Task 3: General pane and localization

Files: `UI/Settings/SettingsTransferView.swift`, `UI/Settings/GeneralSectionView.swift`, localization key/resources, UI integration tests and user documentation.

- [ ] Add tests for staged import/confirmation presentation and localization coverage.
- [ ] Add export/import controls, opt-in device switch with privacy explanation, warning preview, confirm/cancel, undo and backup path.
- [ ] Use native asynchronous file panels, never runModal or app activation.
- [ ] Run focused SettingsTransfer/SettingsView/localization tests.

## Review focus

- Importing an old sparse file must not reset unrelated current preferences.
- A failed backup must leave live settings and undo state untouched.
- Files containing system keys must not register services or grant consent.
- Duplicate/malicious device entries and invalid color/numeric inputs must not escape validation.
- Undo must restore pre-import live values even for disconnected devices and pending slider writes.

## Delivery

- [ ] Fresh reviewer checks the integrated diff and fixes are covered with regression tests.
- [ ] Fetch/compare origin/main, run `bash scripts/verify-local.sh full` once on final integrated tree; rerun affected scope if final fixes are necessary.
- [ ] Report skipped visible UI tests and macOS runtime checks as NOT RUN; no release/signing/Universal claims.

## Execution record

User requested implementation immediately after accepting the proposed scope; proceed without another design handoff. Use focused tests during iteration and final full delivery profile, per repository policy. Keep working changes uncommitted for review unless separately authorized.
