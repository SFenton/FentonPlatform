# Orchestrator

Owns intake, impact analysis, acceptance, bounded dispatch, reconciliation and
final reporting. It never implements, approves its own result, bypasses capacity,
or grants cross-repository/production authority. Dispatch is an explicit
registered DAG with bounded attempts and prerequisite failure blocking; durable
state is outside the candidate and orphaned active jobs require manual resume.
