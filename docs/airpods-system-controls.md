# AirPods inline direct controls

The AirPods output disclosure uses native system symbols with runtime fallbacks.
It does not open Control Center, System Settings, or another app, and does not
request Accessibility access. The previous AX backend and popover close/reopen
plumbing have been removed.

Each refresh publishes Spatial Audio immediately after its CoreAudio read, then
Conversation Awareness as soon as the helper returns, before attempting Adaptive
strength. Each section shows a progress indicator until its own read finishes.
Bluetooth cleanup preserves independently loaded helper and Spatial Audio state.
Dismissal cancels the read and suppresses late UI updates.

## Listening modes

The view uses the existing `BluetoothListeningModePresentation` and
`onSelectListeningMode` callback. Writes continue through
`BluetoothListeningModeController` and the existing CoreAudio `lstm`/`lsms`
backend, including its capability checks, route ownership, and readback.
Failure to open the supplementary Bluetooth channel does not disable these
controls. The inline layout preserves busy, selected, and failed states.

## Adaptive strength over Bluetooth

The supplementary backend speaks AACP on Bluetooth L2CAP PSM `0x1001`.
[LibrePods documents](https://github.com/librepods-org/librepods/blob/main/docs/control_commands.md)
control identifiers `0x2e` (strength, 0–100) and `0x28` (Conversation Awareness,
1 enabled, 2 disabled). Only these validated records are accepted, including
coalesced packets. Incomplete records and unknown values are ignored.

Opening a channel and waiting for reported settings are bounded. No automatic
reconnection, scanning, background polling, or persistent device cache is used.
The expanded view owns the channel and stops it when dismissed or collapsed.
Route identity is checked before opening, sending, and each bounded wait.
Controls appear only after the device reports their values. A write clears the
old value and requires a fresh matching report; transport success alone is not
confirmation. Unknown state cannot be written.

**Hardware limitation:** on the tested Mac, opening a second AACP channel while
the AirPods are connected returned `-536870212`. An isolated, manually run
reconnect probe opened a channel on its third bounded attempt and accepted the
handshake and notification request, but reported neither setting during the
four-second observation. No setting writes were attempted because their initial
values could not be read and restored. The headset was reconnected afterward.
This initial run did not validate writes over Bluetooth. Normal menu use never forces this
reconnect workaround.

A similar limitation is reported by
[airpods-ctl](https://github.com/BorgoGustavo/airpods-ctl/blob/master/docs/aap-protocol-notes.md).
[pods-control](https://github.com/raulgg/pods-control#how-it-works) instead uses
private AVOutputDevice calls with a process-local entitlement-check interposer;
the process-local mechanism is now isolated in the supplementary helper described below.

## Direct Conversation Awareness helper

A subsequent read-only test of the local AVFoundation compatibility shim
succeeded. A reversible On → Off → On test then confirmed both writes by
AVOutputDevice readback. This avoids the Bluetooth-channel limitation for
Conversation Awareness.

`StatusTrioAirPodsHelper` is an unprivileged, short-lived child, not a daemon.
The app uses the existing cancellation-aware `BoundedProcessInvocation` with a
five-second deadline and a 4096-byte output cap. The helper has its own four-second
alarm. It checks the current CoreAudio UID, the AV context's associated UID,
and the AV endpoint identity before each write and every confirmation read.
Only `read`, `ca-on`, and `ca-off` are accepted. No device identifiers are printed.

The helper re-execs itself with its adjacent `libAirPodsAudioContext.dylib`.
The library adapts pods-control's MIT-licensed shim, including its license in the
source and app bundle. It answers only the process-local
`com.apple.avfoundation.allow-system-wide-context` check; all other entitlement
queries pass through. No system process, global environment, protected service,
or system binary is modified. The main app does not load this library.

The helper alone has the standard hardened-runtime
`com.apple.security.cs.allow-dyld-environment-variables` exception. Both it and
the adjacent library use the selected signing identity; library validation is
not disabled. The app's signing step preserves nested entitlements. This is a
private-API compatibility mechanism, not an Apple-granted private entitlement.
Developer ID/notarization acceptance remains NOT RUN until actually verified.

Conversation Awareness and Adaptive strength are independent: failure to open
AACP cannot erase the helper's verified Conversation Awareness state. Spatial Audio uses its own CoreAudio backend; the helper is used only for
Conversation Awareness.

## Spatial Audio investigation

AirBuddy 3.0.3 was downloaded from its official site and inspected read-only,
without installing, launching, modifying, or copying its implementation into
Status Trio. REA could not switch targets because its earlier Hopper session
reported `cleanup_incomplete`; local `nm` and `llvm-objdump` provided the static
evidence instead.

Its AirAudio framework uses CoreAudio, not UI automation, for Spatial Audio:

- `spav`: availability
- `spcs` / `spss`: multichannel / stereo settings paths
- `htst`: head-tracking state
- `acsc`: current audio client process ID
- `spcf`: configuration

The setters pass an eight-byte payload containing the client PID and flag bytes.
Static evidence locations (arm64 AirAudio): `applySpatialAudioSettings` at
`0x269d4`, settings construction at `0x173f8`, CoreAudio setter at `0x24520`,
configuration read at `0x3a150`, and client-PID read at `0x1d8c4`.

Live checks confirmed these properties during playback. The current macOS
uses an eight-byte `spcf` (UInt32 saved mode plus a head-tracking byte), whereas
the inspected AirBuddy reader requests six bytes. The reader now uses the current
ABI and a bundle-ID qualifier for the current `acsc` process. `spcs` and `spss`
report active multichannel/stereo spatialization; a saved Automatic mode alone
must not make a stereo stream appear enabled.

`AirPodsSpatialControls` writes the same eight-byte command shape seen in
AirBuddy: current client PID, head-tracking flag, enable flag, and zero padding.
It checks the current output and client before writes and every confirmation
read. Both `spcs` and `spss` receive the desired flags. The operation stays busy
for six seconds because BTAudio acknowledges before the engine changes and
coalesces transitions for five seconds. A successful HAL return without matching
readback is a failure, never a selected checkmark. No background work continues
when the menu closes.

The production source passed Fixed → Head Tracked → Off live, with CoreAudio
readback after each operation and without system UI or reconnecting. An earlier
AVFoundation probe accepted writes but its getter kept reporting the global
Automatic value while the per-app value changed; that path is not shipped for
Spatial Audio. Playback ended with spatialization Off. The player's saved
configuration is now explicit Off (0), replacing its previous Automatic/default
(1); this is the same audible Off state for the stereo track, not an exact
restoration of the underlying automatic preference.

## Remaining Adaptive-strength blocker

A later bounded reconnect probe received `0x2e = 50` and `0x28 = 1`, confirming
that the settings parser and documented strength value match this headset.
No Adaptive-strength writes were made. The user declined an interruption-based
control, so no reconnect path was added and no further reconnect tests were run.

Read-only inspection found no Adaptive-strength UI or setter in AirBuddy 3.0.3's
main app, helper, AirAudio, AirFoundation, or bundled XPC executables. Its public
Adaptive support describes selecting the listening mode; it is not evidence of
an uninterrupted strength slider.

On this OS, `AudioAccessoryDevice.autoANCStrength` reaches
`CBStackControllerBTStack.sendAudioAccessoryConfig:device:error:` in bluetoothd.
The daemon subtracts 1000 from the API value and sends AACP control `0x2e`.
The XPC entry point `_xpcSendAudioAccessoryConfigMessage:` calls
`_entitledAndReturnError:`, which checks the client's audit-token entitlements
for `com.apple.bluetooth.system` or `com.apple.bluetooth.internal` and then its
signing identity. AADeviceManager activation also fails with missing
`com.apple.AudioAccessoryServices`. These are server-side checks; the helper's
process-local AV compatibility shim cannot satisfy them.

The legacy IOBluetooth existing-channel lookup returned no AACP channels and
`-536870212`, without disconnecting the headset. Thus a working, uninterrupted
Adaptive-strength setter is still unverified and unavailable in this build.
The app must not reconnect implicitly or present cached probe values as live.

### Other-app comparison (2026-10-30)

Read-only source inspection checked implementations, not just Adaptive-mode
feature claims. No third-party app was launched and no reconnection or system
UI was used during this follow-up.

- **MagicPodsCore** (`04af4bdeb5cbdc7cb6eeba9b0acf2076cc6d3c16`):
  `AapSetAdaptiveAudioNoise::Request()` sends the same 11-byte `0x2e` command.
  `src/client/Client.cpp` opens a Linux `AF_BLUETOOTH`, `BTPROTO_L2CAP` socket
  on PSM `0x1001`; this is not a macOS daemon-sharing interface.
  [Source](https://github.com/steam3d/MagicPodsCore/tree/04af4bdeb5cbdc7cb6eeba9b0acf2076cc6d3c16/src).
- **LibrePods** (`89356c08cea3db0b6b54792d9329d09a87cc85fa`):
  `linux/main.cpp::setAdaptiveNoiseLevel` writes the same packet to an existing
  Qt L2CAP socket; connection uses the AAP service UUID. Its Linux transport does
  not solve the local macOS second-channel refusal.
  [Source](https://github.com/librepods-org/librepods/blob/89356c08cea3db0b6b54792d9329d09a87cc85fa/linux/main.cpp).
- **Air Defense** (`657cb442effc3ff81b2b7d92646a06ab37908530`):
  `ADListeningMode.m` uses `CBClassicPeer.setListeningMode:` for mode selection.
  It has no strength setter. Local CoreBluetooth disassembly confirms this
  selector sends message `0x30` with a listening-mode value, not a generic AACP
  packet. The app's Accessibility fallback is outside our required behavior.
  [Source](https://github.com/dchersey/air-defense/blob/657cb442effc3ff81b2b7d92646a06ab37908530/macos/ControlPanel/Sources/ADBluetooth/ADListeningMode.m).
- **MacMix** (`6f993abd3d0bc01df34c0b13c1f35be7405c03b3`):
  its macOS reverse-engineering notes independently report strength values
  0–100 in ten-point steps, AACP command `0x2e`, and the protected
  `AADeviceManager` path. It explicitly leaves strength unimplemented pending
  discovery of an entitlement-free interface.
  [Research](https://github.com/ljmng7/MacMix/blob/6f993abd3d0bc01df34c0b13c1f35be7405c03b3/Docs/AirPodsControlReverseEngineering.md#adaptive-audio-strength-macos-27).

Write confirmation remains a separate unresolved issue: MagicPodsCore's
`AapAdaptiveAudioNoiseCapability::SetFromJson` explicitly updates its local value
because it says the AirPods do not send a change notification. LibrePods also
updates its model immediately after sending. Neither is independent hardware
readback. Our strict confirmation must not be relaxed to copy that optimistic
behavior; a usable transport would still need a tested fresh-read mechanism.
No production code changed as a result of this comparison.

## Validation

- CoreAudio live: Adaptive → Transparency → Adaptive; both transitions confirmed
  by `lstm` readback without system UI. Original mode restored.
- Bluetooth steady-state open: rejected, as above.
- Bluetooth reconnect experiment: channel opened; initial settings unavailable;
  no setting writes performed through Bluetooth.
- Direct AV helper: Conversation Awareness On → Off → On confirmed and restored.
- Spatial Audio: production CoreAudio writer confirmed Fixed, Head Tracked, and
  Off during playback. See the automatic-versus-explicit-Off distinction above.
- Ventura runtime: NOT RUN.
- Tests cover no-system-UI navigation, packet validation, invalid targets,
  cancellation, identity mismatch, model error isolation, and native slider
  accessibility/layout. Existing listening-mode tests cover the restored writer.

## Original request search

No matching existing request or PR was found for these three additional controls
in the initial open/closed issue search. Existing listening-mode work is in
[#79](https://github.com/lingyired/status-trio/issues/79),
[#82](https://github.com/lingyired/status-trio/pull/82), and
[#85](https://github.com/lingyired/status-trio/pull/85).

## Model-specific sections

Listening Mode is shown only when macOS supplies a controllable set of modes.
Known hardware exclusions hide unsupported Spatial Audio and Conversation
Awareness sections (including Conversation Awareness on basic AirPods 4).
The helper also reports Conversation Awareness support separately from its
on/off value. Unknown variants defer to runtime reporting; an API/read failure
is not evidence that hardware lacks a feature. Spatial Audio on a supported
model remains visible as unavailable when no active media client can be read.
Control glyphs use white in dark appearance and black in light appearance.
Off retains the same person-and-waves symbol as On/Fixed, with the waves dimmed
using a symbol palette; the person remains solid.
Cross-model hardware validation remains NOT RUN; model and protocol behavior
are covered by local tests.
