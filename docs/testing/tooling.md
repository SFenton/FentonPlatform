# Portable tooling

`fenton-tooling` exposes `doctor`, `check`, `select`, `run`, and `task`.
Commands use argument vectors, bounded timeouts, process-group cleanup, and
normalized outcomes. Runner plans cover parseable unittest, SwiftPM, Xcode,
.NET, web, and Gradle command shapes; detailed framework parsing remains
consumer-specific.

`review` is admission-only: it requires `FENTON_TRUSTED_ROOT` outside the
candidate, derives HEAD and changed paths from git, resumes a persisted task,
and validates bound immutable receipts, policy identity, test outcomes, and
artifact digests. Missing trusted runtime or malformed receipts block admission.

Capacity status delegates to an existing `devcap` executable (or
`FENTON_DEVCAP_EXECUTABLE`) and never starts a competing scheduler.

Resource-bearing plans use the canonical lifetime-scoped `devcap run` argv:
`pool:NAME`, `sim:UDID`, or `device:UDID`. Unsupported quantities, unnamed or
invalid devices, and a missing bridge are explicit infrastructure failures
before the child starts. The bridge owns waiting, signal forwarding, locks,
and device cleanup; tooling does not implement acquire/release locks. An
isolated owned helper drains output and cleans its child process group,
including bounded escalation when a child ignores termination, before the
bridge can release capacity. Zero-resource portable jobs do not require
`devcap`.

Registered recipes are local profile execution conveniences, not attested
trusted admission. `fenton run --recipe NAME --repo-root PATH` supplies only
the recipe's argument vector, selectors, and resource requirements; external
trusted-runner admission remains separate.
Changed-path planning fails explicitly when any selected component lacks a
registered recipe; selection alone never implies tests ran. Repeated XCTest
case lines are counted once, retaining a failure rather than allowing an
unapproved rerun to erase it. Gradle console counts remain unqualified until
an adapter supplies authoritative result artifacts.

Admission is delegated to a separately installed runner named by an external
`runner.json` manifest (`distribution`, version, executable, package root, and
package digest). The
trusted root also supplies its own repository map and policy, an externally
owned state directory, and an external HMAC key for producer-attested receipts.
The same-user boundary is residual: this is integrity checking, not an OS
sandbox.
