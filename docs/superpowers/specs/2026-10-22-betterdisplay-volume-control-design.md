# BetterDisplay volume integration design

Date: 2026-10-22

Status: Implemented in the isolated worktree. Test and delivery evidence is
recorded in `docs/verification/betterdisplay-volume-integration.md`.

Branch: `codex/issue-115-betterdisplay-volume`

Base: `origin/main` at `d3b7ac241533afda385a1bf95e4df43778a81ce6`

## Goal and approved scope

Issue #115 reports an external BenQ display whose volume remains unavailable in
Status Trio, while the user reports successful keyboard control with BetterDisplay.
The attached AI-generated OSD explanation is background material, not a hardware
trace or an implementation instruction.

The maintainer approved both reading and changing volume through BetterDisplay,
using a new branch and isolated worktree. Success means:

- Current volume is shared by the Menu Bar, Dock and audio panel.
- The existing slider and scroll interactions can change volume through
  BetterDisplay. Mute is enabled only when the selected controller supports it.
- Changes made through BetterDisplay can update Status Trio.
- Failed or stale requests never leave an unconfirmed value looking successful.
- Existing native and direct DDC behavior remains available.

This feature does not establish that the reported BenQ is fixed until its
read/write behavior and audible results are verified on that device.

## Approach and alternatives

Use BetterDisplay's documented DistributedNotificationCenter request/response
transport. It avoids starting a process for every update and does not require
the user to enable an HTTP server or install a companion CLI.

CLI integration is useful for manual diagnosis but is not the production
polling path. HTTP is an alternative transport, not required for the first
version. Replacing the existing DDC implementation or adding an audio driver
does not serve this integration's scope.

BetterDisplay remains responsible for its keyboard handling and feedback UI.
Status Trio does not draw another OSD or change BetterDisplay's feedback settings.
Whether programmatic volume changes produce BetterDisplay OSD feedback must be
recorded separately from whether the volume changes.

## Backend selection and settings

Keep writable Core Audio as the first choice. For other current outputs:

| Preference | Read and write owner |
| --- | --- |
| Existing behavior, the default | Existing direct DDC path |
| BetterDisplay, explicitly selected | BetterDisplay only |

Add an external-display control group in the existing Audio settings page. Show
the preference, the associated BetterDisplay device and a concise availability
or failure reason. Persist selection per audio output UID, not per brand.

When BetterDisplay is selected, suspend Status Trio's direct DDC work for that
output, including queued writes and probes. Do not silently switch backends
after a failed write. The user can restore the existing selection explicitly.

Disabling integration cancels its requests, timers and observers. Do not launch
BetterDisplay, install software, enable HTTP, or change its preferences.

### Product flow refinement, October 29

Show the current audio output and explain that the setting is saved per device.
Use `Standard (Default)` for the existing behavior; hide integration details in
that mode. Choosing BetterDisplay automatically discovers its display catalog
and associates a uniquely identified current audio output. Only an unresolved
or ambiguous identity requires manual display selection. Association validates
volume readback before showing a connected state. Catalog discovery alone is
not proof that volume can be controlled.

Keep `Detect Again` as a bounded recovery action and show the one-line
connection prerequisite directly at the bottom. Display
names are labels only; duplicate names receive a short UUID suffix and the full
selected UUID is available as a tooltip. Preserve the bounded picker width.

Publish the catalog, discovery completeness, current output/display identity,
availability and writable capability in one settings snapshot. A catalog whose
discovery has not completed cannot label a saved display disconnected. Runtime
read/write results must update this snapshot, including after reselecting a
cached display. Native writable volume takes priority and gets an explicit
informational state without unnecessary connection controls or discovery.

## Device association

Every command targets one explicit BetterDisplay display UUID and operates on
a `deviceType == Display`, never an unscoped command or DisplayGroup. Never use
the first enumerated display, a fuzzy name, the mouse position or the focused
screen as the target.

Prefer a uniquely verified association between the current Core Audio output
and a live BetterDisplay device. Core Audio UID, framebuffer EDID UUID and
BetterDisplay display UUID are separate identifier domains; any translation
must have evidence and tests. A DDC service match is not a prerequisite for
BetterDisplay integration.

