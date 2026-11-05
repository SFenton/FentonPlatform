# FentonPlatform

Private shared native foundations, testing and bounded orchestration for Fenton
consumers. The root Swift package exposes independently linkable Apple products.
Portable `fenton-tooling` has its own version and operating profile. Experimental
Windows and Android libraries have separate native harnesses and dependencies.

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
consumer/production access. See [the documentation index](docs/README.md) for
implemented surfaces and the remaining qualification gates.

## Boundaries

`tooling/src/fenton_tooling` is deterministic and stdlib-only at runtime.
`.fenton` is this repo's profile; `contracts` are language-neutral schemas;
`agents` are reusable role/advisor descriptions; `.github` and `.claude` are
thin host descriptors. Operational state belongs outside git.

License: all rights reserved to SFenton. See `LICENSE`.
