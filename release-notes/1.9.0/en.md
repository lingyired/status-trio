# Version %VERSION% (Build %BUILD%)

### Battery

- Added an opt-in native charge-limit picker for supported Apple silicon Macs running macOS 26.4 or later. Choose a system-provided limit, keep it across launches, and restore the original recorded limit with System Managed.
- Managed limits reapply on launch, wake, and power-state changes without additional polling. Charge to Full Now temporarily suspends the selected limit; cancellation, completion, or reconnecting power resumes it. External limit changes pause management until an explicit selection or Reapply.
- Writes and restorations are verified, and interrupted operations retain recovery records. This feature uses a private PowerUI interface; behavior depends on macOS and hardware.
- Added an optional "split" mode for the battery ring. When the top gap shows a bolt, plug or percentage, the left visible half now reads 0–50% and the right half 50–100%, so levels between 40% and 60% no longer hide behind the gap. It is off by default and applies to both the menu bar and the Dock.
