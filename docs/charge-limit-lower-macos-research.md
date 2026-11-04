# Charge-limit support on older macOS and Intel Macs

Research note for issue #187 / PR #207, written 2026-11-04. It records what
other open-source projects do and what adding lower-version support would
actually require. Links are external and were current on that date.

## Why this note exists

The managed charge limit in PR #207 uses the private PowerUI MCL interface.
That interface only exists on Apple silicon running macOS 26.4 or later, so the
feature cannot appear on Intel Macs or on macOS 13–26.3. On 26.4+ macOS already
offers a native charge limit (80–100%), which raises the product question: what
does Status Trio add, and should it support lower versions through another
mechanism?

## Reference projects

| Project | Scope | Mechanism | Lowest macOS |
| --- | --- | --- | --- |
| [charlie0129/batt](https://github.com/charlie0129/batt) | Apple silicon; Go daemon + native menubar GUI, MIT | SMC charge keys, firmware capability probing | macOS 11 (by firmware) |
| [actuallymentor/battery](https://github.com/actuallymentor/battery) | Apple silicon only | SMC keys / `smc` CLI | Apple silicon era |
| [alvarohurtadobo/charge-limiter](https://github.com/alvarohurtadobo/charge-limiter) | Intel MacBooks | `BCLM` SMC key | Intel era |
| [hholtmann/smcFanControl `smc-command`](https://github.com/hholtmann/smcFanControl/tree/master/smc-command) | Generic SMC access | raw SMC key read/write | long-standing |
| [charlie0129/gosmc](https://github.com/charlie0129/gosmc) | SMC library used by `batt` | Go bindings over IOKit | — |

### What `batt` establishes

- macOS 26.4+ ships a native charge limit (adjustable 80–100%); `batt`'s own
  README says it is not needed when that range is enough. It stays useful on
  older releases and for limits below 80%.
- It does not branch on the macOS version. It probes usable SMC keys at runtime
  (mainly tied to firmware, not OS), which also handles an older macOS receiving
  newer firmware.
- Compatibility is described by firmware version, from macOS 11 Big Sur up.
- On Intel, charge limiting is the simpler `BCLM` SMC key; `batt` is
  Apple-silicon-only and points Intel users at that route.
- Starting with macOS 27-era firmware, the SMC charge-control keys
  (`CH0B`/`CH0C`/`CHTE` and `bfF0`/`bfD0`/`bfE0`) are gated behind the private
  entitlement `com.apple.private.iokit.soc-limit`; root is not enough. The
  native System Settings limit still works (enforced by `powerd`), but only at
  80% or above. `batt` adds an opt-in adapter mode that toggles wall power
  instead of the charge state.

## Mechanisms available to Status Trio

1. **Private PowerUI MCL (current PR #207)** — Apple silicon, macOS 26.4+,
   reacts to the same native limit System Settings exposes. Lowest risk, but
   no lower-version support.
2. **SMC charge keys** — Apple silicon `CH0B`/`CH0C`/`CHTE`; Intel `BCLM`.
   Works on older macOS, but needs a privileged writer. Status Trio already
   ships a privileged Helper, so this is technically reachable, but it brings
   sleep handling, firmware variance, model variance, and the macOS 27
   entitlement gate. This is essentially re-implementing `batt`.
3. **Native macOS limit only** — on 26.4+ let the system own the limit and keep
   Status Trio's value to automation only (reapply on launch/wake/replug,
   cooperate with Charge to Full Now).

## Recommendation

- Keep the current PowerUI path as the 26.4+ automation layer. It is the only
  path that needs no privileged charge-key writes.
- If lower-version or Intel support is wanted, do not grow the PowerUI bridge.
  Either integrate/port the SMC approach `batt` uses (its compatibility matrix
  and sleep edge cases are the reference), or accept that the feature is
  26.4+ only and say so plainly in the UI.
- Prefer the system's own battery optimization on 26.4+; a fixed cap is a
  deliberate user choice, not the default recommendation.

## Links

- <https://github.com/charlie0129/batt>
- <https://github.com/charlie0129/gosmc>
- <https://github.com/actuallymentor/battery>
- <https://github.com/alvarohurtadobo/charge-limiter>
- <https://github.com/hholtmann/smcFanControl/tree/master/smc-command>
