"""One thin CLI for selection, execution, state, review and checks."""
import argparse
import hashlib
import json
import os
import subprocess
import sys

from .capacity import devcap_status
from .config import load_json, load_profile, select_components, selectors_for
from .decisions import DecisionQuestion, normalize
from .model import TestPlan
from .runners import plan_from_recipe
from .orchestration import Task, admission_check, load_task, save_task
from .model import ContractError, validate_id, validate_sha
from .execution import run_plan
from .evidence import verify_receipt
from .trust import ContractError as TrustContractError, verify_external_runner


def _git(root, *args):
    completed = subprocess.run(("git", "-C", root) + args, check=True,
                               capture_output=True, text=True)
    return completed.stdout.strip()


def _git_lines(root, *args):
    output = _git(root, *args)
    return [line for line in output.splitlines() if line]


def _result_certifies(result):
    return (result.get("status") == "passed" and
            result.get("executed", 0) > 0 and
            result.get("failed", 0) == 0 and
            result.get("skipped", 0) < result.get("executed", 0))


def _digest(root, relative_path):
    if os.path.isabs(relative_path):
        raise ContractError("absolute artifact path")
    root = os.path.abspath(root)
    candidate = os.path.abspath(os.path.join(root, relative_path))
    if os.path.commonpath((candidate, root)) != root:
        raise ContractError("artifact path escapes candidate")
    current = root
    for part in os.path.relpath(candidate, root).split(os.sep):
        current = os.path.join(current, part)
        if os.path.islink(current):
            raise ContractError("symlink artifact paths are not permitted")
    real_candidate = os.path.realpath(candidate)
    if os.path.commonpath((real_candidate, os.path.realpath(root))) != os.path.realpath(root):
        raise ContractError("artifact path escapes candidate")
    digest = hashlib.sha256()
    with open(candidate, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _candidate_clean(root):
    return _git_lines(root, "status", "--porcelain", "--untracked-files=all")


def _changed_between(root, base_sha, head_sha):
    return _git_lines(root, "diff", "--name-only", base_sha + ".." + head_sha)


def _delegate_review(root, args):
    trusted_root = os.path.abspath(os.environ.get("FENTON_TRUSTED_ROOT", ""))
    if not trusted_root:
        raise ContractError("external trusted root is required")
    executable = verify_external_runner(trusted_root, root, require_current=False)
    env = dict(os.environ)
    env["FENTON_TRUSTED_DELEGATED"] = "1"
    env.pop("PYTHONPATH", None)
    completed = subprocess.run([executable, "review", args.task_id,
                                "--artifact", os.path.abspath(args.artifact)],
                               cwd=root, env=env)
    return completed.returncode


def _installed_assets():
    package_parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    candidates = [
        os.path.join(package_parent, "fenton_tooling_assets"),
        os.path.join(sys.prefix, "fenton_tooling_assets"),
    ]
    for candidate in candidates:
        if os.path.isdir(candidate):
            return candidate
    return None


def _parser():
    parser = argparse.ArgumentParser(prog="fenton")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("doctor", "check"):
        sub.add_parser(name)
    select = sub.add_parser("select")
    select.add_argument("paths", nargs="+")
    run = sub.add_parser("run")
    run.add_argument("--component")
    run.add_argument("--command", dest="argv", nargs=argparse.REMAINDER)
    run.add_argument("--recipe")
    run.add_argument("--repo-root")
    run.add_argument("--selector", action="append")
    run.add_argument("--tier", default="edit")
    run.add_argument("--platform", default="portable")
    run.add_argument("--fixture", default="synthetic-v1")
    run.add_argument("--build", default="local")
    run.add_argument("--timeout", type=float, default=300)
    task = sub.add_parser("task")
    task.add_argument("task_id")
    task.add_argument("state", choices=("running", "verifying", "reviewing", "cancelled"))
    task.add_argument("sha", nargs="?")
    review = sub.add_parser("review")
    review.add_argument("task_id")
    review.add_argument("--artifact", required=True)
    evaluate = sub.add_parser("eval")
    evaluate.add_argument("question_id")
    evaluate.add_argument("answer")
    evaluate.add_argument("--version", default="1")
    evaluate.add_argument("--confidence", type=float, default=1.0)
    return parser


def main(argv=None):
    args = _parser().parse_args(argv)
    root = os.getcwd()
    if args.command == "review" and os.environ.get("FENTON_TRUSTED_DELEGATED") != "1":
        try:
            return _delegate_review(root, args)
        except (OSError, KeyError, ValueError, ContractError) as exc:
            print(json.dumps({"admission": "blocked", "reason": str(exc)}))
            return 2
    if args.command == "doctor":
        print(json.dumps({"profile": os.path.exists(".fenton/repo.json"),
                          "devcap": devcap_status()}, sort_keys=True))
        return 0
    if args.command == "check":
        assets = _installed_assets()
        if os.path.exists(os.path.join(root, ".fenton", "repo.json")):
            profile, policy = load_profile(root)
            if policy.get("trusted_root_required") is not True:
                raise SystemExit("policy must require trusted root")
            for component, deps in profile.get("dependencies", {}).items():
                if component not in profile["components"] or any(
                        dependency not in profile["components"] for dependency in deps):
                    raise SystemExit("invalid component dependency graph")
            if assets:
                required = ("contracts/repository.schema.json",
                            "roles/orchestrator.md",
                            "adapters/fenton-platform.md")
                if any(not os.path.exists(os.path.join(assets, item))
                       for item in required):
                    raise SystemExit("installed tooling assets are incomplete")
            else:
                for required in ("contracts/schemas", "agents/roles", "docs/README.md"):
                    if not os.path.exists(os.path.join(root, required)):
                        raise SystemExit("missing distribution content: " + required)
            print("ok: profile=%d components, protected=%d paths" %
                  (len(profile["components"]), len(policy.get("protected_paths", []))))
        else:
            assets = _installed_assets()
            required = ("contracts/repository.schema.json", "roles/orchestrator.md",
                        "adapters/fenton-platform.md")
            if not assets or any(not os.path.exists(os.path.join(assets, item))
                                 for item in required):
                raise SystemExit("installed tooling assets are incomplete")
            print("ok: installed tooling assets=%s" % assets)
        return 0
    if args.command != "review":
        profile, _ = load_profile(root)
    if args.command == "select":
        components = select_components(profile, args.paths)
        print(json.dumps({"components": components,
                          "selectors": selectors_for(profile, components)}))
        return 0
    if args.command == "run":
        if args.recipe:
            if not args.repo_root:
                raise SystemExit("--repo-root is required with --recipe")
            try:
                plan = plan_from_recipe(profile, args.recipe,
                                        os.path.abspath(args.repo_root), args.tier)
                result = run_plan(plan)
                print(json.dumps({"recipe": args.recipe, "result": result.__dict__},
                                 sort_keys=True))
                return 0 if result.certifies_success else 1
            except (ContractError, OSError, ValueError) as exc:
                print(json.dumps({"status": "infra", "reason": str(exc)}))
                return 2
        if not args.component or not args.selector or not args.argv:
            raise SystemExit("run requires --recipe or command arguments")
        plan = TestPlan(args.component, tuple(args.selector), args.tier,
                        args.platform, tuple(args.argv), args.fixture,
                        args.build, timeout_seconds=args.timeout)
        result = run_plan(plan)
        print(json.dumps(result.__dict__, sort_keys=True))
        return 0 if result.certifies_success else 1
    if args.command == "eval":
        decision = normalize(DecisionQuestion(args.question_id, args.version),
                             {"answer": args.answer, "confidence": args.confidence})
        print(json.dumps(decision.__dict__, sort_keys=True))
        return 0
    state_dir = os.environ.get("FENTON_TRUSTED_STATE")
    if args.command == "review":
        try:
            trusted_root = os.path.abspath(os.environ["FENTON_TRUSTED_ROOT"])
            verify_external_runner(trusted_root, root, require_current=True)
            if not state_dir or not os.path.isabs(state_dir):
                raise ContractError("externally owned trusted state is required")
            if not os.path.exists(state_dir) or not (
                    os.path.commonpath((os.path.abspath(state_dir),
                                        os.path.abspath(root))) != os.path.abspath(root)):
                raise ContractError("trusted state must be outside candidate")
            key_path = os.environ.get("FENTON_ATTESTATION_KEY")
            if not key_path or not os.path.isabs(key_path):
                raise ContractError("external attestation key is required")
            if os.path.commonpath((os.path.abspath(key_path),
                                   os.path.abspath(root))) == os.path.abspath(root):
                raise ContractError("attestation key must be outside candidate")
            if os.path.commonpath((trusted_root, os.path.abspath(root))) == os.path.abspath(root):
                raise ContractError("trusted root must be outside candidate")
            policy = load_json(os.path.join(trusted_root, "policy.json"))
            trusted_profile = load_json(os.path.join(trusted_root, "repo.json"))
            if policy.get("trusted_root_required") is not True:
                raise ContractError("untrusted policy")
            task = load_task(state_dir, args.task_id)
            current_sha = _git(root, "rev-parse", "HEAD")
            dirty = _candidate_clean(root)
            if dirty:
                raise ContractError("candidate worktree is dirty: " + ", ".join(dirty))
            if not task.base_sha:
                raise ContractError("task has no trusted base SHA")
            changed = _changed_between(root, task.base_sha, current_sha)
            expected_selectors = selectors_for(
                trusted_profile, select_components(trusted_profile, changed))
            artifact = load_json(os.path.abspath(args.artifact))
            if not isinstance(artifact, dict):
                raise ContractError("review artifact must be an object")
            reviewer = artifact.get("reviewer")
            trusted_reviewers = policy.get("trusted_reviewers", [])
            if reviewer not in trusted_reviewers:
                raise ContractError("reviewer is not trusted by external policy")
            evidence_ids = artifact.get("evidence_refs", [])
            if not evidence_ids:
                raise ContractError("review artifact has no evidence references")
            derived_evidence = []
            for evidence_id in evidence_ids:
                validate_id(evidence_id, "evidence id")
                if evidence_id not in task.evidence:
                    raise ContractError("review references unbound evidence")
                evidence = load_json(os.path.join(state_dir, "evidence",
                                                  evidence_id + ".json"))
                if evidence.get("run_id") != evidence_id:
                    raise ContractError("evidence identity mismatch")
                if evidence.get("source_sha") != task.source_sha or current_sha != task.source_sha:
                    raise ContractError("evidence SHA mismatch")
                if evidence.get("policy_version") != policy.get("version"):
                    raise ContractError("evidence policy mismatch")
                if sorted(evidence.get("selection", [])) != sorted(expected_selectors):
                    raise ContractError("receipt selection differs from trusted map")
                if policy.get("fixture_generation") and evidence.get("fixture_generation") != policy["fixture_generation"]:
                    raise ContractError("receipt fixture mismatch")
                if policy.get("build_identity") and evidence.get("configuration") != policy["build_identity"]:
                    raise ContractError("receipt build identity mismatch")
                verify_receipt(evidence, key_path)
                if evidence.get("tree_fingerprint") != _git(root, "rev-parse", current_sha + "^{tree}"):
                    raise ContractError("evidence tree mismatch")
                result = evidence.get("result", {})
                if not _result_certifies(result):
                    raise ContractError("evidence does not certify executed tests")
                for path, digest in evidence.get("artifact_digests", {}).items():
                    if _digest(root, path) != digest:
                        raise ContractError("artifact digest mismatch")
                derived_evidence.append(evidence_id)
            task.evidence = derived_evidence
            review_record = {
                "reviewer": reviewer, "author": artifact.get("author"),
                "exact_sha": artifact.get("exact_sha"),
                "tests_passed": bool(derived_evidence),
                "independent": reviewer != artifact.get("author"),
                "receipt_attested": bool(derived_evidence),
                "protected_approval": reviewer in policy.get("protected_reviewers", [])
            }
            accepted, failures = admission_check(
                task, review_record, current_sha, changed, policy)
            task.state = "accepted" if accepted else "rejected"
            save_task(state_dir, task)
            print(json.dumps({"admission": "accepted" if accepted else "rejected",
                              "failures": failures, "task": task.__dict__},
                             sort_keys=True))
            return 0 if accepted else 1
        except (OSError, KeyError, ValueError, ContractError) as exc:
            print(json.dumps({"admission": "blocked", "reason": str(exc)}))
            return 2
    task_dir = os.path.join(root, ".fenton-state")
    try:
        task = load_task(task_dir, args.task_id)
    except FileNotFoundError:
        if not args.sha:
            raise SystemExit("new task requires a source SHA")
        task = Task(args.task_id, args.sha)
    task.transition(args.state)
    save_task(task_dir, task)
    print(json.dumps(task.__dict__, sort_keys=True))
    return 0


if __name__ == "__main__":
    main()