For a connected external `IOMobileFramebufferShim`, match the current CoreAudio
output UID to its EDID UUID, then match its full IOService registry path to the
BetterDisplay catalog's `registryLocation`. Require exactly one framebuffer
and exactly one display record. Read the framebuffer identities only during
catalog discovery, off the main actor, with no additional polling. Publish the
match in the catalog snapshot scoped to its audio output. Save it only when
BetterDisplay is selected, native volume is unavailable, and the output has no
saved display UUID. An existing manual association is never overwritten.
Hide the redundant display picker when the saved UUID matches this exact
association; keep it for unresolved identities and differing manual choices.

When automatic identity translation cannot be proven, offer explicit selection
of a live BetterDisplay display for the current audio output. Persist the
BetterDisplay UUID alongside that output's UID as a local preference, not as a
claim that either identifier is a stable hardware identity. Revalidate the
UUID against the live device catalog at every launch/reconnect and clear the
active binding if it is missing or ambiguous. Do not persist volatile
`displayID` or installation-specific `tagID`; names and serials are not
matching fallbacks.

Ambiguous, missing or disconnected identities disable control and clear the
displayed value. A BetterDisplay OSD event's display ID identifies the feedback
screen; it is not proof of the audio target.

## Components and data flow

- `BetterDisplayIntegrationClient`: owns notification observation, request IDs,
  bounded pending requests, deadlines and response decoding. Exposes typed
  operations rather than arbitrary command execution.
- `BetterDisplayVolumeCoordinator`: owns the selected device, generation,
  latest desired volume, serialized writes, refresh scheduling and capability.
- `VolumeMonitor`: chooses one backend and publishes the existing shared
  `VolumeStatus`. Native and direct DDC implementations retain their contracts.
- Audio settings and panel bindings: expose selection, readable values and
  independently writable volume/mute capabilities.

Reuse existing store and icon presentation paths. No separate Menu Bar or Dock
percentage cache is introduced. Only extract shared backend plumbing needed for
this integration; do not undertake a general audio architecture rewrite.

## Transport contract

Use `pro.betterdisplay.BetterDisplay.request` and the matching `.response`
notification. JSON is carried in the notification object string. Observe
responses before posting requests. Every request has a unique UUID, commands
and parameters, and an explicit device selector when accessing a display.

Use documented `get` and `set` volume operations. Query mute independently.
BetterDisplay's current CLI examples describe generic `volume`/`mute` as
following configured providers, including software or combined audio;
therefore do not assume generic volume always means raw DDC. Validate the
Boolean result and operation-specific payload; payload text is not assumed to
be JSON. Parse the numeric range and current value explicitly, rejecting
malformed, non-finite or inconsistent values. Never assume a universal maximum
of 100 or confuse a normalized value with a raw VCP value.

Read-only runtime protocol samples from BetterDisplay 4.3.4 are recorded in
`.superpowers/sdd/2026-10-22-betterdisplay-volume-control/protocol-evidence.md`.
They establish that `get UUID=<id> volume` returns plain numeric text;
`get UUID=<id> mute` returns `on`/`off`; and requesting `volume`, `value`,
`min` and `max` together returns `current,min,max` as comma-separated text.
Setting only min/max without value returned only the range, not the current
value. The identifiers payload was comma-separated JSON objects without outer
array brackets and identifier values were strings. Support that exact observed
framing as a constrained parse fallback; do not split on commas. A failed
`connected` getter did not imply the live display was disconnected. These are
one-version host samples, not a universal protocol guarantee.

Start with a 3-second request deadline, one mutation in flight and at most one
coalesced refresh. Deadlines and scheduling are injectable for tests. An older
response cannot resolve another request or publish into a newer generation.

Notifications are cooperative local IPC, not authenticated proof of hardware
state. Validate every received message and perform no actions from arbitrary
payload text.

## Volume writes and confirmation

Apply a valid user change to the visible draft immediately. Coalesce repeated
input with a 150 ms maximum send rate and one latest pending value; continuous
dragging must still send updates. Releasing the slider flushes the final value
when the in-flight command permits it.

Convert the normalized UI value using the validated controller range. Serialize
mutations, retaining only the latest unsent value. No automatic retry of a
timed-out mutation is allowed: it might already have taken effect.

After the final successful mutation response, query the same explicit device.
Only a matching, current response confirms the requested value. Ignore reads
that predate a newer user command. A mismatch publishes the returned value and
a failure state; a failed read clears the unconfirmed value and disables
adjustment until a fresh valid read restores capability.

