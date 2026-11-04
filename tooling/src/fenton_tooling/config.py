"""Trusted profile loading and deterministic component selection."""
import json
import os
from typing import Any, Dict, Iterable, List, Set

from .model import ContractError


def load_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_profile(root):
    root = os.path.abspath(root)
    profile = load_json(os.path.join(root, ".fenton", "repo.json"))
    policy = load_json(os.path.join(root, ".fenton", "policy.json"))
    if profile.get("schema_version") != "1":
        raise ContractError("unsupported repository profile")
    return profile, policy


def _matches(path, pattern):
    from fnmatch import fnmatch
    return fnmatch(path, pattern) or fnmatch(path, pattern.lstrip("./"))


def select_components(profile: Dict[str, Any], changed_paths: Iterable[str]) -> List[str]:
    components = profile.get("components", {})
    paths = [p.replace("\\", "/").lstrip("./") for p in changed_paths]
    selected: Set[str] = set()
    unknown = []
    for path in paths:
        matches = [name for name, cfg in components.items()
                   if any(_matches(path, pat) for pat in cfg.get("paths", []))]
        if not matches:
            unknown.append(path)
        selected.update(matches)
    if unknown:
        raise ContractError("unmapped changed paths: " + ", ".join(sorted(unknown)))
    queue = sorted(selected)
    while queue:
        name = queue.pop(0)
        dependencies = profile.get("dependencies", {})
        for dependent, cfg in sorted(components.items()):
            declared = cfg.get("depends_on", dependencies.get(dependent, []))
            if name in declared and dependent not in selected:
                selected.add(dependent)
                queue.append(dependent)
    return sorted(selected)


def selectors_for(profile, components):
    result = []
    for name in sorted(components):
        cfg = profile["components"][name]
        result.extend(cfg.get("selectors", []))
    return sorted(set(result))


def validate_selection(profile, changed_paths, selected_components):
    """Reject candidate-supplied selector suppression."""
    expected = select_components(profile, changed_paths)
    if sorted(selected_components) != expected:
        raise ContractError("selection differs from trusted component map")
    return selectors_for(profile, expected)
