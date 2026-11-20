"""Typed contracts used by the portable runner."""
import dataclasses
import os
import re
from typing import Dict, List, Optional, Tuple


class ContractError(ValueError):
    pass


def validate_id(value, label="id"):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", value):
        raise ContractError("invalid " + label)
    return value


def validate_sha(value):
    if not isinstance(value, str) or not re.fullmatch(r"[0-9a-fA-F]{7,64}", value):
        raise ContractError("invalid source SHA")
    return value.lower()


@dataclasses.dataclass(frozen=True)
class ResourceRequirement:
    capability: str
    quantity: int = 1
    exclusive: bool = True

    def __post_init__(self):
        if not isinstance(self.capability, str) or not re.fullmatch(
                r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}", self.capability):
            raise ContractError("invalid resource capability")
        if self.quantity < 1:
            raise ContractError("resource quantity must be positive")


def _validate_argv(argv):
    if not isinstance(argv, (tuple, list)) or not argv or any(
            not isinstance(item, str) or not item or "\x00" in item for item in argv):
        raise ContractError("command must be a non-empty argument vector")
    return tuple(argv)


@dataclasses.dataclass(frozen=True)
class TestPlan:
    component: str
    selectors: Tuple[str, ...]
    tier: str
    platform: str
    command: Tuple[str, ...]
    fixture: str
    build_identity: str
    cwd: str = "."
    timeout_seconds: float = 300.0
    required: bool = True
    resources: Tuple[ResourceRequirement, ...] = ()
    repo_root: Optional[str] = None

    def __post_init__(self):
        validate_id(self.component, "component")
        if not self.selectors or any(not isinstance(x, str) or not x for x in self.selectors):
            raise ContractError("component and selectors are required")
        if self.tier not in ("edit", "change", "merge", "nightly", "release"):
            raise ContractError("unknown test tier")
        if not self.platform:
            raise ContractError("platform and argv command are required")
        _validate_argv(self.command)
        if self.repo_root is not None:
            if not isinstance(self.repo_root, str) or not os.path.isabs(self.repo_root):
                raise ContractError("repo root must be absolute")
            root = os.path.realpath(self.repo_root)
            cwd = os.path.realpath(self.cwd)
            if os.path.commonpath((cwd, root)) != root:
                raise ContractError("working directory escapes repository root")
        if any(not isinstance(item, ResourceRequirement) for item in self.resources):
            raise ContractError("invalid resource requirement")
        if self.timeout_seconds <= 0:
            raise ContractError("timeout must be positive")


@dataclasses.dataclass
class RunResult:
    status: str
    executed: int = 0
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    exit_code: Optional[int] = None
    reason: str = ""
    stdout: str = ""
    stderr: str = ""
    artifacts: List[str] = dataclasses.field(default_factory=list)
    retry_count: int = 0

    def __post_init__(self):
        allowed = {"passed", "failed", "skipped", "empty", "timeout",
                   "cancelled", "infra", "cached"}
        if self.status not in allowed:
            raise ContractError("invalid run status")
        if min(self.executed, self.passed, self.failed, self.skipped) < 0:
            raise ContractError("negative run count")
        if self.executed != self.passed + self.failed + self.skipped:
            raise ContractError("run counts must total executed tests")

    @property
    def certifies_success(self):
        return (self.status == "passed" and self.exit_code == 0 and
                self.executed > 0 and self.passed > 0 and
                self.failed == 0 and self.skipped < self.executed and
                not self.reason)


@dataclasses.dataclass(frozen=True)
class Evidence:
    run_id: str
    source_sha: str
    tree_fingerprint: str
    tooling_version: str
    schema_version: str
    policy_version: str
    selection: Tuple[str, ...]
    fixture_generation: str
    configuration: str
    artifact_digests: Dict[str, str]
    result: RunResult
    attestation: Optional[str] = None

    def __post_init__(self):
        validate_id(self.run_id, "run id")
        validate_sha(self.source_sha)
        if not self.tooling_version:
            raise ContractError("evidence identity is incomplete")
        if not self.selection or not self.fixture_generation:
            raise ContractError("evidence selection and fixture are required")


def as_dict(value):
    if dataclasses.is_dataclass(value):
        return {k: as_dict(v) for k, v in dataclasses.asdict(value).items()}
    if isinstance(value, tuple):
        return list(value)
    if isinstance(value, list):
        return [as_dict(x) for x in value]
    if isinstance(value, dict):
        return {k: as_dict(v) for k, v in value.items()}
    return value
