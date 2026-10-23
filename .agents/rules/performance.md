# Performance rule

Read this before changing polling, timers, animation, image caches, memory
ownership, observation subscriptions, or anything that runs while the popover
and windows are closed.

- Keep the app low-power at rest. Stop demand-driven work when its surface,
  permission, or device disappears, and bound caches and retry loops.
- Reuse the existing measurement scripts rather than inventing a benchmark:
  `scripts/measure-menu-bar-charging-cpu.sh`,
  `scripts/measure-dock-charging-cpu.sh`, and `scripts/measure-memory.py`.
- Record hardware, process provenance, scenario, duration, and baseline. An
  offline render or test count is not a runtime performance pass.

See `docs/performance/menu-bar-charging-cpu-optimization.md`,
`docs/performance/dock-charging-cpu-optimization.md`, and
`docs/performance/memory-audit-2026-10-20.md`.
