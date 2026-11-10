# Retired tests

These test files are kept for reference but are **not** part of the test target.
They assert behaviour of the pre-merge V1 architecture that the integration
replaced with main's runtime pipeline, so they cannot pass as written:

| File | Why retired |
| --- | --- |
| `IconLegacyCompatibilityTests.swift` | Asserts the branch's legacy mapper output (e.g. `RingGapStyle.value` accessories and its own percentage precedence). The merged mapper uses `.indicator`/bolt-marker semantics. |
| `IconRuntimePresentationOptionsTests.swift` | Builds `IconPresentationViewModel` with the removed `mapResolution`/`designerConfiguration` arguments and asserts `resolveDesignerScene` on `StatusIconPreviewCard`. |
| `IconDesignerMenuBarColorPropagationTests.swift` | Depends on the deleted `IconDesignerRealIconOverrideBridge` and `IconPresentationViewModel.refreshSourceState()` / `output.trace`. |
| `IconPreviewInputBuilderTests.swift` | Pins the branch's simulated Wi-Fi sample shape, which differs from the merged snapshot/resolver contract. |

Removed cases (from an otherwise-active file):
- `IconConfigurationMigrationTests.testLegacyOptionsMigrationPreservesEveryIconOption`
- `IconConfigurationMigrationTests.testStoreMigratesLegacyDefaultsAndKeepsOldKeys`
  Both assert a byte-for-byte lossless legacy-options round-trip. After the
  merge the store keeps main's individual `@Published` settings as the edited
  values and derives the V1 configuration from them, so an exact per-field
  round-trip through the V1 schema no longer holds. `IconConfigurationMigrationTests`
  stays active for the codec/migration cases that do still apply.

Equivalent coverage that remains active:
- resolver/slot semantics: `IconSlotResolverTests`, `IconCompositionResolver*`, `IconContentPlugin*`
- presentation/view model: `IconPresentationViewModelTests` (main's)
- palette/appearance: `IconPaletteResolverTests`, `IconAppearancePublisherTests`
- migration/codec: `IconConfigurationSchemaExtensionTests`, plus the store-level
  cases still tracked in the merge plan.

Restore a file into `Tests/StatusTrioCoreTests/` only after porting its
assertions onto the current architecture.
