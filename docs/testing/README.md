# Testing

Run `python -m unittest discover tooling/tests`. The normalized result model
rejects empty and all-skipped runs as certification. Test selection is
deterministic from `.fenton/repo.json`; unknown changed paths fail explicitly.
Certification additionally requires exit code `0`, at least one passed test,
zero failures, and consistent totals where `executed = passed + failed +
skipped`.

Portable CI targets Ubuntu with Python 3.12 and macOS with Python 3.9, the
qualified host/interpreter combinations. The matrix is non-fail-fast so a
valid host is not cancelled when another hosted image lacks a distribution.
Native Apple harness evidence has been captured
locally, but full consumer/form-factor CI is not automated and simulator
measurements do not certify physical-device claims.

Current evidence covers Python 3.9/3.12 tooling, Mac-host Core and Telemetry
tests, and the hosted iOS/UI harness cases. It does not certify the complete
Apple form-factor matrix, physical-device performance or consumer promotion.
Windows library and Android JVM tests are distinct from native UI execution;
the platform pages record their current ownership and host prerequisites.
Remote private-consumer CI authentication is not configured.

Actual installed-wheel FST Node execution and canonical Mac capacity lifecycle
tests cover the shared execution boundary. Changed-path planning rejects
missing recipe coverage; it never converts a selected component into an
executed test. Windows owned-process-tree execution in the portable runner is
explicitly unsupported until a qualified Job Object adapter exists.

The bounded runtime has deterministic dispatch/replay and external-review
integration. Live model launch is disabled; it is not a continuously running
agent daemon. Run `node tools/check-dependencies.mjs` and
`node tools/check-dependencies.test.mjs` for dependency inventory drift checks.
Passing those checks does not clear recorded license-review gates.
