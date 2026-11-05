"""Trusted selection and conservative native result normalization."""
import re
from .config import select_components
from .model import ContractError
from .runners import plan_from_recipe


def plans_for_changed_paths(profile, changed_paths, repo_root, tier="change"):
    components = select_components(profile, changed_paths)
    recipes = profile.get("recipes", {})
    covered = {recipe.get("component") for recipe in recipes.values()}
    missing = sorted(set(components) - covered)
    if missing:
        raise ContractError("no registered recipes for selected components: " +
                            ", ".join(missing))
    return tuple(plan_from_recipe(profile, name, repo_root, tier)
                 for name, recipe in recipes.items()
                 if recipe.get("component") in components)


def _number(pattern, text):
    match = re.search(pattern, text, re.I | re.M)
    return int(match.group(1)) if match else None


def parse_native_summary(text, exit_code=0):
    cases = re.findall(r"Test Case\s+['\"]([^'\"]+)['\"]\s+(passed|failed|skipped)",
                       text, re.I)
    outcomes = {}
    priority = {"passed": 0, "skipped": 1, "failed": 2}
    for identifier, outcome in cases:
        outcome = outcome.lower()
        previous = outcomes.get(identifier, "passed")
        outcomes[identifier] = max((previous, outcome), key=priority.get)
    case_failed = sum(outcome == "failed" for outcome in outcomes.values())
    case_skipped = sum(outcome == "skipped" for outcome in outcomes.values())
    xctest = [(int(a), int(b)) for a, b in re.findall(
        r"Executed\s+(\d+)\s+tests?,\s+with\s+(\d+)\s+failure", text, re.I)]
    executed = max(len(outcomes), max((a for a, _ in xctest), default=0))
    failed = max(case_failed, max((b for _, b in xctest), default=0))
    swift = [int(x) for x in re.findall(
        r"(?:Test run|Test session).*?(\d+)\s+tests?\s+passed", text, re.I)]
    executed = max(executed, max(swift, default=0))
    unqualified = False
    skipped = case_skipped
    passed = 0
    if not executed:
        ran = _number(r"Ran\s+(\d+)\s+tests?\b", text)
        if ran is not None:
            executed = ran
            failed = max(failed, _number(r"failures?\s*=\s*(\d+)", text) or 0)
            failed += _number(r"errors?\s*=\s*(\d+)", text) or 0
    if not executed:
        tap = re.search(r"^\s*#\s*tests\s+(\d+)\s*$.*?"
                        r"^\s*#\s*pass\s+(\d+)\s*$.*?"
                        r"^\s*#\s*fail\s+(\d+)\s*$.*?"
                        r"^\s*#\s*skipped\s+(\d+)\s*$", text, re.I | re.M | re.S)
        if tap:
            executed, passed, failed, skipped = map(int, tap.groups())
            status = "failed" if failed or exit_code else (
                "skipped" if skipped == executed else "passed")
            return status, executed, passed, failed, skipped
    if not executed:
        dotnet = re.search(r"(?:Passed!|Failed!).*?Failed:\s*(\d+),\s*Passed:\s*(\d+),"
                           r"\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)", text, re.I)
        if dotnet:
            failed, passed, skipped, executed = map(int, dotnet.groups())
        else:
            vitest = re.search(r"^\s*Tests?\s+(.+)$", text, re.I | re.M)
            if vitest:
                line = vitest.group(1)
                passed = _number(r"(\d+)\s+passed", line) or 0
                failed = _number(r"(\d+)\s+failed", line) or 0
                skipped = _number(r"(\d+)\s+(?:skipped|todo)", line) or 0
                executed = passed + failed + skipped
            else:
                gradle = re.search(r"(\d+)\s+tests?\s+completed,\s*(\d+)\s+failed"
                                   r"(?:,\s*(\d+)\s+skipped)?", text, re.I)
                if gradle:
                    executed, failed, skipped = int(gradle.group(1)), int(gradle.group(2)), int(gradle.group(3) or 0)
                    unqualified = True
    if not executed:
        return ("failed" if exit_code else "empty"), 0, 0, 0, 0
    skipped = max(skipped, _number(r"skipped\s*[:=]\s*(\d+)", text) or 0)
    if not passed:
        passed = max(0, executed - failed - skipped)
    status = "infra" if unqualified else (
        "failed" if failed or exit_code else ("skipped" if skipped == executed else "passed"))
    return status, executed, passed, failed, skipped
