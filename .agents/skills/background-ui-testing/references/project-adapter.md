# Adopting the contract

Leave test planning to the project, its agent, and tools: what to test, the
steps, data/fixtures, assertions, functional acceptance, and reporting.
A prewritten plan is not a prerequisite. This skill only governs whether
and how the authorized CU operations can run without disrupting the user's
session.

## Connect existing project instructions

Reference existing information needed for background execution:

- The authorized target and how the tool binds to it without taking over
  the user's working instance or data.
- Supported launch, attachment, input, and optional placement routes, including
  known activation or global-input effects.
- Available interference observations and their limits.
- Resource ownership, project cleanup, and authorized fallback routes.

Reuse the project's terminology and documents. No new adapter format,
launcher, development identity, observer, or control inventory is required.
Do not collect a stack/build inventory just to run an already-supported route.
Missing background support is a capability gap, not a reason to add tests
or change the project's acceptance criteria.

## Integration boundary

If adaptation advice is requested, inspect the actual stack, lifecycle,
automation interfaces, and relevant build/packaging routes before suggesting
options. Prefer existing capabilities and low-impact, removable approaches.
The developer and their agent decide whether and how to implement them within
the authorized scope; no plugin, helper, file count, or per-window pattern
is prescribed.

App adaptation, production-build isolation, and normal application behavior
remain project engineering responsibilities. This skill does not initiate a
release audit or prescribe their verification suite. If test support is added,
it should not affect normal production use; background-execution evidence
alone proves neither that isolation nor release readiness.

When a supplied operation cannot run safely in the background, explain the
limitation and supported options. A foreground or isolated-session fallback
requires its own assessment and authorization. Do not silently replace the
project's CU workload with headless checks or a new test design.

## Instruction-file entry

Place this rule in `AGENTS.md` or the instruction entry point the harness
actually reads. Resolve the skill link against its installed location; adjust
it if the project uses another layout.

```markdown
## Background UI Testing

When testing a UI while the user continues working, read and follow
[background-ui-testing](.agents/skills/background-ui-testing/SKILL.md).
This applies to every agent, harness, and Computer Use provider.

Use this project's supported test target and documented tool restrictions.
Leave test cases, steps, assertions, functional acceptance, and reporting to
this project and its agent. This skill adds no testing-method requirements.
Assess the background execution route before launch,
attachment, capture, or input; observe focus, input, pointer, clipboard, and
workspace effects within known time coverage.
Do not add capability-probe tests or mutations. Stop unsupported or disruptive
operations; never activate then restore. Explain background limitations and
cleanup using the existing report, without redefining the functional result.
Restore only still-owned mutations and release resources within this run's
cleanup scope; do not terminate a shared host to close one test context.
```

If a harness cannot load skills, copy the rule into its actual instruction
file and supply the skill text as a referenced document. Do not claim that
`AGENTS.md`, a filename convention, or skill installation enforces behavior in
every runtime. Verify discovery in that runtime. Keep this entry short and
maintain the full execution contract in one skill.

This entry applies when background testing is requested. A project may
separately choose background testing as its default for live UI work; state
that policy in its own instruction file. Installation alone does not make
every UI task a background test.

## Distribution

The repository copy is versioned source. For personal reuse, a copy can be
installed under `~/.agents/skills/background-ui-testing` for harnesses that
discover that directory. Other harnesses need their own supported skill path
or instruction reference. No global instruction files need to be overwritten.

Keep relative references within the skill so the directory can move intact.
`agents/openai.yaml` is optional Codex UI metadata; other harnesses can ignore
it. The core `SKILL.md` has no hardcoded CU API, machine path, dependency, or
permission requirement. Installing the skill does not install a provider or
grant permissions.

Maintain the standalone repository as the upstream source. Record the
installed version or commit and use the installing harness's supported
update mechanism. Before replacing a copied skill, detect local changes;
do not overwrite them silently. Keep project-specific adapters in their
own repositories so upstream updates do not replace local policy.
