"""Run from an installed wheel, outside the source tree.

Usage: python -m tooling.tests.installed_smoke
The caller supplies an empty directory as cwd; this verifies ``fenton check``
uses packaged assets rather than consumer source files.
"""
import os
import subprocess
import sys
import tempfile
import unittest


@unittest.skipUnless(os.environ.get("FENTON_INSTALLED_SMOKE") == "1",
                     "run only from an installed wheel")
class InstalledSmoke(unittest.TestCase):
    def test_check_uses_packaged_assets(self):
        with tempfile.TemporaryDirectory() as cwd:
            result = subprocess.run([sys.executable, "-m", "fenton_tooling", "check"],
                                    cwd=cwd, capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
