"""Host capacity adapter; uses an existing configured devcap executable."""
import os
import shutil
import subprocess


def devcap_status():
    executable = os.environ.get("FENTON_DEVCAP_EXECUTABLE") or shutil.which("devcap")
    if not executable:
        return {"available": False, "reason": "configured devcap executable not found"}
    try:
        completed = subprocess.run([executable, "status"], text=True,
                                   capture_output=True, timeout=10)
        return {"available": completed.returncode == 0,
                "executable": executable, "output": completed.stdout.strip(),
                "reason": completed.stderr.strip()}
    except (OSError, subprocess.SubprocessError) as exc:
        return {"available": False, "executable": executable, "reason": str(exc)}
