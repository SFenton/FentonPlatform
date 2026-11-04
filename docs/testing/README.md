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
locally, but full consumer/form-factor CI is not automated and physical-device
claims are not certified by this bootstrap.

Current evidence covers Python 3.9/3.12 tooling, Mac-host Core and Telemetry
tests, and the hosted iOS/UI harness cases. It does not certify the complete
Apple form-factor matrix, physical-device performance, consumer compatibility,
Windows, or Android. Remote private-consumer authentication is not configured.
The source-execution roles and adapters are reusable contracts and deterministic
helpers; they are not a fully operational orchestration daemon.
