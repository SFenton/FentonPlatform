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

Admission is delegated to a separately installed runner named by an external
`runner.json` manifest (`distribution`, version, executable, package root, and
package digest). The
trusted root also supplies its own repository map and policy, an externally
owned state directory, and an external HMAC key for producer-attested receipts.
The same-user boundary is residual: this is integrity checking, not an OS
sandbox.
