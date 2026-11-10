# Evidence and cleanup

Use existing project/tool reports for the supplied tests. Add only the
information needed to explain background interference, coverage limits, and
cleanup. This guide defines no test cases, functional evidence requirements,
report schema, or status vocabulary. A tool-output reference may be sufficient;
a browser context need not have a separate PID or local evidence file.

## Interference evidence

Associate observations with the actual target, route, operations, and time
interval. Distinguish foreground activation, input focus, pointer, clipboard,
and workspace effects as far as the available tools can observe them.
Describe resolution, gaps, and missing measurements rather than inferring
non-interference from silence.

Use the same clock basis for actions and observations or record how they
were correlated. A fresh trace can observe the same instance; a new recording
does not require restarting the app or inventing a new PID.

If an action occurred outside the trace, explain that its interference was
not measured. If a missing capability prevented measurement, explain that
limitation. Independently observed activation remains evidence of interference
even without a valid trace. Leave functional outcomes to the project's tests.

Saved-artifact inspection provides no live interference measurement and needs
no attachment. Do not launch a UI or add a functional probe to obtain a
background result for file-only work.

## Cleanup ownership

Follow project cleanup for test data and application state; this skill does
not define a new reset procedure. For background-execution changes such as
window placement or owned observers, retain enough ownership information to
release or restore them safely.

If another actor changed the value, or ownership cannot be established,
preserve it and explain why restoration was withheld. A current
value equal to the test's write is not, by itself, proof that nobody changed
it in between. Continue safe cleanup of other resources.

Release resources at their actual ownership boundary. For an owned browser
context, close that context rather than a shared browser process. For a
pre-existing test target, follow the agreed cleanup scope instead of assuming
that attachment authorizes termination. Confirm release or timeout of
resources due for cleanup, and record any unresolved cleanup. Do not terminate
an unrelated app or restore a whole shared preference snapshot over concurrent
changes.

## Sharing evidence

Keep evidence local unless sharing is part of the authorized task. Prefer
the target window or relevant AX/DOM subtree over unrelated screen content.
Before publishing an example, remove credentials, notifications, private
paths, profile data, and unrelated app content. Label synthetic examples as
illustrative; they do not establish a provider's runtime capabilities.
