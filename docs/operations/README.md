# Operations

State is local, per repository, atomic JSON outside git (for example
`.fenton-state/`). Reports and logs are not committed. The trusted runner owns
policy loading and admission. No database server, provider secret handling,
cross-repository access, production access, or automatic promotion is included.
