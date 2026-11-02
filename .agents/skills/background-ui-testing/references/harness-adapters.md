# Harness capability adapter

Read the active harness's supplied API documentation first. Use only actual
available interfaces; do not guess tool names or copy another harness's API.
Local restrictions on tool choice still apply.

Before live input, establish this small capability record in the run notes:

| Capability | Evidence to record |
| --- | --- |
| Target selection | Exact PID/path, window ID, browser context/profile, or other unambiguous instance identity |
| Launch and attach | Whether either raises, activates, reopens, changes desktops, or starts another instance |
| Observation | Whether AX/DOM reads and screenshots are instance-scoped and side-effect free |
| Input | Whether each action uses remote AX/DOM/window input or foreground/global keyboard/pointer input |
| Interference trace | Foreground/input focus, pointer/workspace effects, timestamps, resolution, and blind spots |
| Lifecycle | Supported background launch, hard observation timeout, ownership, graceful stop, and restore |

Use "unknown" rather than inferring behavior from the tool's name. Unknown
side effects block that action while the user is working. Documentation may
justify a bounded attempt, but only a matching live gate supports PASS.
If required observations are unavailable, report the acceptance limitation.

## Native desktop CU

Observe the target's accessibility state before deriving element indices.
Reobserve after actions and verify actual values/content. Prefer semantic
actions when they work; a coordinate fallback must be scoped to an observed
target window and separately proven not to move the user's pointer or focus.
An element that can be enumerated may still reject or ignore a press.

## Browser automation

A dedicated browser context can isolate storage; it does not automatically
isolate OS focus, dialogs, the pointer, or system clipboard. Check whether the
harness opens/focuses tabs, navigates a user-owned tab, invokes foreground
shortcuts, or captures a whole display. Use a separate test profile/context
when authorized and keep its identity distinct from the user's session.
Headless results cover headless behavior only.

## Other MCP or OS automation

Apply the same contract regardless of whether input comes through an MCP,
driver, accessibility bridge, or OS wrapper. A command-line wrapper around a
GUI action is still a GUI action. A tool that requires foreground/global input
belongs in an explicitly foreground test, not an activate/restore loop.
This skill neither requires nor authorizes installing a third-party provider.

MCP-exposed desktop CU providers are judged by the same capability record: an
MCP tool name is not evidence of instance-scoped input. Confirm whether the
provider's click/type/scroll use remote AX/DOM/window actions or
foreground/global events, and whether its screenshots and accessibility reads
are instance-scoped. If the current session exposes no CU provider, say so
explicitly and report the affected steps as blocked; do not silently substitute
`osascript`, `CGEventPost`, or `cliclick`.

## Provider-specific adapters

Discover the interface exposed in the current session and use its
documented target binding, observation, input, and screenshot methods. Do not
assume old method names, persistent element indices, or old tool behavior.

Keep observed attachment side effects, unsupported routes, provider versions,
and reproduction evidence in the project's adapter. Retest the affected gate
when the harness, service identity, or attachment route changes. A provider
installed on disk but not exposed to this session is unavailable to this run.
