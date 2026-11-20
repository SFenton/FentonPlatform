"""Strict installed-host argument vectors for bounded role contracts."""
import os
import uuid
from dataclasses import dataclass

from .model import ContractError


ROLE_CONTRACTS = {
    "coordinator": ("read-only", ("view", "rg", "glob")),
    "implementer": ("proposal", ("view", "rg", "glob")),
    "reviewer": ("read-only", ("view", "rg", "glob")),
    "verifier": ("read-only", ("view", "rg", "glob")),
    "steward": ("proposal", ("view", "rg", "glob")),
}
ROLE_CONTRACT_TEXT = {
    name: "[registered-role:%s; authority:%s; tools:%s] " %
    (name, authority, ",".join(tools))
    for name, (authority, tools) in ROLE_CONTRACTS.items()
}
ALLOWED_PROVIDERS = {"copilot"}
ALLOWED_MODELS = {"gpt-5.6-luna", "gpt-5.6-terra"}


def _outside(path, root):
    return os.path.commonpath((os.path.abspath(path), os.path.abspath(root))) != os.path.abspath(root)


@dataclass(frozen=True)
class HostInvocation:
    provider: str
    model: str
    role: str
    authority: str
    argv: tuple
    cwd: str

    def to_dict(self):
        return {"provider": self.provider, "model": self.model, "role": self.role,
                "authority": self.authority, "argv": list(self.argv), "cwd": self.cwd}


def build_invocation(provider, model, role, prompt, *, trusted_cwd=None,
                     candidate_root=None, state_dir=None, reasoning_effort="medium",
                     context="default", usage_output_file=None,
                     available_tools=None):
    if provider not in ALLOWED_PROVIDERS:
        raise ContractError("unknown host provider")
    if model not in ALLOWED_MODELS:
        raise ContractError("unknown model")
    if role not in ROLE_CONTRACTS:
        raise ContractError("unregistered role contract")
    if reasoning_effort not in {"default", "low", "medium", "high"}:
        raise ContractError("unsupported reasoning effort")
    if context not in {"default", "long_context"}:
        raise ContractError("unsupported context tier")
    if not isinstance(prompt, str) or not prompt.strip() or "\x00" in prompt:
        raise ContractError("prompt is required")
    cwd = os.path.abspath(trusted_cwd or os.path.expanduser("~"))
    if candidate_root and not _outside(cwd, candidate_root):
        raise ContractError("trusted launch CWD must be outside candidate")
    if usage_output_file is None and state_dir:
        usage_output_file = os.path.join(os.path.abspath(state_dir), "host-usage.json")
    if usage_output_file is None:
        usage_output_file = os.path.join(os.path.expanduser("~"),
                                         ".fenton-runtime", "host-usage.json")
    if not usage_output_file or not os.path.isabs(usage_output_file):
        raise ContractError("external usage output path is required")
    if candidate_root and not _outside(usage_output_file, candidate_root):
        raise ContractError("usage output must be outside candidate")
    authority, tools = ROLE_CONTRACTS[role]
    if available_tools is not None and tuple(available_tools) != tools:
        raise ContractError("caller cannot expand registered role tools")
    usage_output_file = os.path.join(
        os.path.dirname(os.path.abspath(usage_output_file)),
        "host-usage-" + uuid.uuid4().hex + ".json")
    bound_prompt = ROLE_CONTRACT_TEXT[role] + prompt
    argv = (
        "copilot", "-p", bound_prompt, "--model", model, "--reasoning-effort",
        reasoning_effort, "--context", context, "--no-custom-instructions",
        "--disable-builtin-mcps", "--no-ask-user", "--available-tools", *tools,
        "--allow-tool", *tools,
        "--usage-output-file", os.path.abspath(usage_output_file),
    )
    return HostInvocation(provider, model, role, authority, argv, cwd)


def run_invocation(invocation, *, dry_run=True, timeout_seconds=900):
    if dry_run:
        return {"status": "dry-run", **invocation.to_dict(), "usage": "unreconciled"}
    raise ContractError(
        "live host launch is blocked until an external qualified grant and "
        "budget integration exists")
