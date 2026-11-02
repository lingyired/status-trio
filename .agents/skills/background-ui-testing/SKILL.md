---
name: background-ui-testing
description: Use when any agent or harness tests a UI while the user continues working, requests non-disruptive Computer Use, or places test windows on a secondary display.
license: Apache-2.0
metadata:
  author: lingyired
  version: "0.1.0"
---

# Background UI Testing

Preserve the user's foreground app, input focus, pointer, and workspace while
testing a separate UI. Apply this contract to any agent, harness, CU tool,
browser automation, or OS automation that interacts with the user's session.
Use deterministic non-GUI checks where they satisfy the task.

This skill supplies a procedure, not an isolated input session or a guarantee
that a tool or app supports background interaction. A second display alone
does not isolate focus, keyboard, mouse, Spaces, or desktops. Instructions
apply only when the harness actually loads them.

Read [harness-adapters.md](references/harness-adapters.md) to establish the
current tool's capabilities. Read [macos.md](references/macos.md) for macOS.
For project integration or another harness's instruction file, use
[project-adapter.md](references/project-adapter.md).

## 1. Establish ownership and capabilities

- Read the project's launch, build, permission, and cleanup rules. Use its
  supported test mode; never assume flags from another app are recognized.
- Identify the test executable/path, instance PID or equivalent identifier,
  development identity, build/version, and isolated preference/profile domain.
  Do not reuse production or another agent's instance to avoid setup work.
- Check launch, attachment, observation, and input independently: even binding
  a window or taking a screenshot can have side effects in some harnesses.
  Prefer instance-scoped accessibility/DOM/window actions. Tool brand, AX/DOM
  availability, and a background launch flag do not prove non-activation.
- Do not install another tool, grant permissions, reset onboarding, or change
  system settings merely to bypass a blocked background step. Follow existing
  authorization; ask only for a concrete missing prerequisite or foreground
  handoff that is actually needed.
- Use existing diagnostics where possible. If focus, pointer, or workspace
  effects are unknown or known to be disruptive, stop before that operation.
  Resolve them through documentation, read-only evidence, or a separately
  authorized calibration in an isolated session. Measurement does not make a
  potentially disruptive probe safe while the user is working.

## 2. Start a bounded observation window

Record foreground identity and available input/window focus, display/workspace,
and pointer effects with timestamps before launching or attaching. Record what
cannot be observed. Reuse project diagnostics or a short-lived external
observer; do not add resident app polling, new permissions, or private APIs.

Give every recording a start, deadline, target identity, output path, and stop
condition. A finite observer may continue briefly across a user reply, but
must have a hard timeout and a known owner; never extend it indefinitely.
Include launch/attach in the trace or mark them separately unverified.
For a compact run record and cleanup ledger, read
[evidence-and-cleanup.md](references/evidence-and-cleanup.md).

If collecting manual input, prepare the correct live instance and recording
first, then tell the user exactly what to click and the time remaining.
Before interpreting "done", verify the actions fell inside the recording.
Expired or missing coverage is not zero interference. Do not silently combine
different PIDs, clocks, launches, or user actions into one successful run.

## 3. Prove the smallest background operation

Once the capability checks permit an attempt, use the supported background
launch route and verify identity again. Place the window on the requested
display using the app's supported mechanism; record a missing display or
fallback instead of claiming secondary-display coverage.

With observation running, verify:

1. A reversible control changes its actual value.
2. A sidebar/page navigation reaches the intended content.
3. An instance-scoped screenshot captures the resulting UI.

Use only operations within the requested task. For a read-only inspection,
exercise the permitted subset and report control mutation as NOT RUN; do not
change settings just to complete this gate. An app without a sidebar can use
its equivalent navigation. Do not generalize that subset to write access.

Restore changed values when appropriate. An unchanged accessibility tree, a
successful tool return, or a screenshot alone does not prove interaction.
Continue only if those operations worked without observed target activation,
input redirection, pointer movement, or workspace change caused by the test.
Record unrelated foreground changes separately; do not blame the target
solely because another app became active.

Evidence is scoped to the app/build, harness/tool version, launch/attachment
route, display topology, and tested controls. Repeat the affected gate when
these change. A button PASS does not cover text entry, shortcuts, menus,
first-run guides, system dialogs, permission recovery, or Dock/taskbar routes.
Do not exercise known activating controls during a background run.

## 4. Stop or explicitly hand off unsupported steps

Never activate an app and restore focus afterward as a background workaround.
Do not use global clicks/keystrokes or clipboard-based input as a shortcut
around an unsupported instance-scoped action. Use an explicitly authorized
foreground session for operations that need it, and report them separately.

If the tool needs activation, uses the user's pointer, encounters a locked
screen, lacks required evidence, or cannot target the instance reliably, stop
that step. Repeated retries or switching tools are not evidence of safety.
User interaction that deliberately activates an app may pass functional
acceptance; it cannot demonstrate non-activating automation.

Report each claim separately:

| Status | Meaning |
| --- | --- |
| PASS | The stated behavior was executed and supported by matching evidence. |
| FAIL | The attempted behavior contradicted its criterion, including observed test-caused interference. |
| BLOCKED | A prerequisite or tool capability prevents the step or its acceptance. |
| NOT RUN | The stated operation or measurement was not performed/covered. |

An entry point can be functional PASS and background FAIL. An observed
activation is already evidence against non-activation even if the external
trace expired. Use BLOCKED when a missing prerequisite prevents the stated
check, and NOT RUN when that check was not performed or its action time was
not covered. Report only the dimensions actually observed; a foreground trace
does not establish pointer, keyboard-focus, or workspace behavior.

## 5. Restore and report

- Stop only owned test instances and observers, using graceful project
  procedures. Do not terminate production or another worktree.
- Restore only state changed by this run, using an isolated snapshot or a
  change ledger. Verify restored values and absence of owned processes.
  Do not overwrite concurrent changes made by the user or another agent.
  If ownership is uncertain, preserve the current value and report the
  restoration as BLOCKED; continue cleanup of other owned resources.
- Report instance/build provenance, harness/tool, displays, actions and their
  time coverage, functional result, interference result, evidence paths,
  limitations, and cleanup status. Separate manual, automated, and code-only
  checks. Sampled absence of interference has a finite observation limit.
- Provide the normal launch/foreground fallback if background use is blocked.
  Do not claim native runtime, permissions, signing, or other harness support
  from documentation, unit tests, or simulations alone.
