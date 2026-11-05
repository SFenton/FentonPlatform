import os
import shutil
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from fenton_tooling.model import ResourceRequirement, RunResult
from fenton_tooling.runners import plan_for, plan_from_recipe
from fenton_tooling.capacity import devcap_command
from fenton_tooling.execution import isolated_helper_command
from fenton_tooling.testing import parse_native_summary, plans_for_changed_paths


class TestingControlTests(unittest.TestCase):
    def test_unittest_uses_current_interpreter(self):
        self.assertEqual(sys.executable, plan_for("unittest", ("x",), "c").command[0])

    def test_canonical_devcap_argv_and_validation(self):
        argv = devcap_command((ResourceRequirement("pool:build"),), ("echo", "x"),
                              "build", 30, executable="/opt/devcap")
        self.assertEqual(("/opt/devcap", "run", "--pool", "build",
                          "--purpose", "build", "--hold", "30.0", "--", "echo", "x"),
                         argv)
        with self.assertRaises(ValueError):
            devcap_command((ResourceRequirement("device"),), ("echo",), "x", 1,
                           executable="/opt/devcap")

    def test_mixed_xctest_deduplicates_and_swift_zero_does_not_hide(self):
        text = "".join("Test Case '-[Hosted.Case%d]' passed\n" % i for i in range(8))
        text += "".join("Test Case '-[UI.Case%d]' passed\n" % i for i in range(3))
        text += text + "Executed 11 tests, with 0 failures\nTest run with 0 tests passed\n"
        self.assertEqual(("passed", 11, 11, 0, 0), parse_native_summary(text))

    def test_repeated_xctest_failures_and_skips_have_consistent_counts(self):
        text = ("Test Case '-[Hosted.failure]' failed\n"
                "Test Case '-[Hosted.skip]' skipped\n") * 2
        counts = parse_native_summary(text, 1)
        self.assertEqual(("failed", 2, 0, 1, 1), counts)
        self.assertFalse(RunResult(*counts, exit_code=1).certifies_success)
        self.assertEqual(("failed", 1, 0, 1, 0), parse_native_summary(
            "Test Case '-[Hosted.retry]' failed\n"
            "Test Case '-[Hosted.retry]' passed\n"))

    def test_changed_component_without_recipe_fails_closed(self):
        profile = {"components": {
            "native": {"paths": ["src/**"], "selectors": ["native-tests"]}
        }, "dependencies": {}, "recipes": {}}
        with self.assertRaisesRegex(ValueError, "no registered recipes.*native"):
            plans_for_changed_paths(profile, ["src/page.swift"], os.getcwd())

    def test_tap_nonzero_and_gradle_unqualified(self):
        tap = "1..1\n# tests 1\n# pass 1\n# fail 0\n# skipped 0"
        self.assertEqual("failed", parse_native_summary(tap, 1)[0])
        self.assertEqual("infra", parse_native_summary(
            "3 tests completed, 0 failed, 1 skipped")[0])

    def test_recipe_symlink_cwd_is_rejected(self):
        root = os.path.realpath(os.path.dirname(__file__))
        profile = {"recipes": {"x": {"component": "portable", "selectors": ["x"],
                                     "argv": ["echo", "x"], "cwd": ".."}}}
        # A lexical parent is outside the test root and must remain rejected.
        with self.assertRaises(ValueError):
            plan_from_recipe(profile, "x", root)

    def test_isolated_helper_cannot_be_shadowed_by_cwd_package(self):
        shadow = os.path.join(os.path.dirname(__file__), "_shadow")
        os.makedirs(os.path.join(shadow, "fenton_tooling"), exist_ok=True)
        try:
            with open(os.path.join(shadow, "fenton_tooling", "execution.py"), "w") as handle:
                handle.write("raise SystemExit(99)\n")
            command = isolated_helper_command(
                (sys.executable, "-c", "print('Ran 1 test\\n\\nOK')"), shadow)
            result = subprocess.run(command, cwd=shadow, capture_output=True, text=True)
            self.assertEqual(0, result.returncode)
            self.assertIn("Ran 1 test", result.stdout)
        finally:
            shutil.rmtree(shadow, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
