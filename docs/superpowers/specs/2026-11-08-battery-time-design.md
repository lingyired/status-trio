# Battery remaining time in the status panel (#298)

Show the system's battery-runtime estimate directly in the summary subtitle, by default, as selected by the user. Keep the existing charging estimate and state priority. No additional setting, polling, persistence, or icon changes.

Read positive `kIOPSTimeToEmptyKey` minutes through `BatteryReading` and `BatteryStatus.timeToEmptyMinutes`. Publish runtime estimates only for a present, unplugged, non-charging battery. Missing, zero, or negative values mean unknown. Connected, fully charged, absent, and Charge to Full Now states retain their current priority; Low Power Mode on battery keeps its label and appends a valid runtime estimate.

Use a localized duration formatter for hours/minutes and grammatical number, bound to the selected app language. Translate the surrounding approximate-runtime phrase in all 12 shipped languages. Invalid estimates fall back to the existing subtitle. Accessibility uses the same subtitle. Both battery-label branches wrap long subtitles at the existing panel width, allowing all translated estimates and the Low Power Mode prefix to remain visible.

Approaches: the chosen subtitle approach reuses the summary mapper and preserves space. A separate percentage-side label changes layout unnecessarily; a new preference adds state for a small default improvement. Existing charging text already appears in the summary, so preserve it.

Constraints: macOS 13+, unchanged IOKit notification lifecycle and refresh cadence; unchanged Menu Bar/Dock scenes and cache keys. Add focused parser, monitor, subtitle, localization, and estimate-update tests; the shared snapshot change requires the full local delivery profile. Hardware/runtime and Ventura checks remain NOT RUN unless actually performed.
