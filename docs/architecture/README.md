# Architecture

FentonPlatform separates native platform foundations from portable testing and
orchestration. Portable code depends only on Python's standard library and
language-neutral contracts. Consumer routes, domain state, credentials and
production authority stay in consumers.

The bootstrap records extraction provenance from HASS `6b7ed89afa48cc0e22c42df04253f8250ef43039`
and Festival `04aeb01b18961a96ed7432ed58aa77676227f92e`. The portable and
Apple mechanisms are implemented from owner-reviewed behavioral requirements and
pinned-file study documented in `source-license-manifest.json`. The manifest
records the exact source paths and derived mechanisms; it does not infer a
third-party redistribution grant.
