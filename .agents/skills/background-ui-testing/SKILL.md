---
name: background-ui-testing
description: Use when any agent or harness tests a UI while the user continues working, requests non-disruptive Computer Use, or places test windows on a secondary display.
license: Apache-2.0
metadata:
  author: lingyired
  version: "0.1.0"
---

# Background UI Testing

Run the project's authorized Computer Use (CU) workload while preserving the
user's foreground app, input focus, pointer, clipboard, and workspace.
The project, its agent, and test tools own the test cases, steps, assertions,
functional acceptance, and reports. They may define or update the workload
within the task's scope; a prewritten suite is not required. This skill adds
no testing-method requirements and must not expand or replace the workload
to satisfy its own procedure.

This skill governs background execution: target binding, non-disruptive
launch and input, interference observation, stopping, and resource cleanup.
It supplies no driver or isolated input session and cannot make every
provider or app background-capable. A second display alone does not isolate
input. Instructions apply only when the harness loads them.

Read [harness-adapters.md](references/harness-adapters.md) for tool capability
assessment and [macos.md](references/macos.md) when relevant. Use
[project-adapter.md](references/project-adapter.md) to connect existing project
instructions without importing a testing methodology.

## 1. Bind the existing workload to a safe target

Read the project's task, tool restrictions, launch/connection route, and
cleanup rules. Identify the authorized process/window/context/session and
resources the run owns. Keep the user's working target and data separate;
check shared resources rather than assuming a distinct ID guarantees isolation.
No particular build type, launcher, app ID, or integration architecture is
required.

Assess launch, attachment, reads/capture, placement, and input independently
for the operations the workload uses. Prefer supported target-scoped actions.
Tool names, exposed AX/DOM access, and background launch flags do not establish
non-interference. Input inside an isolated session may be suitable only if
its effects are confined there; never redirect input through the user's
active session.

Resolve unknown effects through supplied documentation, read-only evidence,
or a separately authorized isolated calibration. Do not probe a potentially
disruptive route while the user works. If project adaptation advice is
requested, first assess its actual stack and available routes; the developer
and their agent decide implementation. See the [integration boundary](references/project-adapter.md).

## 2. Observe interference during execution

Reuse suitable project or harness observations. Before live launch,
attachment, capture, or input, establish the available baseline and time
coverage for foreground activation, input focus, pointer/clipboard, and workspace effects.
State which dimensions cannot be observed. No separate observer, new file,
app instrumentation, or report schema is required.

Keep observation bounded, associated with the actual target and action times,
and explicit about resolution, gaps, and blind spots. Any observer started
by the run needs an owner, deadline, and stop condition. Include launch and
attachment or state that their interference was not measured.
For evidence limits and cleanup, read
[evidence-and-cleanup.md](references/evidence-and-cleanup.md).

## 3. Execute the supplied tests without disturbing the user

Use the assessed background route for the project's existing steps.
Do not add a sample toggle, navigation, screenshot, or other functional
check as a background capability gate. Preserve read-only scope. File-only
work needs no live attachment. Leave assertions and functional verification
to the project's test procedure.

If placement is requested, use a supported app or tool route with assessed
effects. Do not move unrelated windows or switch the user's workspace.
Record missing displays or placement fallback without claiming that the
requested display was covered.

Do not activate then restore focus, use the user's global keyboard/pointer
input, or overwrite the user's clipboard to bypass a missing capability.
Observe the workload as it runs; do not manufacture additional user actions
to demonstrate non-interference. An observation window expiring does not
require restarting the target or repeating a functional test: renew coverage
before continuing, and disclose earlier gaps.

## 4. Stop the affected route or use an authorized fallback

If the route interferes, is known to require the user's focus/input, cannot
reliably target the test instance, or needs an unavailable unlocked UI, stop
the affected operation. Preserve available evidence and continue only
independent, authorized work whose background route is supported.

Report the capability gap. A different route, foreground handoff, or isolated
session needs its own assessment and applicable authorization; do not silently
switch. Do not install tools, grant permissions, change system settings,
modify the app, or invent replacement tests just to bypass the gap.
Installation of this skill is not authorization for those changes.

## 5. Release owned resources and report interference

Follow project cleanup at the actual ownership boundary. Release only
resources due for cleanup; closing one test context must not terminate a
shared host. Restore only changes still owned by the run and within the
agreed cleanup scope. Preserve later user changes or uncertain ownership,
and explain anything left unresolved.

Use existing project/tool reporting conventions. Add what is needed to
explain background execution: the target/route, observed interference or
limits, relevant coverage/evidence, unsupported operations, and cleanup.
Do not impose status names or a test-report format, or redefine the project's
functional result.

Functional success does not establish non-interference. Observed activation
still counts as interference even outside a recording; an uncovered action
does not support a zero-interference claim. Distinguish test-caused effects
from unrelated user activity. Scope claims to the actual environment, route,
operations, measured dimensions, and interval; reassess affected capabilities
when these change.