The readback confirms BetterDisplay's reported state. It is not represented as
independent proof of a physical DDC read or an audible volume change.

Every write entry point checks selected backend, writable capability, identity
and generation. Programmatic updates to slider state must not call setVolume.
Apply this protection to slider callbacks, scroll actions and the monitor's
control methods, not just the slider's disabled appearance.

## External changes and lifecycle

Query after initial association, relevant output changes, reconnection, wake
and BetterDisplay readiness. If the user has enabled OSD notifications, volume
and mute events trigger a coalesced refresh; they do not replace a confirmed
initial query or establish device association.

While integration is enabled, BetterDisplay is running and an external output
is associated, use bounded reconciliation reads: 2 seconds with audio details
visible and 10 seconds otherwise. Observe only the current output. Do not poll
the full display list repeatedly; refresh topology when invalidated.

Stop polling during sleep, after integration is disabled, when the output
changes to a native device, or when BetterDisplay is absent. Application
lifecycle observation can restore the connection when BetterDisplay launches.
Request deadlines cover unexpected termination without relying only on its
orderly shutdown notification.

Output switches (including A -> B -> A), backend changes, display topology
changes, sleep and application restart invalidate the generation. Clear draft,
capability and queued work before publishing a new output. An already posted
command cannot be recalled and may complete on its original explicitly targeted
device; it must never be retargeted to the new output.

## Failure presentation

Expose concise reasons for app absent, integration disabled or unresponsive,
device unassociated, invalid response, unsupported control and failed write
confirmation. A timeout alone cannot prove which unavailable condition caused
it; use available evidence and otherwise report an unresponsive connection.

Retain no previous device's percentage on a new device. Do not present unknown
mute as known unmuted. Recovery requires a new valid response, not a cached
percentage. Diagnostics use stage and stable outcome names, excluding raw
device identities, serial numbers and notification payloads.

Localize new user-facing strings in every shipped language.

## Verification and acceptance

Automated tests must cover request correlation, timeout cleanup, invalid
payloads/ranges, backend priority and exclusivity, explicit targeting,
association ambiguity, write coalescing and final flush, readback mismatch,
late responses, generation invalidation and observer/timer teardown.

Add regressions proving external UI synchronization sends zero writes, all
write entry points respect capability, and Menu Bar, Dock and panel receive
the same scalar and mute state. Retain existing DDC and Core Audio regressions.

Run focused tests through `bash scripts/test.sh [filter]` during implementation.
Before delivery run `bash scripts/verify-local.sh full` on the final integrated
tree and compare it with the latest `origin/main`.

Manual acceptance must distinguish:

| Check | Current evidence |
| --- | --- |
| BetterDisplay request and payload shapes | Read-only probe of BetterDisplay 4.3.4; set/OSD/runtime compatibility NOT RUN |
| Reported BenQ initial read, writes and audible changes | NOT RUN |
| Keyboard/slider/scroll alternation and mute | NOT RUN |
| Output switch, app restart, sleep and reconnect | NOT RUN |
| Real dual-display targeting | NOT RUN |
| macOS 13 and current macOS runtime | NOT RUN |
| CPU, memory and wakeups with integration active/inactive | NOT RUN |

For resource measurements record hardware, process provenance, scenario and
duration; compare integration disabled, idle integration and repeated volume
changes. Mock transports and successful builds do not prove runtime efficiency.

## Delivery boundaries and review

Implementation follows
`docs/superpowers/plans/2026-10-22-betterdisplay-volume-control.md` using
DeepSeek, as requested by the maintainer. Do not commit, push, merge, create a
PR or publish a release without the maintainer's corresponding authorization.

## Primary references

- Issue and updated user request:
  https://github.com/lingyired/status-trio/issues/115
- BetterDisplay integration overview:
  https://betterdisplay.pro/guide/integration/
- BetterDisplay request/response, lifecycle and OSD protocol:
  https://betterdisplay.pro/guide/integration/third-party-apps/
- BetterDisplay operation, device selector and volume parameters:
  https://betterdisplay.pro/guide/integration/cli-reference/
- Existing backend RFC: `docs/design/audio-volume-backends.md`
- Existing DDC verification: `docs/verification/issue-115-ddc-targeting.md`
