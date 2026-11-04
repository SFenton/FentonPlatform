# Agents and trust

Roles and four read-only advisors are reusable contracts. The trusted runner,
policy and evaluator are outside a candidate worktree. This repo does not claim
same-user sandboxing or autonomous merge. Review admission requires exact SHA,
independent reviewer, executed tests and protected-path approval.

The role and source-execution assets currently describe boundaries and invoke
deterministic helpers; they do not constitute a continuously running
orchestration daemon.

Candidate-supplied booleans, changed-path lists, source SHAs, and arbitrary
evidence strings are not trusted review inputs. Protected approval comes only
from the external policy's reviewer allowlist.

Decision calls are disabled; normalization supports replay and abstention only.
Learning is proposal/shadow-only and automatic promotion is disabled.
