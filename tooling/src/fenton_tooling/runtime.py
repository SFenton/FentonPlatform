"""Bounded, replayable repository orchestration.

This control-plane adapter keeps durable state outside a candidate repository.
It dispatches only explicitly registered DAG nodes and never applies changes.
"""
import argparse
try:
    import fcntl
except ImportError:  # Windows imports remain usable for dry-run/replay.
    fcntl = None
import json
import os
import subprocess
import time
import uuid
from dataclasses import dataclass

from .config import load_profile
from .execution import run_plan
from .model import ContractError, RunResult, validate_id, validate_sha
from .runners import plan_from_recipe
from .orchestration import load_task
from .trust import verify_external_runner


def _git(root, *args):
    return subprocess.check_output(("git", "-C", root) + args, text=True).strip()


def verify_source_root(root, source_sha):
    root = os.path.abspath(root)
    validate_sha(source_sha)
    if _git(root, "status", "--porcelain", "--untracked-files=all"):
        raise ContractError("source root is not clean")
    if _git(root, "rev-parse", "HEAD").lower() != source_sha.lower():
        raise ContractError("source SHA does not match HEAD")
    return source_sha


def _outside(path, root):
    return os.path.commonpath((os.path.abspath(path), os.path.abspath(root))) != os.path.abspath(root)


def _atomic_json(path, value):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    temporary = path + ".tmp-%s" % os.getpid()
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, sort_keys=True, indent=2)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


@dataclass(frozen=True)
class RegisteredJob:
    job_id: str
    recipe: str
    prerequisites: tuple = ()
    max_attempts: int = 1
    role: str = "implementer"
    authority: str = "read-only"

    def __post_init__(self):
        validate_id(self.job_id, "job id")
        validate_id(self.recipe, "recipe")
        if self.max_attempts < 1:
            raise ContractError("max attempts must be positive")
        if self.authority not in ("read-only", "proposal"):
            raise ContractError("unsupported job authority")
        for item in self.prerequisites:
            validate_id(item, "prerequisite")


def load_registered_jobs(trusted_root, path=None):
    """Load only the externally trusted job registry, never candidate config."""
    trusted_root = os.path.abspath(trusted_root)
    config_path = os.path.abspath(path or os.path.join(
        trusted_root, ".fenton", "runtime.json"))
    if os.path.commonpath((config_path, trusted_root)) != trusted_root:
        raise ContractError("runtime registry must be under trusted root")
    try:
        with open(config_path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError) as exc:
        raise ContractError("external runtime registry is unavailable: %s" % exc)
    if payload.get("schema_version") != "1" or not isinstance(payload.get("jobs"), list):
        raise ContractError("invalid external runtime registry")
    jobs = []
    for item in payload["jobs"]:
        if not isinstance(item, dict):
            raise ContractError("invalid registered job")
        allowed = {"job_id", "recipe", "prerequisites", "max_attempts",
                   "role", "authority"}
        if set(item) - allowed:
            raise ContractError("unregistered runtime job fields")
        jobs.append(RegisteredJob(
            item["job_id"], item["recipe"], tuple(item.get("prerequisites", ())),
            int(item.get("max_attempts", 1)), item.get("role", "implementer"),
            item.get("authority", "read-only")))
    if not jobs:
        raise ContractError("external runtime registry has no jobs")
    return tuple(jobs)


