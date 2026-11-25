# Dependency, conflict and connected-change rules

## Feature dependencies

A feature's `requires` are **other feature ids**. Enabling a feature plans its
whole parent closure (parents first) and emits each feature's `mutations`. Parent
mutations are marked `dependency`; the requested feature's own mutations are
`requested`. Example: `hardware.panel.gpu.temperature` requires
`panel.hardware`, `hardware.panel.rings`, `hardware.panel.gpu`, and additionally
sets `hardware.temperature.enabled = true`.

Enabling a parent module must NOT unconditionally start every collector — it only
sets the settings that make the module visible. Monitoring stays demand-based.

## Conditions are typed and separate

A descriptor uses distinct condition fields; do not collapse them:

- `visibleWhen` — whether the UI row is shown.
- `enabledWhen` — whether the control can be operated.
- `effectiveWhen` — whether the saved value actually takes effect now.
- `availableWhen` — whether the environment/hardware supports it.

Example: `panel.appearance.backgroundStyle` is `availableWhen ui.liquidGlass` for
the Liquid Glass option; `icon.outerRing.hardware.secondaryMetric` is
`effectiveWhen` source=hardwareMonitor AND layout=dual.

## Constraints and resolution strategies

| kind | meaning | resolutions used |
|---|---|---|
| `distinctValues` | value must differ from `other` when `when` holds | `swap` (dual-ring primary/secondary) |
| `minimumCount` | collection keeps at least `min` items | `reject` (≥1 hardware ring) |
| `maximumCount` | collection keeps at most `max` items | `reject` |
| `requires` | another setting must be enabled/present | `reject` |
| `numericRange` | value inside `min...max` | `reject` |

`swap` means: when a new value collides with the other slot, the other slot takes
this setting's **previous** value — producing a legal, distinct pair — instead of
erroring. This mirrors the app's existing dual-ring swap behavior.

To hide all hardware rings, disable `hardware.rings.enabled`; do **not** empty
`icon.outerRing.hardware.ringSlots` (it enforces a minimum of one).

## Connected changes (`onChange`)

Some settings imply other writes. These are declared as `onChange` mutations so a
single request produces one previewable plan:

- `panel.appearance.boldText` → sets both `…titleWeight` and `…mediumWeight`
  (a `nil` mutation value means "mirror the triggering value"). The two weight
  fields are `underlyingOnly` and must never be exposed as separate writable
  settings.
- Temperature being disabled replaces temperature-dependent ring/footer metrics
  (domain rule wired in the service's core provider).

Every connected change appears in the plan with source `connected`, is validated,
and is restored together with the direct change.

## Access policy

- `accessPolicy.developmentProfile == false` → a dev profile may NOT set it
  (system side effects, privacy, shortcuts, device identity, helper).
- New settings default to UI-only; external read/write must be granted explicitly.
- A profile that touches a disallowed setting is rejected as a whole — never
  partially applied.
