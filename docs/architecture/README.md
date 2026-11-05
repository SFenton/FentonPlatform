# Architecture

FentonPlatform separates native platform foundations from portable testing and
orchestration. Portable code depends only on Python's standard library and
language-neutral contracts. Consumer routes, domain state, credentials and
production authority stay in consumers.

## Product and authority boundaries

Implemented foundations include the SwiftPM Apple products and neutral harness
under `platforms/apple`, plus the installable portable tooling and contracts.
The portable package has no runtime dependencies beyond the Python standard
library. Consumer pilots pin immutable revisions and preserve each app's own
routes, theme and modal policies; their evidence and promotion status are
tracked separately in [Consumers](../consumers/README.md).

Windows and Android have experimental native libraries plus separate harnesses,
not UIKit translations or consumer rewrites. Their NuGet/Gradle dependencies
are scoped to those platforms; Apple and portable consumers do not acquire
another platform's SDK.

The bounded runtime dispatches registered verification jobs and delegates
admission to a separately installed pinned review pipeline. State, trusted
policy, signed receipts and reviewer authority remain outside the candidate.
Live model launch, decision providers, automatic promotion and production access
remain disabled. This integrity boundary is not a same-user OS sandbox.

Builds and focused tests do not certify the full form-factor matrix,
physical-device performance, native accessibility/lifecycle, package licensing
or consumer promotion. See the [roadmap](../roadmap.md) for unresolved gates.

The bootstrap records extraction provenance from HASS `6b7ed89afa48cc0e22c42df04253f8250ef43039`
and Festival `04aeb01b18961a96ed7432ed58aa77676227f92e`. The portable and
Apple mechanisms are implemented from owner-reviewed behavioral requirements and
pinned-file study documented in `source-license-manifest.json`. The manifest
records the exact source paths and derived mechanisms; it does not infer a
third-party redistribution grant.
