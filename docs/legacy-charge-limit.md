# Legacy macOS Charge Limit — Research, Baseline and Evidence

> **Status:** Phase 0 research note (no app code modified)
> **Date:** 2026-11-04
> **Branch:** `fix/207-charge-limit-compat`
> **Recorded main SHA at baseline:** `57541b8234b562640ca455ebc352f1dd20502818` (`origin/main`)
> **Branch HEAD at baseline:** `5d4513ab`
> **Plan of record:** `status-trio-legacy-charge-limit-plan.md` (user-provided 2026-11-04)

This note is the Phase 0 deliverable for adding optional, low-overhead battery
charge ceilings on macOS 13–15 (Intel and Apple Silicon) alongside the existing
native PowerUI limit on macOS 26.4+. It records what the reference projects
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
| macOS 13–15 | Intel | Eligible after probe + validation (firmware `BCLM`) | Keep system charge-to-full if present |
| macOS 13–14 | Apple Silicon | Legacy SMC inhibit (`CH0B`/`CH0C`, `CHTE`) after probe | Independent of native |
| macOS 15 | Apple Silicon | Legacy SMC inhibit by **actual capabilities**, not OS-only | See §4 gap |
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
   "Intel 13–15" target and must be settled on a real Intel macOS 13/14/15
   machine before the Intel backend is advertised.
2. **Apple Silicon macOS 15 inhibit.** Whether `CH0B`/`CH0C`/`CHTE` remain
   writable without the private entitlement on macOS 15 is not confirmed for
   this repository; batt's own docs say newer firmware gates them. The plan
   explicitly says the Apple Silicon 13/14 and 15 backends are distinguished by
   actual capabilities, not an OS-only check.
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