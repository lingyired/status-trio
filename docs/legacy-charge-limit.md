# Legacy macOS Charge Limit — Research, Baseline and Evidence

> **Status:** Phase 0 research note (no app code modified)
> **Date:** 2026-11-04
> **Branch:** `fix/207-charge-limit-compat`
> **Recorded main SHA at baseline:** `57541b8234b562640ca455ebc352f1dd20502818` (`origin/main`)
> **Branch HEAD at baseline:** `5d4513ab`
> **Plan of record:** `status-trio-legacy-charge-limit-plan.md` (user-provided 2026-11-04)

This note is the Phase 0 deliverable for adding optional, low-overhead battery
charge ceilings on macOS 13–14 (Intel and Apple Silicon) alongside the existing
native PowerUI limit on macOS 26.4+. macOS 15 is out of scope by a 2026-11-05
product decision. It records what the reference projects
actually do, the supported matrix, licensing boundaries, and the evidence gaps
that must stay open until real-hardware validation. It complements
`docs/charge-limit-lower-macos-research.md`, which was written earlier and
contained initial leads.

This phase modifies **no application code** and performs **no SMC write or
probe**. Its purpose is to decide recorded sleep/quit behaviour and the manual
reset procedure *before any write call is implemented*.

---

## 1. Reference sources and behaviour (audited 2026-11-04)

Reference projects were shallow-cloned fresh into an isolated temp dir and
their relevant source was read directly. Licences are noted because Status
Trio is Apache-2.0 and **GPL source must not be copied**. bclm and battery are
MIT; batt, calma, gosmc, smc-command, charge-limiter are GPL. See §5.