class BoundedRuntime:
    def __init__(self, repo_root, state_dir, profile=None, policy=None,
                 trusted_root=None):
        self.repo_root = os.path.abspath(repo_root)
        self.state_dir = os.path.abspath(state_dir)
        if not _outside(self.state_dir, self.repo_root):
            raise ContractError("runtime state must be outside candidate")
        if profile is None or policy is None:
            if not trusted_root:
                raise ContractError("external trusted profile and policy are required")
            trusted_root = os.path.abspath(trusted_root)
            if not _outside(trusted_root, self.repo_root):
                raise ContractError("trusted root must be outside candidate")
            profile, policy = load_profile(trusted_root)
        self.profile, self.policy = profile, policy
        self.trusted_root = os.path.abspath(trusted_root) if trusted_root else None
        os.makedirs(os.path.join(self.state_dir, "jobs"), exist_ok=True)
        self.lock_path = os.path.join(self.state_dir, "writer.lock")
        self.journal_path = os.path.join(self.state_dir, "journal.jsonl")
        self._lock_handle = None

    def _lock(self):
        if fcntl is None:
            raise ContractError("runtime execution requires POSIX file locking")
        handle = open(self.lock_path, "a+", encoding="utf-8")
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (BlockingIOError, OSError):
            handle.close()
            raise ContractError("another runtime writer owns state")
        self._lock_handle = handle

    def _unlock(self):
        if self._lock_handle is not None:
            fcntl.flock(self._lock_handle.fileno(), fcntl.LOCK_UN)
            self._lock_handle.close()
            self._lock_handle = None

    def _event(self, event, **fields):
        with open(self.journal_path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps({"event": event, "timestamp": time.time(), **fields},
                                    sort_keys=True) + "\n")
            handle.flush()
            os.fsync(handle.fileno())

    def _path(self, job_id):
        return os.path.join(self.state_dir, "jobs", validate_id(job_id, "job id") + ".json")

    def _save(self, record):
        _atomic_json(self._path(record["job_id"]), record)

    def _load(self, job_id):
        try:
            with open(self._path(job_id), encoding="utf-8") as handle:
                return json.load(handle)
        except FileNotFoundError:
            return None

    def reconcile_orphaned_active_jobs(self, resume=False):
        records = []
        for name in sorted(os.listdir(os.path.join(self.state_dir, "jobs"))):
            if not name.endswith(".json"):
                continue
            with open(os.path.join(self.state_dir, "jobs", name), encoding="utf-8") as handle:
                record = json.load(handle)
            if record.get("state") != "running":
                continue
            owner = int(record.get("owner_pid", 0))
            try:
                os.kill(owner, 0)
                alive = True
            except (OSError, ProcessLookupError):
                alive = False
            if not alive:
                record.update(state="orphaned", decision="rejected",
                              reason="orphaned active job; manual resume required")
                self._save(record)
                self._event("orphaned", job_id=record["job_id"], resume=bool(resume))
                records.append(record)
        return records

    def dispatch(self, jobs, source_sha, cancel_event=None, run_id=None, resume=False):
        verify_source_root(self.repo_root, source_sha)
        requested_run_id = run_id
        run_id = run_id or uuid.uuid4().hex
        self.last_run_id = run_id
        jobs = tuple(jobs)
        by_id = {job.job_id: job for job in jobs}
        if len(by_id) != len(jobs):
            raise ContractError("duplicate registered job")
        if any(dep not in by_id for job in jobs for dep in job.prerequisites):
            raise ContractError("job prerequisite is not registered")
        visiting, visited = set(), set()

        def visit(job_id):
            if job_id in visiting:
                raise ContractError("registered DAG contains a cycle")
            if job_id in visited:
                return
            visiting.add(job_id)
            for prerequisite in by_id[job_id].prerequisites:
                visit(prerequisite)
            visiting.remove(job_id)
            visited.add(job_id)

        for job_id in sorted(by_id):
            visit(job_id)
        self._lock()
        try:
            self.reconcile_orphaned_active_jobs(resume=resume)
            result = {}
            pending = set(by_id)
            existing_records = {job_id: self._load(job_id) for job_id in sorted(by_id)}
            persisted_run_ids = {
                record.get("run_id") for record in existing_records.values()
                if record and record.get("run_id")
            }
            if len(persisted_run_ids) > 1:
                raise ContractError("persisted jobs belong to mixed runs")
            persisted_run_id = next(iter(persisted_run_ids), None)
            if persisted_run_id:
                if requested_run_id and requested_run_id != persisted_run_id:
                    raise ContractError("resume run identity mismatch")
                run_id = persisted_run_id
            self.last_run_id = run_id
            for job_id in sorted(by_id):
                existing = existing_records[job_id]
                if not existing:
                    continue
                if existing.get("source_sha") != source_sha:
                    raise ContractError("persisted job SHA differs")
                if (existing.get("recipe") and existing.get("recipe") != by_id[job_id].recipe) or (
                        existing.get("prerequisites") and
                        tuple(existing["prerequisites"]) != by_id[job_id].prerequisites):
                    raise ContractError("persisted job definition differs")
                if existing.get("state") == "pending-review":
                    result[job_id] = existing
                elif existing.get("state") in ("accepted", "verifying",
                                                "rejected", "blocked", "cancelled",
                                                "timeout"):
                    result[job_id] = existing
                    pending.remove(job_id)
                elif existing.get("state") == "orphaned":
                    if not resume:
                        result[job_id] = existing
                        pending.remove(job_id)
                    else:
                        result[job_id] = existing
            while pending:
                blocked = sorted(job_id for job_id in pending if any(
                    dep in result and result[dep]["state"] in
                    ("rejected", "blocked", "cancelled", "timeout", "orphaned")
                    for dep in by_id[job_id].prerequisites))
                for job_id in blocked:
                    record = {"job_id": job_id, "state": "blocked",
                              "decision": "rejected", "reason": "prerequisite failed",
                              "source_sha": source_sha, "run_id": run_id}
                    self._save(record)
                    self._event("blocked", job_id=job_id)
                    result[job_id] = record
                    pending.remove(job_id)
                awaiting = sorted(job_id for job_id in pending if any(
                    dep in result and result[dep]["state"] in
                    ("verifying", "pending-review", "running")
                    for dep in by_id[job_id].prerequisites))
                for job_id in awaiting:
                    record = result.get(job_id) or self._load(job_id) or {
                        "job_id": job_id, "source_sha": source_sha,
                        "run_id": run_id, "attempts": 0,
                        "recipe": by_id[job_id].recipe,
                        "prerequisites": list(by_id[job_id].prerequisites),
                        "role": by_id[job_id].role,
                        "authority": by_id[job_id].authority,
                    }
                    record.update(state="pending-review", decision="pending",
                                  reason="prerequisite awaiting review",
                                  source_sha=source_sha, run_id=run_id)
                    self._save(record)
                    result[job_id] = record
                    pending.remove(job_id)
                ready = sorted(job_id for job_id in pending if all(
                    not by_id[job_id].prerequisites or
                    (dep in result and result[dep]["state"] == "accepted")
                    for dep in by_id[job_id].prerequisites))
                if not ready:
                    break
                for job_id in ready:
                    record = self._run(by_id[job_id], source_sha, cancel_event, run_id,
                                       self._load(job_id))
                    result[job_id] = record
                    pending.remove(job_id)
            return result
        finally:
            self._unlock()

    def _run(self, job, source_sha, cancel_event, run_id, existing=None):
        record = existing or {"job_id": job.job_id, "state": "running",
                              "source_sha": source_sha, "owner_pid": os.getpid(),
                              "attempts": 0, "authority": job.authority,
                              "run_id": run_id, "recipe": job.recipe,
                              "prerequisites": list(job.prerequisites),
                              "role": job.role}
        record.update(state="running", owner_pid=os.getpid(), run_id=run_id)
        self._save(record)
        self._event("started", job_id=job.job_id)
        last = None
        first_attempt = record.get("attempts", 0) + 1
        if first_attempt > job.max_attempts:
            record.update(state="rejected", decision="rejected",
                          reason="maximum attempts exhausted")
            self._save(record)
            self._event("rejected", job_id=job.job_id,
                        reason=record["reason"])
            return record
        for attempt in range(first_attempt, job.max_attempts + 1):
            record["attempts"] = attempt
            try:
                plan = plan_from_recipe(self.profile, job.recipe, self.repo_root, "change")
                last = run_plan(plan, cancel_event)
            except (ContractError, OSError, ValueError) as exc:
                last = RunResult("infra", reason=str(exc))
            if last.certifies_success:
                record.update(state="verifying", result=last.__dict__,
                              decision="pending-independent-review")
                self._save(record)
                self._event("verification-ready", job_id=job.job_id)
                return record
            if last.status in ("cancelled", "timeout"):
                break
        terminal_state = "cancelled" if last and last.status == "cancelled" else (
            "timeout" if last and last.status == "timeout" else "rejected")
        record.update(state=terminal_state, decision=terminal_state,
                      reason=last.reason if last else "no result",
                      result=last.__dict__ if last else None)
        self._save(record)
        self._event("rejected", job_id=job.job_id, reason=record["reason"])
        return record

    def accept(self, job_id, artifact_path):
        """Delegate review; consume only the external runner's accepted task."""
        if not self.trusted_root:
            raise ContractError("acceptance blocked: external trusted root is required")
        if not self.policy.get("trusted_reviewers"):
            raise ContractError("acceptance blocked: external reviewer allowlist is empty")
        artifact_path = os.path.abspath(artifact_path)
        if not _outside(artifact_path, self.repo_root):
            raise ContractError("review artifact must be outside candidate")
        record = self._load(job_id)
        if not record or record.get("state") != "verifying":
            raise ContractError("acceptance blocked: job is not verifying")
        source_sha = record.get("source_sha")
        verify_source_root(self.repo_root, source_sha)
        executable = verify_external_runner(self.trusted_root, self.repo_root)
        env = dict(os.environ)
        env.update(FENTON_TRUSTED_ROOT=self.trusted_root,
                   FENTON_TRUSTED_STATE=self.state_dir,
                   FENTON_TRUSTED_DELEGATED="1")
        completed = subprocess.run(
            [executable, "review", job_id, "--artifact", artifact_path],
            cwd=self.repo_root, env=env, check=False)
        verify_source_root(self.repo_root, source_sha)
        if completed.returncode != 0:
            raise ContractError("external review did not accept task")
        try:
            task = load_task(self.state_dir, job_id)
        except (OSError, ValueError) as exc:
            raise ContractError("external accepted task is unavailable: %s" % exc)
        if task.state != "accepted" or task.source_sha != source_sha:
            raise ContractError("external accepted task SHA/state mismatch")
        record.update(state="accepted", decision="accepted",
                      external_review=True, reviewer_task=job_id)
        self._save(record)
        self._event("accepted", job_id=job_id)
        return record


