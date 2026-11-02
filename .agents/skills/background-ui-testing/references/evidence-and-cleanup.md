# Evidence and cleanup

Use a short Markdown record or equivalent structured data. Record facts;
missing fields are unknown, not an invitation to probe the user's session.

## Run record

```text
Run: <unique run ID>
Target: <executable/profile, PID/context ID, build/commit, dirty state>
Harness: <provider, version, exposed capabilities, attachment route>
Environment: <OS, displays/scaling, requested and actual placement>
Observation: <start, deadline, clock basis, actual gaps, output path>
Actions: <action ID, target identity, start/end time, observed outcome>
Functional result: <PASS | FAIL | BLOCKED | NOT RUN, evidence>
Foreground activation: <status, evidence interval, resolution, blind spots>
Input focus: <status, evidence interval, resolution, blind spots>
Pointer: <status, evidence interval, resolution, blind spots>
Workspace: <status, evidence interval, resolution, blind spots>
Cleanup: <owned resources stopped, values restored, preserved conflicts>
```

Use the same clock basis for actions and observations or record how they
were correlated. A fresh trace can observe the same instance; a new recording
does not require restarting the app or inventing a new PID.

An action outside the trace has interference measurement NOT RUN. If a
missing capability prevents measurement, that measurement is BLOCKED.
Independently observed activation remains FAIL even without a valid trace.
Judge functional outcome separately.

For file-only inspection of an existing screenshot, record its source and
timestamp if available. Live interaction and live interference measurements
are NOT RUN; do not attach to an app merely to inspect a saved artifact.

## Change ledger

For each mutation, record the target domain/resource, original value,
value written by this run, action time, and any available revision or
ownership evidence. Before restoring, read the current state and check
whether the run still owns that mutation.

If another actor changed the value, or ownership cannot be established,
preserve it and mark that restoration BLOCKED with the reason. A current
value equal to the test's write is not, by itself, proof that nobody changed
it in between. Continue safe cleanup of other resources.

Stop only observers and test instances created or explicitly owned by the
run. Confirm exit or timeout, and record resources left running. Do not use
cleanup to terminate an unrelated app or restore a whole shared preference
snapshot over concurrent changes.

## Sharing evidence

Keep evidence local unless sharing is part of the authorized task. Prefer
the target window or relevant AX/DOM subtree over unrelated screen content.
Before publishing an example, remove credentials, notifications, private
paths, profile data, and unrelated app content. Label synthetic examples as
illustrative; they do not establish a provider's runtime capabilities.
