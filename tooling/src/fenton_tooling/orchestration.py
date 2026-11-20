"""Small bounded task state machine and independent admission checks."""
import json
import os
from dataclasses import dataclass, field
from typing import List, Optional

from .evidence import atomic_write_json
from .model import validate_id, validate_sha


STATES = ("queued", "running", "verifying", "reviewing", "accepted", "rejected", "cancelled")


@dataclass
class Task:
    task_id: str
    source_sha: str
    base_sha: Optional[str] = None
    state: str = "queued"
    attempts: int = 0
    evidence: List[str] = field(default_factory=list)
    owner: Optional[str] = None

    def __post_init__(self):
        validate_id(self.task_id, "task id")
        validate_sha(self.source_sha)
        if self.base_sha is not None:
            validate_sha(self.base_sha)
        if self.state not in STATES:
            raise ValueError("invalid task state")

    def transition(self, target):
        allowed = {
            "queued": ("running", "cancelled"), "running": ("verifying", "cancelled"),
            "verifying": ("reviewing", "rejected", "cancelled"),
            "reviewing": ("accepted", "rejected", "cancelled"),
            "accepted": (), "rejected": (), "cancelled": ()
        }
        if target not in allowed.get(self.state, ()):
            raise ValueError("invalid task transition %s -> %s" % (self.state, target))
        self.state = target


def save_task(state_dir, task):
    validate_id(task.task_id, "task id")
    atomic_write_json(os.path.join(state_dir, "tasks", task.task_id + ".json"),
                      task.__dict__)


def load_task(state_dir, task_id):
    validate_id(task_id, "task id")
    with open(os.path.join(state_dir, "tasks", task_id + ".json"),
              "r", encoding="utf-8") as handle:
        payload = json.load(handle)
    if payload.get("task_id") != task_id:
        raise ValueError("task identity mismatch")
    return Task(**payload)


def admission_check(task, review, current_sha, changed_paths, policy):
    failures = []
    if policy.get("trusted_root_required") is not True:
        failures.append("untrusted policy")
    if task.source_sha != current_sha:
        failures.append("moved head")
    if review.get("reviewer") in (None, review.get("author")):
        failures.append("self-review")
    if not review.get("exact_sha") or review["exact_sha"] != task.source_sha:
        failures.append("review SHA mismatch")
    if not task.evidence:
        failures.append("missing evidence")
    if not review.get("tests_passed"):
        failures.append("missing tests")
    if review.get("independent") is not True:
        failures.append("missing independent review")
    if review.get("receipt_attested") is not True:
        failures.append("missing externally attested receipt")
    protected = set(policy.get("protected_paths", []))
    if any(any(p == x or p.startswith(x.rstrip("/") + "/") for x in protected)
           for p in changed_paths) and not review.get("protected_approval"):
        failures.append("protected change")
    return (not failures, failures)
