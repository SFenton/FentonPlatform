import os
import json
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from fenton_tooling.config import select_components, validate_selection
from fenton_tooling.decisions import DecisionQuestion, normalize, replay
from fenton_tooling.execution import run_plan
from fenton_tooling.model import ContractError, Evidence, RunResult, TestPlan
from fenton_tooling.evidence import write_evidence
from fenton_tooling.cli import _digest
from fenton_tooling.orchestration import Task, admission_check
from fenton_tooling.runners import plan_for


class ToolingTests(unittest.TestCase):
    def test_selection_is_deterministic_and_includes_dependents(self):
        profile = {"components": {
            "base": {"paths": ["src/**"]},
            "consumer": {"paths": ["app/**"], "depends_on": ["base"]}}}
        self.assertEqual(["base", "consumer"], select_components(profile, ["src/a"]))

    def test_unknown_path_is_rejected(self):
        with self.assertRaises(ValueError):
            select_components({"components": {}}, ["secret.txt"])

    def test_dropped_selectors_are_rejected(self):
        profile = {"components": {"base": {"paths": ["src/**"], "selectors": ["base"]}}}
        with self.assertRaises(ValueError):
            validate_selection(profile, ["src/a"], [])

    def test_empty_and_all_skipped_do_not_certify(self):
        empty = run_plan(TestPlan("x", ("x",), "edit", "portable",
                                  (sys.executable, "-c", "pass"), "f", "b"))
        self.assertFalse(empty.certifies_success)
        skipped = run_plan(TestPlan("x", ("x",), "edit", "portable",
                                    (sys.executable, "-c", "print('skipped')"), "f", "b"))
        self.assertFalse(skipped.certifies_success)

    def test_certification_requires_successful_exit_and_positive_passes(self):
        self.assertFalse(RunResult("passed", executed=1, passed=1,
                                   exit_code=1).certifies_success)
        self.assertFalse(RunResult("passed", executed=1, passed=1,
                                   exit_code=None).certifies_success)
        self.assertFalse(RunResult("passed", executed=1, passed=0, skipped=1,
                                   exit_code=0).certifies_success)

    def test_inconsistent_run_totals_are_rejected(self):
        with self.assertRaises(ContractError):
            RunResult("passed", executed=2, passed=1, exit_code=0)

    def test_real_runner_summaries_and_large_output_are_parsed(self):
        cases = [
            ("Ran 2 tests in 0.01s\n\nOK", "passed", 2),
            ("Ran 2 tests in 0.01s\n\nFAILED (failures=1)", "failed", 2),
            ("Passed! - Failed: 0, Passed: 2, Skipped: 1, Total: 3", "passed", 3),
            ("Tests  2 passed | 1 skipped", "passed", 3),
            ("3 tests completed, 0 failed, 1 skipped", "passed", 3),
            ("TAP version 13\n1..3\n# tests 3\n# pass 3\n# fail 0\n# skipped 0", "passed", 3),
        ]
        for output, status, count in cases:
            plan = TestPlan("x", ("x",), "edit", "portable",
                            (sys.executable, "-c", "print(%r)" % output), "f", "b")
            result = run_plan(plan)
            self.assertEqual(status, result.status)
            self.assertEqual(count, result.executed)
        plan = TestPlan("x", ("x",), "edit", "portable",
                        (sys.executable, "-c", "import sys; sys.stdout.write('x'*300000)"),
                        "f", "b")
        result = run_plan(plan)
        self.assertEqual("empty", result.status)
        self.assertEqual(300000, len(result.stdout))

    def test_cli_subprocess_requires_real_summary(self):
        env = dict(os.environ, PYTHONPATH=os.path.join(os.path.dirname(__file__), "..", "src"))
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        command = [sys.executable, "-m", "fenton_tooling", "run",
                   "--component", "x", "--selector", "x", "--command",
                   sys.executable, "-c", "pass"]
        empty = subprocess.run(command, cwd=root, env=env, capture_output=True)
        self.assertNotEqual(0, empty.returncode)
        command[-1] = "print('Ran 1 test in 0.01s\\n\\nOK')"
        passed = subprocess.run(command, cwd=root, env=env, capture_output=True)
        self.assertEqual(0, passed.returncode)

    def test_cancellation_drains_pipe_and_kills_child_tree(self):
        event = threading.Event()
        code = ("import subprocess,sys,time; "
                "subprocess.Popen([sys.executable,'-c','import time; time.sleep(20)']); "
                "sys.stdout.write('x'*300000); sys.stdout.flush(); time.sleep(20)")
        plan = TestPlan("x", ("x",), "edit", "portable",
                        (sys.executable, "-c", code), "f", "b", timeout_seconds=5)
        timer = threading.Timer(.1, event.set)
        timer.start()
        result = run_plan(plan, event)
        timer.cancel()
        self.assertEqual("cancelled", result.status)

    def test_cancellation_cleans_owned_process(self):
        event = threading.Event()
        plan = TestPlan("x", ("x",), "edit", "portable",
                        (sys.executable, "-c", "import time; time.sleep(20)"),
                        "f", "b", timeout_seconds=5)
        timer = threading.Timer(.05, event.set)
        timer.start()
        result = run_plan(plan, event)
        self.assertEqual("cancelled", result.status)
        timer.cancel()

    def test_admission_rejects_self_review_moved_sha_and_missing_tests(self):
        task = Task("t", "abcdef0")
        task.evidence.append("e")
        ok, failures = admission_check(
            task, {"reviewer": "a", "author": "a", "exact_sha": "abcdef0",
                   "tests_passed": False}, "changed", ["README.md"],
                  {"trusted_root_required": True})
        self.assertFalse(ok)
        self.assertIn("self-review", failures)
        self.assertIn("moved head", failures)

    def test_decision_abstains_in_low_confidence_band(self):
        decision = normalize(DecisionQuestion("q", "1"), {"answer": "yes", "confidence": .2})
        self.assertEqual("abstain", decision.answer)

    def test_untrusted_policy_and_unavailable_key_are_rejected_safely(self):
        task = Task("t", "abcdef0")
        ok, failures = admission_check(
            task, {"reviewer": "b", "author": "a", "exact_sha": "abcdef0",
                   "tests_passed": True}, "abcdef0", [], {})
        self.assertFalse(ok)
        self.assertIn("untrusted policy", failures)
        unavailable = replay(DecisionQuestion("q", "1"), {},
                              lambda _q, _p: (_ for _ in ()).throw(KeyError("key")))
        self.assertEqual("abstain", unavailable.answer)

    def test_state_and_evidence_ids_are_safe_and_immutable(self):
        with self.assertRaises(ContractError):
            Task("../escape", "abcdef0")
        evidence = Evidence("run-1", "abcdef0", "tree", "0.1", "1", "p",
                            ("selector",), "fixture", "config", {},
                            RunResult("passed", executed=1, passed=1))
        with tempfile.TemporaryDirectory() as state:
            key = os.path.join(state, "external-key")
            with open(key, "wb") as handle:
                handle.write(b"synthetic-external-key")
            previous = os.environ.get("FENTON_ATTESTATION_KEY")
            os.environ["FENTON_ATTESTATION_KEY"] = key
            try:
                write_evidence(state, evidence)
            finally:
                if previous is None:
                    os.environ.pop("FENTON_ATTESTATION_KEY", None)
                else:
                    os.environ["FENTON_ATTESTATION_KEY"] = previous
            with self.assertRaises(ContractError):
                write_evidence(state, evidence)

    @unittest.skipUnless(hasattr(os, "symlink"), "symlinks unavailable")
    def test_artifact_digest_rejects_symlink_escape(self):
        with tempfile.TemporaryDirectory() as root:
            outside = os.path.join(os.path.dirname(root), "outside-artifact")
            with open(outside, "w", encoding="utf-8") as handle:
                handle.write("outside")
            os.symlink(outside, os.path.join(root, "artifact"))
            with self.assertRaises(ContractError):
                _digest(root, "artifact")
            os.unlink(outside)

    def test_concurrent_evidence_writers_have_one_winner(self):
        evidence = Evidence("concurrent", "abcdef0", "tree", "0.1", "1", "p",
                            ("selector",), "fixture", "config", {},
                            RunResult("passed", executed=1, passed=1))
        with tempfile.TemporaryDirectory() as state:
            def write():
                try:
                    write_evidence(state, evidence)
                    return "won"
                except ContractError:
                    return "lost"
            with ThreadPoolExecutor(max_workers=2) as pool:
                outcomes = list(pool.map(lambda _: write(), range(2)))
            self.assertEqual(["lost", "won"], sorted(outcomes))

    def test_candidate_review_cannot_run_without_external_pinned_runner(self):
        env = dict(os.environ, PYTHONPATH=os.path.join(os.path.dirname(__file__), "..", "src"))
        env.pop("FENTON_TRUSTED_ROOT", None)
        root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
        result = subprocess.run(
            [sys.executable, "-m", "fenton_tooling", "review", "task",
             "--artifact", "review.json"], cwd=root, env=env, capture_output=True,
            text=True)
        self.assertEqual(2, result.returncode)
        self.assertIn("runner", result.stdout)

    def test_native_runner_argv_retains_selectors(self):
        for kind in ("unittest", "swiftpm", "xcode", "web", "gradle"):
            plan = plan_for(kind, ("A", "B"), "Component")
            self.assertTrue(any("A" in arg or "B" in arg for arg in plan.command))
        with self.assertRaises(ValueError):
            plan_for("dotnet", ("A", "B"), "Component")


if __name__ == "__main__":
    unittest.main()
