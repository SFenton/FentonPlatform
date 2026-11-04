"""Bounded argv execution with drained pipes and owned-process cleanup."""
import os
import re
import signal
import subprocess
import threading
import time

from .model import RunResult, TestPlan


def _number(pattern, text, default=None):
    match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
    return int(match.group(1)) if match else default


def _parse_output(plan, stdout, stderr, exit_code):
    """Parse summaries emitted by supported native runners.

    A zero exit code without a recognized non-empty summary is deliberately
    ``empty``: process success is not test success.
    """
    text = stdout + "\n" + stderr
    executed = passed = failed = skipped = None

    # Python unittest: Ran N tests ... OK / FAILED (...).
    ran = _number(r"Ran\s+(\d+)\s+tests?\b", text)
    if ran is not None:
        executed = ran
        skipped = _number(r"skipped\s*=\s*(\d+)", text, 0) or 0
        failed = (_number(r"failures?\s*=\s*(\d+)", text, 0) or 0) + \
                 (_number(r"errors?\s*=\s*(\d+)", text, 0) or 0)
        if re.search(r"\bFAILED\b", text):
            failed = max(failed, 1)
        passed = max(0, executed - failed - skipped)
    else:
        # Node's TAP summary.
        tap = re.search(
            r"^\s*#\s*tests\s+(\d+)\s*$.*?"
            r"^\s*#\s*pass\s+(\d+)\s*$.*?"
            r"^\s*#\s*fail\s+(\d+)\s*$.*?"
            r"^\s*#\s*skipped\s+(\d+)\s*$", text,
            re.IGNORECASE | re.MULTILINE | re.DOTALL)
        if tap:
            executed, passed, failed, skipped = map(int, tap.groups())
        else:
            # dotnet test summary.
            summary = re.search(
            r"(?:Passed!|Failed!)\s*-\s*Failed:\s*(\d+),\s*Passed:\s*(\d+),"
            r"\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)", text, re.IGNORECASE)
            if summary:
                failed, passed, skipped, executed = map(int, summary.groups())
            else:
                # XCTest: Executed N tests, with F failure(s) (S unexpected).
                xctest = re.search(
                r"Executed\s+(\d+)\s+tests?,\s*with\s+(\d+)\s+failure",
                text, re.IGNORECASE)
                if xctest:
                    executed, failed = int(xctest.group(1)), int(xctest.group(2))
                    skipped = _number(r"skipped\s*[:=]\s*(\d+)", text, 0) or 0
                    passed = max(0, executed - failed - skipped)
                else:
                    # Vitest/Jest and similar summary: Tests N passed | N failed | N skipped.
                    test_line = re.search(
                    r"^\s*Tests?\s+(.+?)(?:\n|$)", text,
                    re.IGNORECASE | re.MULTILINE)
                    if test_line:
                        line = test_line.group(1)
                        passed = _number(r"(\d+)\s+passed", line, 0) or 0
                        failed = _number(r"(\d+)\s+failed", line, 0) or 0
                        skipped = (_number(r"(\d+)\s+(?:skipped|todo)", line, 0) or 0)
                        executed = passed + failed + skipped
                    else:
                        # Gradle: N tests completed, F failed, S skipped.
                        gradle = re.search(
                        r"(\d+)\s+tests?\s+completed,\s*(\d+)\s+failed(?:,\s*(\d+)\s+skipped)?",
                        text, re.IGNORECASE)
                        if gradle:
                            executed, failed = int(gradle.group(1)), int(gradle.group(2))
                            skipped = int(gradle.group(3) or 0)
                            passed = max(0, executed - failed - skipped)

    if executed is None:
        return RunResult("failed" if exit_code else "empty", exit_code=exit_code,
                         stdout=stdout, stderr=stderr,
                         reason="unrecognized test summary")
    if failed:
        status = "failed"
    elif executed == 0 or skipped == executed:
        status = "skipped" if skipped else "empty"
    else:
        status = "passed" if exit_code == 0 else "failed"
    return RunResult(status=status, executed=executed, passed=passed,
                     failed=failed, skipped=skipped, exit_code=exit_code,
                     stdout=stdout, stderr=stderr)


def _reader(stream, chunks):
    while True:
        chunk = stream.read(65536)
        if not chunk:
            return
        chunks.append(chunk)


def run_plan(plan: TestPlan, cancel_event=None) -> RunResult:
    if os.name == "nt":
        return RunResult("infra", reason="Windows owned process-tree cleanup requires a Job Object and is unsupported")
    else:
        creationflags = 0
        process_group = True
    try:
        proc = subprocess.Popen(list(plan.command), cwd=plan.cwd,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=False, start_new_session=process_group,
                                creationflags=creationflags)
    except (OSError, ValueError) as exc:
        return RunResult("infra", reason=str(exc))
    out_chunks, err_chunks = [], []
    readers = [
        threading.Thread(target=_reader, args=(proc.stdout, out_chunks), daemon=True),
        threading.Thread(target=_reader, args=(proc.stderr, err_chunks), daemon=True),
    ]
    for reader in readers:
        reader.start()
    started = time.monotonic()
    cancelled = timed_out = False
    while proc.poll() is None:
        if cancel_event is not None and cancel_event.is_set():
            cancelled = True
            break
        if time.monotonic() - started > plan.timeout_seconds:
            timed_out = True
            break
        time.sleep(0.01)
    if cancelled or timed_out:
        try:
            if os.name == "nt":
                proc.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(1)
        except (OSError, subprocess.TimeoutExpired):
            try:
                if os.name == "nt":
                    proc.kill()
                else:
                    os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
        try:
            proc.wait(2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()
    else:
        proc.wait()
        # A successful parent can leave a background descendant in its owned
        # process group. Reap the whole group before releasing the lease.
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            time.sleep(0.05)
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    for reader in readers:
        reader.join(2)
    stdout = b"".join(out_chunks).decode("utf-8", "replace")
    stderr = b"".join(err_chunks).decode("utf-8", "replace")
    proc.stdout.close()
    proc.stderr.close()
    if cancelled or timed_out:
        return RunResult("cancelled" if cancelled else "timeout",
                         exit_code=proc.returncode, stdout=stdout, stderr=stderr,
                         reason="cancelled" if cancelled else "timeout")
    return _parse_output(plan, stdout, stderr, proc.returncode)
