import os
import json
import shutil
import stat
import subprocess
import sys
import threading
import unittest
import uuid

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

from fenton_tooling import __version__
from fenton_tooling.hosts import build_invocation, run_invocation
from fenton_tooling.learning import (cache_namespace, friction_digest,
                                     metadata_allowlist, propose, question,
                                     replay_decision, synthetic_test)
from fenton_tooling.model import ContractError
from fenton_tooling.orchestration import load_task
from fenton_tooling.runtime import (BoundedRuntime, RegisteredJob, replay,
                                    verify_source_root)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        base = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
            os.path.abspath(__file__)))), ".runtime-test-" + uuid.uuid4().hex)
        self.base = base
        self.root_name, self.state_name, self.trusted_name = (
            base + "-root", base + "-state", base + "-trusted")
        os.makedirs(self.root_name)
        os.makedirs(self.state_name)
        os.makedirs(os.path.join(self.trusted_name, ".fenton"))
        subprocess.run(["git", "init", "-q", self.root_name], check=True)
        subprocess.run(["git", "-C", self.root_name, "config", "user.email",
                        "test@example.invalid"], check=True)
        subprocess.run(["git", "-C", self.root_name, "config", "user.name",
                        "Test"], check=True)
        with open(os.path.join(self.root_name, "marker"), "w", encoding="utf-8") as handle:
            handle.write("ok")
        subprocess.run(["git", "-C", self.root_name, "add", "marker"], check=True)
        subprocess.run(["git", "-C", self.root_name, "commit", "-q", "-m",
                        "fixture"], check=True)
        self.sha = subprocess.check_output(
            ["git", "-C", self.root_name, "rev-parse", "HEAD"], text=True).strip()
        self.profile = {"schema_version": "1", "recipes": {
            "one": {"component": "portable", "platform": "portable",
                    "argv": [sys.executable, "-c", "print('Ran 1 test\\n\\nOK')"],
                    "selectors": ["one"], "cwd": ".", "timeout_seconds": 10}}}
        self.policy = {"trusted_root_required": True, "protected_paths": []}
        with open(os.path.join(self.trusted_name, ".fenton", "repo.json"),
                  "w", encoding="utf-8") as handle:
            json.dump(self.profile, handle)
        with open(os.path.join(self.trusted_name, ".fenton", "policy.json"),
                  "w", encoding="utf-8") as handle:
            json.dump(self.policy, handle)
        with open(os.path.join(self.trusted_name, ".fenton", "runtime.json"),
                  "w", encoding="utf-8") as handle:
            json.dump({"schema_version": "1", "jobs": [{
                "job_id": "smoke", "recipe": "one", "role": "verifier",
                "authority": "read-only"}]}, handle)

    def tearDown(self):
        shutil.rmtree(self.root_name, ignore_errors=True)
        shutil.rmtree(self.state_name, ignore_errors=True)
        shutil.rmtree(self.trusted_name, ignore_errors=True)

    def test_dag_blocks_unreviewed_prerequisite(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        results = runtime.dispatch(
            (RegisteredJob("first", "one"), RegisteredJob(
                "second", "one", prerequisites=("first",))), self.sha)
        self.assertEqual("verifying", results["first"]["state"])
        self.assertEqual("pending-review", results["second"]["state"])

    def test_resume_re_evaluates_dependency_wait_records(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        jobs = (RegisteredJob("first", "one"), RegisteredJob(
            "second", "one", prerequisites=("first",)))
        first = runtime.dispatch(jobs, self.sha)
        runtime._save(dict(first["first"], state="accepted", decision="accepted"))
        resumed = runtime.dispatch(
            jobs, self.sha, run_id=first["first"]["run_id"], resume=True)
        self.assertEqual("verifying", resumed["second"]["state"])
        self.assertEqual(1, resumed["second"]["attempts"])

    def test_source_must_be_clean_and_exact(self):
        verify_source_root(self.root_name, self.sha)
        with open(os.path.join(self.root_name, "dirty"), "w", encoding="utf-8") as handle:
            handle.write("x")
        with self.assertRaises(ContractError):
            verify_source_root(self.root_name, self.sha)
        os.unlink(os.path.join(self.root_name, "dirty"))
        with open(os.path.join(self.root_name, "moved"), "w", encoding="utf-8") as handle:
            handle.write("new")
        subprocess.run(["git", "-C", self.root_name, "add", "moved"], check=True)
        subprocess.run(["git", "-C", self.root_name, "commit", "-q", "-m",
                        "move"], check=True)
        with self.assertRaises(ContractError):
            verify_source_root(self.root_name, self.sha)

    def test_cycle_is_rejected_before_any_job_runs(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        with self.assertRaises(ContractError):
            runtime.dispatch((RegisteredJob("a", "one", ("b",)),
                              RegisteredJob("b", "one", ("a",))), self.sha)
        self.assertEqual([], os.listdir(os.path.join(self.state_name, "jobs")))

    def test_flock_excludes_live_writer_and_recovers_after_crash(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        runtime._lock()
        try:
            code = (
                "import os,sys; sys.path.insert(0,%r); "
                "from fenton_tooling.runtime import BoundedRuntime; "
                "r=BoundedRuntime(%r,%r,{},{}); r._lock()"
            ) % (os.path.join(os.path.dirname(__file__), "..", "src"),
                 self.root_name, self.state_name)
            blocked = subprocess.run([sys.executable, "-c", code],
                                     capture_output=True)
            self.assertNotEqual(0, blocked.returncode)
        finally:
            runtime._unlock()
        crash = (
            "import os,sys; sys.path.insert(0,%r); "
            "from fenton_tooling.runtime import BoundedRuntime; "
            "r=BoundedRuntime(%r,%r,{},{}); r._lock(); os._exit(0)"
        ) % (os.path.join(os.path.dirname(__file__), "..", "src"),
             self.root_name, self.state_name)
        self.assertEqual(0, subprocess.run([sys.executable, "-c", crash]).returncode)
        recovered = BoundedRuntime(self.root_name, self.state_name,
                                   self.profile, self.policy)
        recovered._lock()
        recovered._unlock()

    def test_cancelled_run_is_persisted_as_cancelled(self):
        event = threading.Event()
        profile = {"schema_version": "1", "recipes": {
            "slow": {"component": "portable", "platform": "portable",
                     "argv": [sys.executable, "-c",
                              "import time; time.sleep(20)"],
                     "selectors": ["slow"], "cwd": ".", "timeout_seconds": 30}}}
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 profile, self.policy)
        timer = threading.Timer(.05, event.set)
        timer.start()
        try:
            result = runtime.dispatch((RegisteredJob("slow-job", "slow"),),
                                      self.sha, cancel_event=event)["slow-job"]
        finally:
            timer.cancel()
        self.assertEqual("cancelled", result["state"])
        self.assertEqual("cancelled", result["result"]["status"])

    def test_orphan_resume_is_explicit_and_attempt_bounded(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        runtime._save({"job_id": "orphan", "state": "running",
                       "source_sha": self.sha, "run_id": "orphan-run",
                       "owner_pid": 99999999, "attempts": 1, "recipe": "one",
                       "prerequisites": [], "role": "verifier",
                       "authority": "read-only"})
        first = runtime.dispatch((RegisteredJob("orphan", "one", max_attempts=2),),
                                 self.sha)
        self.assertEqual("orphaned", first["orphan"]["state"])
        resumed = runtime.dispatch(
            (RegisteredJob("orphan", "one", max_attempts=2),), self.sha,
            run_id="orphan-run", resume=True)
        self.assertEqual("verifying", resumed["orphan"]["state"])
        self.assertEqual(2, resumed["orphan"]["attempts"])
        runtime._save(dict(resumed["orphan"], state="orphaned", owner_pid=99999999))
        exhausted = runtime.dispatch(
            (RegisteredJob("orphan", "one", max_attempts=2),), self.sha,
            run_id="orphan-run", resume=True)
        self.assertEqual("rejected", exhausted["orphan"]["state"])

    def test_mixed_persisted_runs_are_rejected_before_dispatch(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        for job_id, run_id in (("a", "run-a"), ("b", "run-b")):
            runtime._save({"job_id": job_id, "state": "verifying",
                           "source_sha": self.sha, "run_id": run_id,
                           "attempts": 1, "recipe": "one",
                           "prerequisites": [], "role": "verifier",
                           "authority": "read-only"})
        with self.assertRaisesRegex(ContractError, "mixed runs"):
            runtime.dispatch((RegisteredJob("a", "one"),
                              RegisteredJob("b", "one")), self.sha,
                             run_id="run-a", resume=True)

    def test_task_file_identity_is_bound_to_requested_job(self):
        os.makedirs(os.path.join(self.state_name, "tasks"), exist_ok=True)
        with open(os.path.join(self.state_name, "tasks", "job-a.json"),
                  "w", encoding="utf-8") as handle:
            json.dump({"task_id": "job-b", "source_sha": self.sha,
                       "state": "accepted"}, handle)
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            load_task(self.state_name, "job-a")

    def test_dispatch_cli_uses_external_registry_for_clean_candidate_smoke(self):
        env = dict(os.environ, PYTHONPATH=os.path.join(
            os.path.dirname(__file__), "..", "src"))
        completed = subprocess.run(
            [sys.executable, "-m", "fenton_tooling.runtime", "dispatch",
             "--repo-root", self.root_name, "--trusted-root", self.trusted_name,
             "--state-dir", self.state_name, "--source-sha", self.sha],
            cwd=os.path.join(os.path.dirname(__file__), "..", ".."),
            env=env, capture_output=True, text=True, check=False)
        self.assertEqual(0, completed.returncode, completed.stderr)
        payload = json.loads(completed.stdout)
        self.assertEqual("verifying", payload["jobs"]["smoke"]["state"])
        self.assertEqual("read-only", payload["jobs"]["smoke"]["authority"])

    def test_host_dry_run_is_strict(self):
        invocation = build_invocation(
            "copilot", "gpt-5.6-luna", "reviewer", "inspect",
            trusted_cwd=self.state_name, candidate_root=self.root_name,
            state_dir=self.state_name)
        self.assertNotIn("--allow-all", invocation.argv)
        self.assertNotIn("--yolo", invocation.argv)
        self.assertIn("--no-custom-instructions", invocation.argv)
        self.assertIn("--allow-tool", invocation.argv)
        self.assertIn("--available-tools", invocation.argv)
        self.assertNotIn("bash", invocation.argv)
        self.assertEqual("dry-run", run_invocation(invocation)["status"])
        with self.assertRaises(ContractError):
            run_invocation(invocation, dry_run=False)
        with self.assertRaises(ContractError):
            build_invocation("unknown", "gpt-5.6-luna", "reviewer", "inspect",
                             trusted_cwd=self.state_name, state_dir=self.state_name)
        with self.assertRaises(ContractError):
            build_invocation("copilot", "claude-opus-5.5", "reviewer", "inspect",
                             trusted_cwd=self.state_name, state_dir=self.state_name)
        with self.assertRaises(ContractError):
            build_invocation("copilot", "gpt-5.6-luna", "reviewer", "inspect",
                             trusted_cwd=self.state_name, state_dir=self.state_name,
                             available_tools=("bash",))

    def test_runtime_replay_is_deterministic(self):
        journal = os.path.join(self.state_name, "journal.jsonl")
        with open(journal, "w", encoding="utf-8") as handle:
            handle.write('{"event":"started","job_id":"one"}\n')
            handle.write('{"event":"rejected","job_id":"one"}\n')
        first = replay(journal)
        self.assertEqual(first, replay(journal))
        self.assertEqual(2, first["event_count"])

    def test_learning_is_allowlisted_bounded_and_shadow_only(self):
        metadata = {"component": "portable-testing", "outcome": "failed"}
        self.assertEqual(metadata, metadata_allowlist(metadata))
        proposals = propose(metadata, [
            {"action": "a", "proving_test": "t1"},
            {"action": "b", "proving_test": "t2"},
            {"action": "c", "proving_test": "t3"},
            {"action": "d", "proving_test": "t4"}])
        self.assertEqual(3, len(proposals))
        self.assertFalse(synthetic_test(proposals[0])["applied"])
        self.assertEqual("abstain", replay_decision(
            question("q"), {"answer": "yes", "confidence": .2}).answer)
        self.assertNotEqual(cache_namespace("jev"), cache_namespace("openrouter"))
        with self.assertRaises(ContractError):
            friction_digest({"transcript": "private"})

    def test_external_acceptance_is_fail_closed_for_untrusted_negatives(self):
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, self.policy)
        cases = (
            {"exact_sha": "moved-head"},
            {"reviewer": "self", "author": "self"},
            {"receipt": "missing"},
            {"result": {"status": "passed", "executed": 2, "skipped": 2}},
            {"changed_paths": ["evals/graders/protected.py"]},
            {"selectors": []},
            {"cross_repo": True},
        )
        for case in cases:
            with self.subTest(case=case):
                with self.assertRaises(ContractError):
                    runtime.accept("job", "review.json")

    def _fixture_runtime(self, mode, source_sha=None):
        package_root = os.path.join(self.trusted_name, "package")
        shutil.rmtree(package_root, ignore_errors=True)
        shutil.copytree(os.path.join(os.path.dirname(__file__), "..", "src",
                                     "fenton_tooling"), package_root)
        runner = os.path.join(self.trusted_name, "runner.py")
        with open(runner, "w", encoding="utf-8") as handle:
            handle.write(
                "#!/usr/bin/env python3\n"
                "import json, os, subprocess, sys\n"
                "mode = os.environ['FIXTURE_MODE']\n"
                "if mode == 'exit': raise SystemExit(1)\n"
                "root = os.getcwd()\n"
                "if mode == 'move':\n"
                "    open(os.path.join(root, 'review-moved'), 'w').close()\n"
                "    subprocess.run(['git', 'add', 'review-moved'], check=True)\n"
                "    subprocess.run(['git', '-c', 'user.email=fixture@example.invalid', '-c', 'user.name=fixture', 'commit', '-m', 'review'], check=True)\n"
                "if mode in ('wrong', 'accept'):\n"
                "    sha = os.environ['TASK_SHA'] if mode == 'accept' else 'a' * 40\n"
                "    path = os.path.join(os.environ['FENTON_TRUSTED_STATE'], 'tasks')\n"
                "    os.makedirs(path, exist_ok=True)\n"
                "    with open(os.path.join(path, sys.argv[2] + '.json'), 'w') as f:\n"
                "        json.dump({'task_id': sys.argv[2], 'source_sha': sha, 'state': 'accepted', 'attempts': 1, 'evidence': ['external'], 'owner': 'fixture'}, f)\n"
                "raise SystemExit(0)\n")
        os.chmod(runner, os.stat(runner).st_mode | stat.S_IXUSR)
        from fenton_tooling.trust import package_digest
        with open(os.path.join(self.trusted_name, "runner.json"), "w", encoding="utf-8") as handle:
            json.dump({"distribution": "fenton-tooling", "version": __version__,
                       "executable": runner, "package_root": package_root,
                       "package_digest": package_digest(package_root)}, handle)
        policy = dict(self.policy, trusted_reviewers=["fixture"])
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 self.profile, policy, self.trusted_name)
        runtime._save({"job_id": "job", "state": "verifying",
                       "source_sha": self.sha, "run_id": "run", "attempts": 1})
        artifact = os.path.join(self.trusted_name, "review.json")
        with open(artifact, "w", encoding="utf-8") as handle:
            handle.write("{}")
        env = dict(os.environ, FIXTURE_MODE=mode,
                   TASK_SHA=source_sha or self.sha)
        return runtime, artifact, env

    def test_external_review_bridge_consumes_only_external_accepted_task(self):
        runtime, artifact, env = self._fixture_runtime("accept")
        old = os.environ.copy()
        os.environ.update(env)
        try:
            result = runtime.accept("job", artifact)
        finally:
            os.environ.clear()
            os.environ.update(old)
        self.assertEqual("accepted", result["state"])

    def test_external_review_bridge_rejects_cli_exit_moved_head_and_sha_mismatch(self):
        for mode, expected in (("exit", "external review did not accept task"),
                               ("wrong", "accepted task SHA"),
                               ("move", "source SHA")):
            runtime, artifact, env = self._fixture_runtime(mode)
            old = os.environ.copy()
            os.environ.update(env)
            try:
                with self.assertRaisesRegex(ContractError, expected):
                    runtime.accept("job", artifact)
            finally:
                os.environ.clear()
                os.environ.update(old)

    def _actual_cli_fixture(self, result):
        with open(os.path.join(self.root_name, "marker"), "w",
                  encoding="utf-8") as handle:
            handle.write("review-target-" + uuid.uuid4().hex)
        subprocess.run(["git", "-C", self.root_name, "add", "marker"], check=True)
        subprocess.run(["git", "-C", self.root_name, "commit", "-q", "-m",
                        "review-target"], check=True)
        source_sha = subprocess.check_output(
            ["git", "-C", self.root_name, "rev-parse", "HEAD"], text=True).strip()
        base_sha = subprocess.check_output(
            ["git", "-C", self.root_name, "rev-parse", "HEAD^"], text=True).strip()
        profile = {
            "schema_version": "1",
            "components": {"marker-component": {
                "paths": ["marker"], "selectors": ["portable-smoke"]}},
            "recipes": {}
        }
        policy = {
            "schema_version": "1", "version": "0.2.0",
            "trusted_root_required": True,
            "trusted_reviewers": ["synthetic-reviewer"],
            "protected_reviewers": [],
            "fixture_generation": "synthetic-v1",
            "build_identity": "local", "protected_paths": [],
            "acceptance": {"require_exact_sha": True,
                           "require_independent_review": True,
                           "require_executed_tests": True},
            "authority": {"cross_repo": False, "production": False,
                          "automatic_promotion": False, "provider_calls": False}
        }
        for root in (self.trusted_name,
                     os.path.join(self.trusted_name, ".fenton")):
            with open(os.path.join(root, "repo.json"), "w", encoding="utf-8") as handle:
                json.dump(profile, handle)
            with open(os.path.join(root, "policy.json"), "w", encoding="utf-8") as handle:
                json.dump(policy, handle)
        package_root = os.path.join(self.trusted_name, "actual-package")
        shutil.rmtree(package_root, ignore_errors=True)
        os.makedirs(package_root)
        shutil.copytree(os.path.join(os.path.dirname(__file__), "..", "src",
                                     "fenton_tooling"),
                        os.path.join(package_root, "fenton_tooling"))
        runner = os.path.join(self.trusted_name, "actual-runner.py")
        with open(runner, "w", encoding="utf-8") as handle:
            handle.write(
                "#!/usr/bin/env python3\n"
                "import sys\n"
                "sys.path.insert(0, %r)\n"
                "from fenton_tooling.cli import main\n"
                "raise SystemExit(main())\n" % package_root)
        os.chmod(runner, os.stat(runner).st_mode | stat.S_IXUSR)
        from fenton_tooling.trust import attest, package_digest
        with open(os.path.join(self.trusted_name, "runner.json"), "w", encoding="utf-8") as handle:
            json.dump({"distribution": "fenton-tooling", "version": __version__,
                       "executable": runner, "package_root": package_root,
                       "package_digest": package_digest(package_root)}, handle)
        key_path = os.path.join(self.trusted_name, "attestation-key")
        with open(key_path, "wb") as handle:
            handle.write(b"synthetic-external-review-key")
        evidence = {
            "run_id": "actual-evidence", "source_sha": source_sha,
            "tree_fingerprint": subprocess.check_output(
                ["git", "-C", self.root_name, "rev-parse", source_sha + "^{tree}"],
                text=True).strip(),
            "tooling_version": __version__, "schema_version": "1",
            "policy_version": "0.2.0", "selection": ["portable-smoke"],
            "fixture_generation": "synthetic-v1", "configuration": "local",
            "artifact_digests": {}, "result": result
        }
        evidence["attestation"] = attest(evidence, key_path)
        os.makedirs(os.path.join(self.state_name, "evidence"), exist_ok=True)
        with open(os.path.join(self.state_name, "evidence",
                               "actual-evidence.json"), "w", encoding="utf-8") as handle:
            json.dump(evidence, handle)
        os.makedirs(os.path.join(self.state_name, "tasks"), exist_ok=True)
        with open(os.path.join(self.state_name, "tasks", "actual-job.json"),
                  "w", encoding="utf-8") as handle:
            json.dump({"task_id": "actual-job", "source_sha": source_sha,
                       "base_sha": base_sha, "state": "verifying", "attempts": 1,
                       "evidence": ["actual-evidence"], "owner": "operator"}, handle)
        artifact = os.path.join(self.trusted_name, "actual-review.json")
        with open(artifact, "w", encoding="utf-8") as handle:
            json.dump({"reviewer": "synthetic-reviewer", "author": "operator",
                       "exact_sha": source_sha,
                       "evidence_refs": ["actual-evidence"]}, handle)
        runtime = BoundedRuntime(self.root_name, self.state_name,
                                 profile, policy, self.trusted_name)
        runtime._save({"job_id": "actual-job", "state": "verifying",
                       "source_sha": source_sha, "run_id": "actual-run",
                       "attempts": 1, "recipe": "unused",
                       "prerequisites": [], "role": "verifier",
                       "authority": "read-only"})
        env = dict(os.environ, FENTON_ATTESTATION_KEY=key_path)
        return runtime, artifact, env

    def test_actual_external_cli_accepts_only_valid_attested_receipt(self):
        result = {"status": "passed", "executed": 1, "passed": 1, "failed": 0,
                  "skipped": 0, "exit_code": 0, "reason": "", "stdout": "",
                  "stderr": "", "artifacts": [], "retry_count": 0}
        runtime, artifact, env = self._actual_cli_fixture(result)
        old = os.environ.copy()
        os.environ.update(env)
        try:
            accepted = runtime.accept("actual-job", artifact)
        finally:
            os.environ.clear()
            os.environ.update(old)
        self.assertEqual("accepted", accepted["state"])

    def test_actual_external_cli_rejects_nonzero_and_all_skipped_attested_receipts(self):
        for result in (
            {"status": "passed", "executed": 1, "passed": 1, "failed": 0,
             "skipped": 0, "exit_code": 1, "reason": "", "stdout": "",
             "stderr": "", "artifacts": [], "retry_count": 0},
            {"status": "passed", "executed": 2, "passed": 0, "failed": 0,
             "skipped": 2, "exit_code": 0, "reason": "", "stdout": "",
             "stderr": "", "artifacts": [], "retry_count": 0},
        ):
            runtime, artifact, env = self._actual_cli_fixture(result)
            old = os.environ.copy()
            os.environ.update(env)
            try:
                with self.assertRaisesRegex(ContractError,
                                             "external review did not accept task"):
                    runtime.accept("actual-job", artifact)
            finally:
                os.environ.clear()
                os.environ.update(old)

    def test_failed_or_all_skipped_verification_never_becomes_pending_review(self):
        for name, output in (("bad", "Ran 2 tests\\n\\nFAILED (failures=1)"),
                             ("skipped", "Tests 2 skipped")):
            profile = {"schema_version": "1", "recipes": {
                name: {"component": "portable", "platform": "portable",
                       "argv": [sys.executable, "-c", "print(%r)" % output],
                       "selectors": [name], "cwd": ".", "timeout_seconds": 10}}}
            runtime = BoundedRuntime(self.root_name, self.state_name,
                                     profile, self.policy)
            result = runtime.dispatch(
                (RegisteredJob(name + "-job", name, max_attempts=2),), self.sha)[name + "-job"]
            self.assertEqual("rejected", result["state"])
            self.assertEqual(2, result["attempts"])


if __name__ == "__main__":
    unittest.main()
