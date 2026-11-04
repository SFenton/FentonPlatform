# Testing

Run `python -m unittest discover tooling/tests`. The normalized result model
rejects empty and all-skipped runs as certification. Test selection is
deterministic from `.fenton/repo.json`; unknown changed paths fail explicitly.
Certification additionally requires exit code `0`, at least one passed test,
zero failures, and consistent totals where `executed = passed + failed +
skipped`.

Portable CI targets Linux and macOS. Native Apple UI evidence and physical-device
claims are not implemented by this bootstrap.
