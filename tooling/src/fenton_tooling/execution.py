"""Bounded argv execution with canonical capacity and owned cleanup."""
import json
import os
import signal
import subprocess
import sys
import threading
import time

from .capacity import devcap_command
from .model import ContractError, RunResult, TestPlan

_HELPER_TERM_GRACE = 5.0
_BRIDGE_CLEANUP_GRACE = 7.0


def _reader(stream, chunks):
    while True:
        chunk = stream.read(65536)
        if not chunk:
            return
        chunks.append(chunk)


def _owned_command(command, cwd):
    proc = subprocess.Popen(list(command), cwd=cwd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, start_new_session=True)
    out, err = [], []
    readers = [threading.Thread(target=_reader, args=(stream, chunks), daemon=True)
               for stream, chunks in ((proc.stdout, out), (proc.stderr, err))]
    for reader in readers:
        reader.start()
    stop_requested = False
    stop_at = None

    def forward(signum, _frame):
        nonlocal stop_requested, stop_at
        stop_requested = True
        stop_at = time.monotonic() + _HELPER_TERM_GRACE
        try:
            os.killpg(proc.pid, signum)
        except ProcessLookupError:
            pass

    previous = {sig: signal.signal(sig, forward)
                for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT)}
    try:
        while True:
            try:
                code = proc.wait(timeout=.2)
                break
            except subprocess.TimeoutExpired:
                if stop_requested and time.monotonic() >= stop_at:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    code = proc.wait()
                    break
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            time.sleep(.05)
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        for reader in readers:
            reader.join(2)
        stdout, stderr = b"".join(out), b"".join(err)
        proc.stdout.close()
        proc.stderr.close()
        sys.stdout.buffer.write(stdout)
        sys.stdout.buffer.flush()
        sys.stderr.buffer.write(stderr)
        sys.stderr.buffer.flush()
    return 128 - code if code < 0 else code


def _helper_main(argv):
    if len(argv) != 1:
        return 2
    try:
        command, cwd = json.loads(argv[0])
        if not isinstance(command, list) or not command or not isinstance(cwd, str):
            return 2
        return _owned_command(command, cwd)
    except (OSError, ValueError, TypeError):
        return 2


def isolated_helper_command(command, cwd):
    """Return the absolute-package, isolated helper argv used under devcap."""
    payload = json.dumps([list(command), cwd], separators=(",", ":"))
    package_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    bootstrap = ("import sys; sys.path.insert(0, %r); "
                 "from fenton_tooling.execution import _helper_main; "
                 "raise SystemExit(_helper_main(sys.argv[2:]))" % package_root)
    return (sys.executable, "-I", "-c", bootstrap, "--owned-helper", payload)


def _parse_output(stdout, stderr, exit_code):
    from .testing import parse_native_summary
    status, executed, passed, failed, skipped = parse_native_summary(
        stdout + "\n" + stderr, exit_code)
    reason = "unqualified summary: Gradle lacks an authoritative pass count" if status == "infra" else (
        "" if executed else "unrecognized test summary")
    if status == "infra":
        status = "passed"
    return RunResult(status, executed, passed, failed, skipped, exit_code,
                     reason, stdout, stderr)


def run_plan(plan: TestPlan, cancel_event=None) -> RunResult:
    command = tuple(plan.command)
    wrapped = bool(plan.resources)
    if wrapped:
        try:
            command = devcap_command(
                plan.resources,
                isolated_helper_command(command, plan.cwd),
                "%s %s" % (plan.component, plan.fixture), plan.timeout_seconds)
        except (OSError, ValueError, ContractError) as exc:
            return RunResult("infra", reason=str(exc))
    if os.name == "nt":
        return RunResult("infra", reason="Windows owned process cleanup is unsupported")
    try:
        proc = subprocess.Popen(list(command), cwd=plan.cwd, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=False,
                                start_new_session=True)
    except (OSError, ValueError) as exc:
        return RunResult("infra", reason=str(exc))
    out, err = [], []
    readers = [threading.Thread(target=_reader, args=(stream, chunks), daemon=True)
               for stream, chunks in ((proc.stdout, out), (proc.stderr, err))]
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
        time.sleep(.01)
    if cancelled or timed_out:
        try:
            if wrapped:
                proc.send_signal(signal.SIGTERM)
            else:
                os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(_BRIDGE_CLEANUP_GRACE if wrapped else 1)
        except (OSError, subprocess.TimeoutExpired):
            try:
                proc.kill() if wrapped else os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            proc.wait()
    else:
        proc.wait()
        if not wrapped:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                time.sleep(.05)
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    for reader in readers:
        reader.join(2)
    stdout = b"".join(out).decode("utf-8", "replace")
    stderr = b"".join(err).decode("utf-8", "replace")
    proc.stdout.close()
    proc.stderr.close()
    if cancelled or timed_out:
        return RunResult("cancelled" if cancelled else "timeout",
                         exit_code=proc.returncode, stdout=stdout, stderr=stderr,
                         reason="cancelled" if cancelled else "timeout")
    return _parse_output(stdout, stderr, proc.returncode)


if __name__ == "__main__" and len(sys.argv) >= 2 and sys.argv[1] == "--owned-helper":
    raise SystemExit(_helper_main(sys.argv[2:]))
