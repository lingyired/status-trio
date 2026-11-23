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
| Lifecycle | Supported creation or connection route, bounded observation, resource ownership, scoped release, and restore |

Use "unknown" rather than inferring behavior from the tool's name. Unknown
side effects block that action while the user is working. Assess only the
routes needed by the supplied workload, without inventing sample operations
or functional gates. Observations during that workload support interference
claims only within their coverage. Report missing measurements as limitations.

## Native desktop CU

Bind actions to the current target rather than stale element indices or an
unrelated foreground window. Prefer supported semantic actions. A coordinate
route in the user's desktop must be target-scoped and established not to
move the user's pointer or focus. How the test locates controls and checks
their behavior belongs to the project's test procedure.

## Browser automation

A dedicated browser context can isolate storage; it does not automatically
isolate OS focus, dialogs, the pointer, or system clipboard. Check whether the
harness opens/focuses tabs, navigates a user-owned tab, invokes foreground
shortcuts, or captures a whole display. Use a separate test profile/context
when authorized and keep its identity distinct from the user's session.
Headless results cover headless behavior only.
Do not switch a headed CU test to headless merely to complete it under this
skill; use the project's chosen route or report the background limitation.

## Isolated desktops and remote sessions

An owned VM, remote desktop, or other isolated session may support coordinate
input within that session. Establish that input, clipboard, display capture,
and lifecycle operations do not affect the user's host session. Isolation
must come from the actual tool/environment, not the label "remote."
Keep the project's workload intact and scope observations to the claimed
isolation boundary.

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
are instance-scoped. Evaluate supported CLI or scripting interfaces by their
actual behavior too; their names alone neither permit nor prohibit them.
If no capable interface is exposed to this run, explain which steps cannot
proceed. Do not substitute an unassessed route or global input.

## Provider-specific adapters

Discover the interface exposed in the current session and use its
documented target binding, observation, input, and screenshot methods. Do not
assume old method names, persistent element indices, or old tool behavior.

Keep observed attachment side effects, unsupported routes, provider versions,
and reproduction evidence in existing project notes. Reassess affected capabilities
when the harness, service identity, or attachment route changes. A provider
installed on disk but not exposed to this session is unavailable to this run.
