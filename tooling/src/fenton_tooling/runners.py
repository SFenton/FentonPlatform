"""Native runner plans and trusted recipe construction."""
import os
import sys
from .model import ResourceRequirement, TestPlan, validate_id


def plan_for(kind, selectors, component, cwd=".", fixture="synthetic-v1",
             build_identity="local", tier="change", timeout_seconds=900,
             resources=(), repo_root=None):
    selectors = tuple(selectors)
    if not selectors:
        raise ValueError("at least one exact selector is required")
    if kind == "unittest":
        command = (sys.executable, "-m", "unittest") + selectors
    elif kind == "swiftpm":
        # SwiftPM accepts one regular-expression filter; quote-free grouping
        # keeps the argv safe while retaining every requested selector.
        expression = selectors[0] if len(selectors) == 1 else "(?:" + "|".join(selectors) + ")"
        command = ("swift", "test", "--filter", expression)
    elif kind == "xcode":
        command = ("xcodebuild", "test", "-scheme", component) + tuple(
            "-only-testing:%s/%s" % (component, selector) for selector in selectors)
    elif kind == "dotnet":
        if len(selectors) != 1:
            raise ValueError("dotnet adapter requires one exact filter expression")
        command = ("dotnet", "test", "--no-restore", "--filter",
                   "FullyQualifiedName=" + selectors[0])
    elif kind == "web":
        command = ("yarn", "test:unit", "--run", "--testNamePattern",
                   "(?:" + "|".join(selectors) + ")")
    elif kind == "gradle":
        command = ("./gradlew", "test") + tuple(
            item for selector in selectors for item in ("--tests", selector))
    else:
        raise ValueError("unsupported runner: " + kind)
    return TestPlan(component, selectors, tier, kind, command, fixture,
                    build_identity, cwd=cwd, timeout_seconds=timeout_seconds,
                    resources=tuple(resources), repo_root=repo_root)


def plan_from_recipe(profile, name, repo_root, tier=None):
    validate_id(name, "recipe")
    if not os.path.isabs(repo_root):
        raise ValueError("repository root must be absolute")
    recipe = profile.get("recipes", {}).get(name)
    if not isinstance(recipe, dict):
        raise ValueError("unknown registered recipe: " + name)
    selectors = tuple(recipe.get("selectors", ()))
    argv = recipe.get("argv")
    if not selectors or not isinstance(argv, list) or not argv or any(
            not isinstance(item, str) or not item for item in argv):
        raise ValueError("recipe requires selectors and an argument vector")
    root = os.path.realpath(repo_root)
    cwd = os.path.realpath(os.path.join(root, recipe.get("cwd", ".")))
    if os.path.commonpath((cwd, root)) != root:
        raise ValueError("recipe working directory escapes repository root")
    command = tuple(item.replace("{repo_root}", root) for item in argv)
    resources = tuple(ResourceRequirement(item["capability"], item.get("quantity", 1),
                                          item.get("exclusive", True))
                      for item in recipe.get("resources", ()))
    return TestPlan(recipe.get("component", "portable-testing"), selectors,
                    tier or recipe.get("tier", "change"),
                    recipe.get("platform", "portable"), command,
                    recipe.get("fixture", "profile-v1"),
                    recipe.get("build_identity", "local"), cwd=cwd,
                    timeout_seconds=float(recipe.get("timeout_seconds", 900)),
                    resources=resources, repo_root=root)
