"""Replayable, abstaining decision normalization; transports are injectable."""
import hashlib
from dataclasses import dataclass
from typing import Any, Callable, Optional


@dataclass(frozen=True)
class DecisionQuestion:
    question_id: str
    version: str
    answer_type: str = "yes_no"
    namespace: str = "disabled"


@dataclass(frozen=True)
class Decision:
    answer: str
    confidence: float
    question_id: str
    version: str
    source: str


def normalize(question: DecisionQuestion, raw: Any, source="replay",
              low=0.35, high=0.65) -> Decision:
    if isinstance(raw, dict):
        answer = str(raw.get("answer", "abstain")).lower()
        confidence = float(raw.get("confidence", 0.0))
    else:
        answer, confidence = str(raw).lower(), 1.0
    if answer not in ("yes", "no"):
        answer = "abstain"
    if confidence < low or (answer == "abstain" and confidence < high):
        answer = "abstain"
    return Decision(answer, max(0.0, min(1.0, confidence)),
                    question.question_id, question.version, source)


def replay(question, payload, transport: Optional[Callable] = None):
    if transport is None:
        return normalize(question, payload, "replay")
    try:
        return normalize(question, transport(question, payload), question.namespace)
    except (OSError, KeyError, RuntimeError, ValueError):
        return Decision("abstain", 0.0, question.question_id, question.version,
                        "unavailable")


def cache_key(question, payload):
    encoded = repr((question.question_id, question.version, question.namespace,
                    payload)).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()
