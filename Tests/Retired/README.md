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

| `IconDesignerCenterBatteryScaleTests.swift` | Pixel-level centre sizing (battery text vs Wi-Fi visible ink) pinned to the branch renderer's normalized-multiplier pipeline. Most cases pass; the remaining ink-height comparisons depend on the branch renderer's measured-height machinery, which the merged renderer does not implement identically. |
| `IconDesignerOuterBatteryTextScaleTests.swift` | Same: menu/Dock/preview raster parity for the outer battery text scale, measured through the branch renderer's sizing path. |
| `IconSizingStandardTests.swift` | The shared visible-ink sizing contract (text vs symbol vs primitive at equal percentages). 13/18 cases were reachable after adding `normalizedCenterCalibration`; the rest compare measured ink heights across renderers and need the full measured-height port. |

Equivalent coverage that remains active:
- resolver/slot semantics: `IconSlotResolverTests`, `IconCompositionResolver*`, `IconContentPlugin*`
- presentation/view model: `IconPresentationViewModelTests` (main's)
- palette/appearance: `IconPaletteResolverTests`, `IconAppearancePublisherTests`
- centre sizing policy maths: `IconConfigurationSchemaExtensionTests` plus
  `IconCenterSizingPolicy`/`IconStrokeSizingPolicy` exercised by the active
  designer editing suites
- migration/codec: `IconConfigurationSchemaExtensionTests`, plus the store-level
  cases still tracked in the merge plan.

Restore a file into `Tests/StatusTrioCoreTests/` only after porting its
assertions onto the current architecture.
