# Apple Watch first battery reading and row layout

## Scope

Apple Watch battery readings use the trusted paired iPhone companion route. A
nearby device name is not proof of association, and this change does not add
reads for unselected or hidden devices. Both Apple-device display and background
battery refresh remain off by default.

## First-read scheduling

Phone and selected Watch jobs share a bounded queue with at most two concurrent
helper reads. Watch jobs are interleaved with phone jobs instead of waiting for
an entire phone batch, so unrelated slow phones cannot occupy both workers
before any selected Watch starts. The overall cycle timeout still preserves
completed observations; it is not extended to hide a stuck route.

An authorized Watch with no valid cached battery observation receives at most
three initial retries at one-minute intervals while reading demand remains
active. After that budget is used, normal refresh cadence resumes. A successful
Watch observation clears its retry budget; a successful phone observation alone
does not. Watch-only initial retries do not reread healthy phones or move the regular
full-refresh deadline. Results are accepted only for the devices requested in
that read and still authorized when it finishes. Healthy cached readings use
the normal configured interval. Disabling background refresh does not enable hidden background work: with no visible
popover demand, reads and retries stop. Background intervals remain 1–10 minutes.

These changes remove reproducible scheduling delays, but cannot guarantee that
a real iPhone/Watch companion route supplies a reading within a fixed duration.
The reported ten-minute first reading still requires hardware retesting; it is
not established that either scheduling issue alone explains the entire delay.

## Row presentation

A trusted-device row renders its detail line only when actual detail exists
(currently an observed charging state). Missing charging metadata or a false
charging flag does not create an empty second line. List-height estimates use
the same detail visibility rule, including alias-resolved metadata.

A pending battery reading leaves the trailing battery area blank, rather than
rendering a dash or a zero-percent value. Actual valid readings (including 0%)
and explicit availability states retain their separate meanings. AirPods
component readings and genuine charging details keep their existing layout.

## Verification

Regression tests cover fair shared helper scheduling and the concurrency cap,
bounded initial Watch retries, success/partial success, demand cancellation,
rendered row height, pending trailing pixels, and preservation of real charging
and AirPods component details. Use the following before integration:

```bash
swift test
swift build -c release
bash scripts/test-mobile-battery-helper.sh
bash scripts/check-forbidden-patterns.sh
git diff --check
```

Actor-isolated controller changes are verified locally. The repository is
local-first and does not require a remote CI preflight before merging; use the
focused filter while iterating and the `full` local profile on the final
integrated tree:

```bash
bash scripts/test.sh 'AppleDeviceDiscoveryControllerTests|MobileBatteryHelperReaderTests'
bash scripts/verify-local.sh full
```

No release, installed app replacement, or credential change is part of this fix.
