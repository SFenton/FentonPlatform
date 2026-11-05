# Agents and trust

Roles and read-only advisors are reusable contracts. The trusted runner,
policy and evaluator are outside a candidate worktree. This repo does not claim
same-user sandboxing or autonomous merge. Review admission requires exact SHA,
independent reviewer, executed tests and protected-path approval.

Candidate-supplied booleans, changed-path lists, source SHAs, and arbitrary
evidence strings are not trusted review inputs. Protected approval comes only
from the external policy's reviewer allowlist.

The role and source-execution assets currently describe boundaries and invoke
deterministic helpers; they do not constitute a continuously running
orchestration daemon.

Decision calls are disabled; normalization supports replay and abstention only.
Learning is proposal/shadow-only and automatic promotion is disabled.

## Bounded runtime

`python -m fenton_tooling.runtime` is the standalone runtime entry point. Jobs
are explicitly registered DAG nodes with bounded attempts; failed prerequisites
block dependents. Durable state and the single-writer journal live outside the
candidate repository. Dead active owners are reconciled as orphaned and
rejected; resumption is manual.
The writer lock uses an OS-backed POSIX advisory lock, so a crashed writer
does not leave a stale lock namespace.

`runtime dispatch` reads its job registry, profile, and policy only from an
external trusted root. The repository `.fenton/runtime.json` is only a
proposal template and cannot self-register jobs or grant authority. A
deterministic own-repository smoke can be run in a clean isolated candidate
from an installed wheel with:

```text
python -m fenton_tooling.runtime dispatch --repo-root <candidate> \
  --trusted-root <external-profile> --state-dir <external-run-state> \
  --source-sha <candidate-head>
```

Dispatch performs verification only; a `verifying` or `pending-review` result
is not an acceptance or promotion. Cancellation and timeout remain distinct
durable outcomes, and only explicit resume may retry an orphan within its
persisted attempt bound and run identity.

The runtime verifies a clean source root and exact SHA before dispatch. Existing
`run_plan` process-group cleanup handles owned timeout and cancellation.
Acceptance requires an externally produced, attested receipt and independent
exact-SHA review; candidate booleans and self-issued receipts never certify a
job. Acceptance delegates to the established external pinned CLI review
pipeline and consumes only its externally persisted accepted task with the
same exact SHA. Missing trusted runner state, moved HEAD, failed review, or
empty reviewer allowlists remain blocked. The runtime never applies repository
changes or grants production or cross-repository authority.
The operator must stage the external task, signed receipts and reviewer
authorization; dispatch does not issue them.

The Copilot host adapter constructs strict argument vectors from registered role
contracts, launches from an external trusted CWD, disables custom instructions
and built-in MCPs, and never uses blanket permissions. Unknown providers/models
are rejected, and missing usage is recorded as unreconciled. The installed CLI
help used by the adapter is retained in the session artifact
`fp-copilot-help.txt`. Preview it with
`python -m fenton_tooling.runtime dry-run --prompt "inspect the registered
task"`. After independent review, an operator may execute the emitted argv
from the external trusted CWD outside this package; `run_invocation` remains
fail-closed until qualified external host-grant/budget integration exists.

Learning is shadow-only: bounded categorical friction metadata can produce at
most three untested synthetic proposals, with no transcript collection or
automatic apply.
Decision providers are disabled without an actual grant and budget. Jev and
OpenRouter use separate calibration/cache namespaces; replay and low-confidence
answers abstain.