def replay(path):
    with open(path, encoding="utf-8") as handle:
        events = [json.loads(line) for line in handle if line.strip()]
    return {"events": events, "event_count": len(events)}


def _main(argv=None):
    parser = argparse.ArgumentParser(prog="python -m fenton_tooling.runtime")
    sub = parser.add_subparsers(dest="command", required=True)
    dry = sub.add_parser("dry-run")
    dry.add_argument("--provider", default="copilot")
    dry.add_argument("--model", default="gpt-5.6-luna")
    dry.add_argument("--role", default="coordinator")
    dry.add_argument("--prompt", required=True)
    replay_parser = sub.add_parser("replay")
    replay_parser.add_argument("journal")
    dispatch = sub.add_parser("dispatch")
    dispatch.add_argument("--repo-root", required=True)
    dispatch.add_argument("--trusted-root", required=True)
    dispatch.add_argument("--state-dir", required=True)
    dispatch.add_argument("--source-sha", required=True)
    dispatch.add_argument("--run-id")
    dispatch.add_argument("--resume", action="store_true")
    dispatch.add_argument("--registry")
    args = parser.parse_args(argv)
    if args.command == "replay":
        print(json.dumps(replay(args.journal), sort_keys=True))
        return 0
    if args.command == "dispatch":
        try:
            trusted_root = os.path.abspath(args.trusted_root)
            jobs = load_registered_jobs(trusted_root, args.registry)
            runtime = BoundedRuntime(
                args.repo_root, args.state_dir, trusted_root=trusted_root)
            result = runtime.dispatch(jobs, args.source_sha, run_id=args.run_id,
                                      resume=args.resume)
            print(json.dumps({"run_id": runtime.last_run_id,
                              "jobs": result}, sort_keys=True))
            return 0 if all(item.get("state") not in
                            ("rejected", "blocked", "cancelled", "orphaned")
                            for item in result.values()) else 1
        except (ContractError, OSError, ValueError, subprocess.SubprocessError) as exc:
            print(json.dumps({"dispatch": "blocked", "reason": str(exc)},
                             sort_keys=True))
            return 2
    from .hosts import build_invocation
    print(json.dumps(build_invocation(args.provider, args.model, args.role,
                                      args.prompt).to_dict(), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
