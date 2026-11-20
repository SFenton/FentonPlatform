"""External trust-boundary helpers for admission and receipt attestation."""
import hashlib
import hmac
import json
import os
import sys

from .model import ContractError
from . import __version__


def _outside(path, candidate):
    return os.path.commonpath((os.path.abspath(path), os.path.abspath(candidate))) != os.path.abspath(candidate)


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def package_digest(package_root):
    digest = hashlib.sha256()
    for directory, _, files in os.walk(package_root):
        for name in sorted(files):
            if not name.endswith(".py"):
                continue
            path = os.path.join(directory, name)
            digest.update(os.path.relpath(path, package_root).encode("utf-8"))
            with open(path, "rb") as handle:
                digest.update(handle.read())
    return digest.hexdigest()


def verify_external_runner(trusted_root, candidate, require_current=False):
    manifest_path = os.path.join(trusted_root, "runner.json")
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
        if manifest.get("distribution") != "fenton-tooling" or not manifest.get("version"):
            raise ContractError("trusted runner manifest identity is incomplete")
    executable = os.path.realpath(manifest.get("executable", ""))
    package_root = os.path.realpath(manifest.get("package_root", ""))
    if (not executable or not package_root or
            not _outside(executable, candidate) or
            not _outside(package_root, candidate)):
        raise ContractError("trusted runner is not external")
    if not os.path.isfile(executable) or not os.path.isdir(package_root):
        raise ContractError("trusted runner distribution is unavailable")
    if manifest.get("package_digest") != package_digest(package_root):
        raise ContractError("trusted runner distribution digest mismatch")
    if require_current and manifest.get("version") != __version__:
        raise ContractError("trusted runner version mismatch")
    if require_current and not os.path.realpath(sys.modules[__package__].__file__).startswith(package_root + os.sep):
        raise ContractError("admission is executing candidate-local tooling")
    return executable


def attest(value, key_path):
    if not key_path or not os.path.isabs(key_path):
        raise ContractError("external attestation key is required")
    with open(key_path, "rb") as handle:
        key = handle.read()
    if not key:
        raise ContractError("attestation key is unavailable")
    return hmac.new(key, canonical_json(value), hashlib.sha256).hexdigest()


def verify_attestation(value, signature, key_path):
    expected = attest(value, key_path)
    if not signature or not hmac.compare_digest(expected, signature):
        raise ContractError("receipt attestation mismatch")
