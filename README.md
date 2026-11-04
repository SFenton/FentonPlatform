# FentonPlatform

Private shared foundations for Fenton consumers. This bootstrap contains the
portable `fenton-tooling` package, contract schemas, reusable role assets, and
this repository's own operating profile. Apple sources are intentionally owned
by the Apple worker and are not part of this bootstrap.

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -e .
python -m fenton_tooling doctor
python -m fenton_tooling check
python -m unittest discover tooling/tests
```

The trusted runner must be installed outside a candidate worktree. This package
does not provide an OS sandbox, merge authority, provider credentials, or live
consumer/production access. Windows and Android remain future native lanes.

## Boundaries

`tooling/src/fenton_tooling` is deterministic and stdlib-only at runtime.
`.fenton` is this repo's profile; `contracts` are language-neutral schemas;
`agents` are reusable role/advisor descriptions; `.github` and `.claude` are
thin host descriptors. Operational state belongs outside git.

License: all rights reserved to SFenton. See `LICENSE`.
