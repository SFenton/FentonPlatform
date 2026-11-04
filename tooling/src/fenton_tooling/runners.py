"""Small native-runner adapters producing TestPlan argv without shell text."""
from .model import TestPlan


def plan_for(kind, selectors, component, cwd=".", fixture="synthetic-v1",
             build_identity="local", tier="change", timeout_seconds=900):
    selectors = tuple(selectors)
    if not selectors:
        raise ValueError("at least one exact selector is required")
    if kind == "unittest":
        command = ("python", "-m", "unittest") + selectors
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
                    build_identity, cwd=cwd, timeout_seconds=timeout_seconds)
