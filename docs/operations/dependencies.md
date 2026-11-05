# Dependency and source manifest

The runtime package has no third-party dependencies. `setuptools` is a build
requirement only. The repository's portable checks use Python standard-library
`unittest`, Node's standard filesystem module, and pinned GitHub Actions for CI.
No copied third-party skill corpus or private source is distributed.

## Native platform inventories

Native dependencies are tracked separately from the portable runtime:

- `integrations/dependencies/windows.json` records exact Windows project-assets
  resolutions and cached NuGet license metadata.
- `integrations/dependencies/native.json` records Android Gradle verification
  metadata, wrapper integrity, and cached-POM license observations.

Only standard SPDX identifiers observed in cached metadata are emitted as SPDX.
Microsoft SDK/proprietary terms and missing metadata use explicit `LicenseRef-*`
entries with source URLs and `review_required: true`. Native publication remains
blocked until those review items are resolved by the parent-owned license
workflow.

The dependency guard validates declared direct references against these exact
inventories, wrapper hashes, and explicit review markers. It does not inspect
private source or call external services.
