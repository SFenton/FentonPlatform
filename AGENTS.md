# Agent entry point

Read `docs/README.md` and the canonical documents under `docs/` before changing
behavior. The trusted control plane must load policy outside a candidate
worktree; candidate tooling is never its own judge. Preserve exact-SHA evidence,
independent review, protected-path checks, cancellation cleanup, and the
no-production/no-cross-repo boundary.

Run `python -m unittest discover tooling/tests`, `python -m fenton_tooling
doctor`, `python -m fenton_tooling check`, and `node tools/check-docs.mjs` when
available. Do not add credentials, reports, logs, or generated state to git.
