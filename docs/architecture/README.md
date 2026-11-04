# Architecture

FentonPlatform separates native platform foundations from portable testing and
orchestration. Portable code depends only on Python's standard library and
language-neutral contracts. Consumer routes, domain state, credentials and
production authority stay in consumers.

## Phase 0 boundary

Implemented foundations include the SwiftPM Apple products and neutral harness
under `platforms/apple`, plus the installable portable tooling and contracts.
The portable package has no runtime dependencies beyond the Python standard
library. The repository has no remote private-consumer authentication, so
consumer adoption and compatibility evidence remain separately authorized work.

The current implementation does not certify the full device/form-factor matrix,
physical-device performance, Windows, Android, or live autonomous orchestration.
Those are future capabilities, not implied by the presence of contracts,
roles, adapters, or platform directories.

The bootstrap records extraction provenance from HASS `6b7ed89afa48cc0e22c42df04253f8250ef43039`
and Festival `04aeb01b18961a96ed7432ed58aa77676227f92e`. The portable and
Apple mechanisms are implemented from owner-reviewed behavioral requirements and
pinned-file study documented in `source-license-manifest.json`. The manifest
records the exact source paths and derived mechanisms; it does not infer a
third-party redistribution grant.
