# Worked development profiles

All examples are minimal: they declare the feature(s) a task needs and add exact
overrides only when a feature alone is not enough. Ids come from
`settings-schema.json` / `feature-registry.json`.

## 1. Test GPU temperature in the hardware ring

```json
{
  "schemaVersion": 1,
  "features": ["hardware.panel.gpu.temperature"],
  "applyMode": "onLaunch"
}
```

The planner enables `panel.hardware` → `hardware.panel.rings` →
`hardware.panel.gpu`, sets the GPU ring metrics, and turns temperature monitoring
on. Nothing else is enabled and background history stays off.

## 2. Reproduce a dual-ring conflict

```json
{
  "schemaVersion": 1,
  "features": ["hardware.panel.cpu"],
  "preferences": {
    "icon.outerRing.hardware.layout": "dual"
  },
  "mutations": [
    { "id": "icon.outerRing.hardware.ringSlots", "operation": "add", "value": "cpu" }
  ],
  "applyMode": "onLaunch"
}
```

`dual` may set the same metric in both slots; the constraint resolves it with a
swap so the pair stays distinct. The `add` mutation keeps existing ring slots.

## 3. Force a specific panel background (Liquid Glass check)

```json
{
  "schemaVersion": 1,
  "preferences": {
    "panel.appearance.backgroundStyle": "liquidGlass"
  },
  "applyMode": "onLaunch"
}
```

On a machine without `ui.liquidGlass`, the value is still stored but does not
render; check the capability first if the test depends on the glass material.

## 4. Bold panel text (virtual setting)

```json
{
  "schemaVersion": 1,
  "preferences": {
    "panel.appearance.boldText": true
  },
  "applyMode": "onLaunch"
}
```

This one override mirrors to both underlying weight fields through `onChange`.
Do not set `…titleWeight` / `…mediumWeight` directly — they are `underlyingOnly`.

## 5. What NOT to put in a profile

```json
{
  "schemaVersion": 1,
  "preferences": {
    "general.launchAtLogin": true,
    "bluetooth.devices.hidden": ["AA-BB-CC-DD-EE-FF"]
  }
}
```

Rejected: `general.launchAtLogin` has a system side effect and
`bluetooth.devices.hidden` is device-identity/sensitive — both have
`accessPolicy.developmentProfile = false`. A profile that includes them is
rejected as a whole and nothing is written.

## Deleted / absent profile

If `.dev-profile.json` is absent, startup is unchanged. Deleting it stops
auto-application on the next launch but does not reset settings already changed.
