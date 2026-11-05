"""Adapter for the one canonical host-wide ``devcap run`` bridge."""
import json
import os
import re
import shutil
import subprocess
from typing import Iterable, Optional, Tuple

from .model import ContractError, ResourceRequirement

_UDID = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")


def _configured_argv() -> Tuple[str, ...]:
    raw = os.environ.get("FENTON_DEVCAP_ARGV", "")
    if not raw:
        return ()
    try:
        value = json.loads(raw)
    except ValueError as exc:
        raise ContractError("FENTON_DEVCAP_ARGV must be a JSON argument vector") from exc
    if not isinstance(value, list) or any(not isinstance(item, str) or not item for item in value):
        raise ContractError("FENTON_DEVCAP_ARGV must contain non-empty strings")
    return tuple(value)


def devcap_executable() -> Optional[str]:
    executable = os.environ.get("FENTON_DEVCAP_EXECUTABLE") or shutil.which("devcap")
    if executable and os.sep in executable and not os.path.isabs(executable):
        raise ContractError("configured devcap executable must be absolute")
    return executable


def devcap_command(requirements: Iterable[ResourceRequirement], command,
                   purpose: str, hold_seconds: float, executable=None,
                   prefix: Iterable[str] = ()) -> Tuple[str, ...]:
    executable = executable or devcap_executable()
    if not executable:
        raise ContractError("required devcap bridge is unavailable")
    if not purpose or "\x00" in purpose or hold_seconds <= 0:
        raise ContractError("invalid devcap purpose or hold")
    args = [executable] + list(prefix or _configured_argv()) + ["run"]
    seen = set()
    for requirement in requirements:
        if requirement.quantity != 1:
            raise ContractError("devcap run does not support resource quantities")
        kind, sep, identifier = requirement.capability.partition(":")
        if not sep or not identifier:
            raise ContractError("resource must name a device or pool: " + requirement.capability)
        if kind in ("sim", "simulator"):
            if not _UDID.fullmatch(identifier):
                raise ContractError("simulator resource must be a UDID")
            flag = "--sim"
        elif kind == "device":
            if not _UDID.fullmatch(identifier):
                raise ContractError("device resource must be a UDID")
            flag = "--device"
        elif kind == "pool":
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", identifier):
                raise ContractError("invalid devcap pool")
            flag = "--pool"
        else:
            raise ContractError("unsupported devcap capability: " + requirement.capability)
        key = (flag, identifier)
        if key in seen:
            raise ContractError("duplicate devcap resource: " + requirement.capability)
        seen.add(key)
        args.extend((flag, identifier))
    args.extend(("--purpose", purpose, "--hold", str(float(hold_seconds)), "--"))
    args.extend(command)
    return tuple(args)


def devcap_status():
    executable = devcap_executable()
    if not executable:
        return {"available": False, "reason": "configured devcap executable not found"}
    try:
        completed = subprocess.run([executable] + list(_configured_argv()) + ["status"],
                                   text=True, capture_output=True, timeout=10)
        return {"available": completed.returncode == 0, "executable": executable,
                "output": completed.stdout.strip(), "reason": completed.stderr.strip()}
    except (OSError, subprocess.SubprocessError) as exc:
        return {"available": False, "executable": executable, "reason": str(exc)}
