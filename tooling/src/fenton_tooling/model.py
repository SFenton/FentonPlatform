"""Typed contracts used by the portable runner."""
import dataclasses
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

    def __post_init__(self):
        if not self.component or not self.selectors or any(not x for x in self.selectors):
            raise ContractError("component and selectors are required")
        if self.tier not in ("edit", "change", "merge", "nightly", "release"):
            raise ContractError("unknown test tier")
        if not self.platform or not self.command or any(not x for x in self.command):
            raise ContractError("platform and argv command are required")
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
                self.failed == 0 and self.skipped < self.executed)


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
