"""Allowlisted, shadow-only friction learning and abstaining decisions."""
import hashlib
import json
from dataclasses import dataclass

from .decisions import Decision, DecisionQuestion, normalize
from .model import ContractError

ALLOWED_METADATA = {"component", "role", "task_kind", "outcome",
                    "duration_bucket", "retry_count", "selector_count"}
PROVIDERS = {"jev", "openrouter"}
ENUMS = {
    "role": {"coordinator", "implementer", "reviewer", "verifier", "steward"},
    "task_kind": {"implementation", "verification", "review", "proposal"},
    "outcome": {"passed", "failed", "blocked", "cancelled", "abstained"},
    "duration_bucket": {"short", "medium", "long"},
}


def metadata_allowlist(metadata):
    if not isinstance(metadata, dict):
        raise ContractError("learning metadata must be an object")
    if set(metadata) - ALLOWED_METADATA:
        raise ContractError("learning metadata contains disallowed fields")
    clean = {}
    for key in sorted(metadata):
        value = metadata[key]
        if key in ENUMS:
            if value not in ENUMS[key]:
                raise ContractError("learning metadata value is not registered")
        elif key in ("retry_count", "selector_count"):
            if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value <= 1000:
                raise ContractError("learning metadata count is out of bounds")
        elif key == "component":
            if not isinstance(value, str) or not value or len(value) > 80:
                raise ContractError("learning component is invalid")
        clean[key] = value
    return clean


def friction_digest(metadata):
    value = json.dumps(metadata_allowlist(metadata), sort_keys=True,
                       separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(value).hexdigest()


@dataclass(frozen=True)
class Proposal:
    digest: str
    action: str
    proving_test: str
    synthetic: bool = True


def propose(metadata, actions):
    if not isinstance(actions, (list, tuple)):
        raise ContractError("proposal actions must be a list")
    digest = friction_digest(metadata)
    result = []
    for action in actions[:3]:
        if not isinstance(action, dict) or not action.get("action") or not action.get("proving_test"):
            raise ContractError("proposal requires action and proving test")
        result.append(Proposal(digest, action["action"], action["proving_test"]))
    return tuple(result)


def synthetic_test(proposal):
    if not isinstance(proposal, Proposal) or not proposal.synthetic:
        raise ContractError("only synthetic proposals can be tested")
    return {"digest": proposal.digest, "action": proposal.action,
            "proving_test": proposal.proving_test, "status": "untested",
            "applied": False}


def question(question_id, version="1"):
    return DecisionQuestion(question_id, version, namespace="shadow-replay")


def replay_decision(question_contract, payload, provider="replay", grant=False,
                    budget=0, transport=None):
    if provider not in PROVIDERS and provider != "replay":
        raise ContractError("unknown decision provider")
    if provider in PROVIDERS:
        return Decision("abstain", 0.0, question_contract.question_id,
                        question_contract.version, "disabled")
    return normalize(question_contract, payload, "replay")


def cache_namespace(provider):
    if provider not in PROVIDERS:
        raise ContractError("unknown decision provider")
    return provider + "-calibration-cache"