| Project | Licence | Hardware | Mechanism | Lowest macOS claim |
| --- | --- | --- | --- | --- |
| [bclm](https://github.com/zackelia/bclm) | MIT | Intel + Apple Silicon | `BCLM` (Intel, ui8) / `CHWA` (Apple Silicon, ui8) SMC charge-limit keys | compiled ≥10.15, runs ≥10.9 |
| [batt](https://github.com/charlie0129/batt) | GPL-2.0 (app), MIT libs | Apple Silicon | legacy `CH0B`/`CH0C` (ui8) then `CHTE` (ui32); firmware keys `bfF0`/`bfD0`/`bfE0`; macOS 27 adapter fallback `CH0I`/`CH0J`/`CHIE` | macOS 11+ (firmware-based) |
| [battery](https://github.com/actuallymentor/battery) | MIT | Apple Silicon | `CH0B`/`CH0C` inhibit toggles | Apple Silicon era |
| [charge-limiter](https://github.com/alvarohurtadobo/charge-limiter) | GPL-3.0 | Intel | `BCLM` + `BFCL` (MagSafe LED) via bundled bclm binary | Intel era |
| [smc-command](https://github.com/hholtmann/smcFanControl/tree/master/smc-command) | GPL-2.0 | Generic SMC | raw SMC key read/write over IOKit | long-standing |
| [gosmc](https://github.com/charlie0129/gosmc) | GPL-2.0 | SMC library (batt) | Go bindings over IOKit (`IOConnectCallStructMethod`) | — |
| [calma](https://github.com/Milanpatel35/calma) | GPL-3.0 | Apple Silicon | allowlisted SMC write; engine with hysteresis | new project, low real-machine evidence |

### Intel: firmware ceiling first

- The canonical Intel key is `BCLM` (type `ui8`). Writing the ceiling percent
  limits charging; writing `100` lifts the cap. `BFCL` (also `ui8`) drives the
  MagSafe LED state light and is usually kept at `limit − 5`.
- `charge-limiter` (Intel, GPL-3.0) is a JXA app that shells out to a bundled
  copy of the MIT `bclm` binary; it writes `BCLM` and `BFCL` and reapplies the
  limit after reboot. Its behaviour is a product reference, not portable code.
- **Firmware vs software:** several Intel MacBooks persist `BCLM` in firmware
  so the cap survives reboot even without the app. That persistence can be a
  benefit and a hazard: disable must be explicit.

### Apple Silicon: legacy inhibit keys

- Older firmware: the pair `CH0B` + `CH0C` (both `ui8`) control charging.
  Writes `0x00` allow charging and `0x02` inhibit charging; writing just one of
  the pair is insufficient — both must be written together.
- Tahoe-era firmware: `CHTE` (a 4-byte/ui32 key) supersedes the pair. A value
  `0x00000000` allows charging; `0x01000000` inhibits. `batt` reads `CH0B`
  (len 1, `0x00` = enabled) or `CHTE` (4 zero bytes = enabled).
- `bclm`'s Apple Silicon route uses a different key, `CHWA` (ui8): `1 → 80`,
  `0 → 100`. That is the *system* battery-optimization switch, not the inhibit
  mechanism, and it appears tied to the OS version (see §4 evidence gap).

### Control-mode selection is firmware-probing, not OS-branching

`batt` determines the mechanism from **SMC key presence**, not the macOS
version string (`ChargeControlMode`): it prefers the firmware charge-limit keys
(`bfF0`+`bfD0`+`bfE0`), else the legacy inhibit keys, else reports unsupported.
This is the correct shape to reuse conceptually — an older macOS on newer
firmware still has the newer keys — and is why Status Trio should not key legacy
support off a bare OS-version check.

### Adapter-off is out of product scope

`batt` (macOS 27-era firmware) falls back to cutting and restoring wall power
via `CH0I`/`CH0J`/`CHIE` because the charge-enable keys become entitlement-gated.
**Status Trio does not and will not use adapter-off (`CH0I`/`CHIE`) control** per
the plan's product constraints (no forced discharge, no adapter-off). That means
on firmware where the inhibit keys are gated behind the private
`com.apple.private.iokit.soc-limit` entitlement, Status Trio must show
`unsupported`, not emulate battery/`batt`'s adapter route.

---

## 2. Supported matrix (planned)

| Runtime | Model | Legacy limiter | Notes |
| --- | --- | --- | --- |
| macOS 13–14 | Intel | Eligible after probe + validation (firmware `BCLM`) | Keep system charge-to-full if present |
| macOS 13–14 | Apple Silicon | Legacy SMC inhibit (`CH0B`/`CH0C`, `CHTE`) after probe | Independent of native |
| macOS 15 | All | **Out of scope (user decision 2026-11-05)** | No legacy backend; no native limit before 26.4 |
| macOS 16–26.3 | All | **Not released in this milestone** | Do not regress existing features |
| macOS 26.4+ | Apple Silicon | Do not expose legacy SMC writes | Prefer existing native PowerUI/system limit |
| macOS 26.4+ | Intel | Not in this milestone | No built-in manual ceiling assumed |
| Desktop/no battery / unsupported firmware / unsigned-helperless build | All | No write controls | Show native or read-only affordances |

Status Trio itself keeps its macOS 13 deployment target. A GitHub/Developer ID
distribution gate is distinct from app compatibility and hardware capability;
both must pass before a control becomes enabled. `minOS=13` in the binary does
**not** equal verified Ventura runtime behaviour.

The native path (`ManagedChargeLimitController` + `ChargeToFullNowNowController`)
touching PowerUI stays untouched for macOS 26.4+. Legacy limiting must use a
**separate session type and store** so the two never write the same keys or
disrupt each other's cancellation semantics.

### Recorded sleep / quit behaviour (decided in this spec, before writes)

- **Sleep without a target:** if a limit session is active when the Mac starts
  to sleep, inhibit charging before sleep (without holding a system-sleep
  assertion). The machine may not reach the target if closed early; on wake,
  re-read state and resume/reapply. This is a documented V1 tradeoff, not a bug.
- **Quit / disable:** before releasing the XPC session, restore the original
  SMC values, read back to verify, then end the charge session and release the
  connection. If restore fails, retain a visible `restoreFailed` state and
  provide an explicit recovery path; never report `disabled` as success.
- **Manual reset procedure (documented, to ship with the feature):** users must
  be able to restore stock charging without the app running. Because the helper
  only runs while Status Trio is alive, the reset path is: (1) open Status Trio
  → Settings → Battery → turn the legacy limiter off (app restores original
  values), or (2) if the app is unavailable, reopen/reinstall the helper build
  and disable, or (3) on Intel only, after fully re-charging, the firmware cap
  may persist — see the README/help copy. The exact per-backend manual reset
  instructions must be validated on real hardware before release and recorded
  in the product docs. This phase does not yet claim a working automated reset.

---

## 3. Licensing

Status Trio is Apache-2.0. The following constraints were confirmed by reading
each project's licence file:

- **Do not copy** GPL code: `batt` (GPL-2.0), `battery`'s firmware logic where
  GPL, `charge-limiter` (GPL-3.0), `smc-command` (GPL-2.0), `gosmc` (GPL-2.0),
  `calma` (GPL-3.0). Their documented behaviour, SMC key semantics, API shapes
  and tests are analysed and re-implemented independently.
- **MIT, reuse permitted with notice:** `bclm` (MIT, © 2020 Zack Elia) and
  `battery` (MIT, © 2022 Mentor Palokaj). If any MIT code is actually reused
  (rather than re-implemented), the copyright notice must be preserved.
- The IOKit/SMC access is Apple's own; using `IOKit` directly is fine.

---

## 4. Evidence gaps / non-verified claims (must stay OPEN)

The following are the single biggest sources of risk and are **not established
fact**:

1. **Intel `BCLM` on macOS 15.** `bclm`'s README states BCLM/CHWA fails on
   macOS >= 15.0 due to kernel entitlement enforcement (SIP must be disabled).
   Reading bclm issue #49 (title `keyNotFound(code: "CHWA")`) shows the reported
   failures are on **Apple Silicon** and about `CHWA` key-presence, not Intel
   `BCLM`. Intel `BCLM` behaviour on macOS 15 is therefore **unverified** and
   cannot be assumed broken or working. This is the sharpest uncertainty in the
   "Intel 13–14" target and must be settled on a real Intel macOS 13/14
   machine before the Intel backend is advertised. (macOS 15 was later ruled
   out of scope by the 2026-11-05 product decision.)
2. **Apple Silicon macOS 15 inhibit.** Moot for this feature: macOS 15 is out
   of scope (2026-11-05). Recorded only because it explains why the earlier plan
   treated 15 as a separate capability band.
3. **No entitlement guessing.** Plan requires no private entitlement guesses in
   the probe. Determining which key set exists and is writable is a read-only
   probe in Phase 2; a writable result is proven only on authorized hardware.
4. **Firmware-persistence hazard.** Intel firmware persistence of the cap and
   Apple Silicon software-only inhibit behave differently on reboot. Neither is
   validated on real hardware here.
5. **"macOS 27 entitlement" is not universal.** The plan explicitly warns
   against treating adapter-mode, the macOS 27 entitlement, or a minimum-OS
   claim as true for every model. They are real only on demonstrated firmware.

Nothing in this note substitutes for a real-hardware Physical Device check
(the plan's §9 matrix) before any backend is marked supported.

---

## 5. Audit trail

- Projects shallow-cloned 2026-11-04 into an isolated temp dir (outside the
  repo): `bclm`, `batt`, `battery`, `charge-limiter`, `smcFanControl`, `gosmc`,
  `calma`. No project files were copied into Status Trio.
- No application code was changed in Phase 0. Deliberate: the intent is to fix
  the recorded sleep/quit and reset semantics *before* implementing writes.

## 6. References

- [bclm](https://github.com/zackelia/bclm) (MIT) — Intel `BCLM` + Apple Silicon `CHWA`.
- [batt](https://github.com/charlie0129/batt) (GPL-2.0) — Apple Silicon inhibit + firmware probing.
- [battery](https://github.com/actuallymentor/battery) (MIT) — Apple Silicon inhibit toggles.
- [charge-limiter](https://github.com/alvarohurtadobo/charge-limiter) (GPL-3.0) — Intel `BCLM`/`BFCL`.
- [smc-command](https://github.com/hholtmann/smcFanControl/tree/master/smc-command) (GPL-2.0) — SMC I/O interface shape.
- [gosmc](https://github.com/charlie0129/gosmc) (GPL-2.0) — SMC library interface.
- [calma](https://github.com/Milanpatel35/calma) (GPL-3.0) — architecture reference, allowlist, fake SMC.
---

## 7. Audited source revisions (2026-11-04)

Fresh shallow clones in an isolated temp directory. Commit identifiers are
recorded so a later reader can reproduce the audit; no project files were
copied into Status Trio.

| Project | Audited commit | Licence |
| --- | --- | --- |
| bclm | `ae2c209614755d81bf5b788513dba1d44280a6f6` | MIT |
| batt | `57644f763ef03a443f1c697d3845e0d58b39a6df` | GPL-2.0 |
| battery | `8288167d8bcfd396120a005ad3528a1e73904f2a` | MIT |
| charge-limiter | `31836642d3012e3c3201fbf9a645c7196687a229` | GPL-3.0 |
| smc-command | `e1bd672bcd2d72eddff9b6da7b9cae38e35c4206` | GPL-2.0 |
| gosmc | `36c917295717bb50f098b591843eb23b4ca699dd` | GPL-2.0 |
| calma | `6225f40b536b13434d1de8dba9d4d857ed7cf9ea` | GPL-3.0 |

## 8. Implementation status on `fix/207-charge-limit-compat`

What exists in this branch (source-level evidence only):

- Pure domain model: runtime/OS classification, backend selection, status/error
  taxonomy, session store (`LegacyChargeLimit*`).
- Read-only capability probe with a closed key list and width/type/value
  validation (`LegacySMCProbe`, `LegacyChargeSMCKeys`).
- Helper coordinator: durable root-owned journal written before the first
  write, `expectedLimit` ownership check before any write, multi-key rollback,
  readback verification, restore on disable and on client loss.
  `expectedLimit` always means "the value I believe is on the hardware right
  now" — never the pre-management restore destination; the app therefore passes
  `nil` when it only knows its own intent, and the journal enforces ownership.
- The journal records `hw.model`; a record from another Mac is refused, so a
  stale file cannot restore a stock value that does not exist here. The store
  is owner-only, `O_NOFOLLOW`, single-link, size-bounded and atomic; an
  unreadable/corrupt record is an error, never "no session".
- Battery-driven hysteresis: the app's existing battery snapshot drives the 2%
  decision. Only a decision change writes; there is no new polling timer. A
  temporary full charge is never interrupted, and sleep clears the remembered
  gate so wake re-evaluates from hardware.
- One persistent authenticated XPC connection while a limit is held, released
  as soon as none is, so the helper can idle-exit.
- Hardware ownership is per connection: the daemon hands each XPC connection its
  own owner id through a per-connection proxy. A second connection (for example
  the short-lived Low Power Mode client) cannot disable the cap, cannot
  overwrite it, and its disconnect does not trigger charge recovery.
- If recovery after client loss fails, the root daemon holds itself alive until
  the stock values are actually restored; it does not exit leaving a capped
  battery unowned.
- The helper registration needed by this feature is tracked separately from the
  Low Power Mode control intent, so approving the helper from the charge-limit
  group does not opt the user into Low Power Mode control. The demand follows a
  held cap, so an idle app does not keep the daemon registered-and-polled.
- The SMC bridge requires an exact four-character key and the per-key data
  type/width on every read and every write; a read payload outside the known
  charge values is treated as absent, so an unrecognised firmware value is
  never adopted or restored over.
- The journal also records the OS build (`kern.osversion`); a record from a
  different build is refused.
- A journal left by a killed helper is reconciled at the next helper start:
  stock values are restored, or the record is kept and the daemon stays alive
  when the current hardware value belongs to something else.
- When a connection that only verified a saved session disconnects, it still
  owns quit restoration; the app quits and the stock ceiling is restored.
- Before sleep the app asks the helper to force the Silicon gate closed (a
  temporary full charge is preserved, and Intel's firmware ceiling is a no-op);
  wake re-evaluates from hardware.
- The settings group offers an explicit "Restore original charging" entry
  whenever the app cannot confirm the cap (failed verification, failed restore,
  or a foreign change). Turning the limit off performs the same verified
  helper operation.
- The battery details page shows one compact row (target + state + a single
  full-charge/cancel action) derived from the controller; it adds no second
  battery monitor and no timer.
- The main battery card shows no charge ceiling (product decision, user
  2026-11-04). It does offer one plain action for older systems, where the
  native PowerUI action does not exist: "charge to full once" while a cap is
  held, "cancel full charge" during a temporary full charge. The native 26.4+
  action area and the legacy action never appear together. Tests pin the action
  per state and assert the card stays well below the full details row.
- `SMCPrivateAPI`: minimal AppleSMC IOKit bridge whose write allowlist is
  `BCLM`/`CH0B`/`CH0C`/`CHTE`; linked only into the root helper.
- Shared typed XPC capsule + combined protocol; Low Power Mode and the charge
  limiter remain independent surfaces.
- App-side availability (OS band, runtime architecture including Rosetta,
  internal battery, probe facts), XPC client, controller and the Settings group,
  localized in all 12 shipped languages.
- The "prefer the system battery optimization" hint is gated by an explicit
  macOS 26.4+ check, not by the private-API capability.

**NOT RUN (no target hardware in this session):**

- Any real SMC read or write on Intel or Apple Silicon macOS 13/14/15.
- Charge cutoff behaviour at the requested ceiling, plug/unplug, sleep/wake and
  lid-close.
- Helper install/approval on a Developer ID build, XPC handshake at runtime.
- Universal/signed/notarized packaging and macOS 13 runtime acceptance.

`bash scripts/verify-local.sh full` passes for source, build and native
contracts, but it is not hardware evidence.

## 9. Manual reset procedure (must be validated on real hardware first)

If the limiter cannot be turned off normally:

1. Open Status Trio → Settings → Battery → turn the legacy limit off. The app
   asks the helper to restore the journaled stock values and verify the
   readback.
2. Quit Status Trio. The helper restores the journal on client loss, then
   idle-exits.
3. If the app is gone and hardware remains capped: reinstall the same
   development build and repeat step 1. On Intel, `BCLM` may persist in
   firmware; after a full charge to 100% the ceiling returns to stock.
4. If the helper cannot be reached, the journal is under
   `/Library/Application Support/StatusTrio/`; a maintainer can inspect it, but
   must not delete it before restoring, or the stock value is lost.

This procedure is a design requirement for release; it has **not** been
exercised on hardware.
