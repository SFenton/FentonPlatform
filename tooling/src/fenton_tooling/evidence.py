"""Atomic, per-repository evidence state."""
import hashlib
import json
import os
import tempfile
from .model import ContractError, Evidence, as_dict, validate_id
from .trust import attest, verify_attestation


def digest_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def atomic_write_json(path, value):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".state-", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, sort_keys=True, indent=2)
            handle.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def exclusive_write_json(path, value):
    """Publish once without allowing a concurrent writer to replace it."""
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".state-", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(value, handle, sort_keys=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        try:
            os.link(temp, path)
        except FileExistsError:
            raise ContractError("evidence run identity already exists")
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def write_evidence(state_dir, evidence: Evidence):
    safe = validate_id(evidence.run_id, "run id")
    path = os.path.join(state_dir, "evidence", safe + ".json")
    payload = as_dict(evidence)
    key_path = os.environ.get("FENTON_ATTESTATION_KEY")
    if key_path:
        payload["attestation"] = attest({k: v for k, v in payload.items()
                                         if k != "attestation"}, key_path)
    exclusive_write_json(path, payload)
    return path


def verify_receipt(payload, key_path):
    signature = payload.get("attestation")
    body = {k: v for k, v in payload.items() if k != "attestation"}
    verify_attestation(body, signature, key_path)
