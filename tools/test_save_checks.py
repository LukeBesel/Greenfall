#!/usr/bin/env python3
"""Exercise the save-check shell entry points with failed Godot processes, without saves."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


FAKE_GODOT = r'''#!/usr/bin/env python3
import os
from pathlib import Path
import sys

counter = Path(os.environ["FAKE_COUNTER"])
stage = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(stage))
mode = os.environ["FAKE_MODE"]
if mode == "orbit":
    line = "[reload] wrote lumi=[1, 0, 0, 0] cubes=321 saved=true" if stage == 1 else "[reload] read lumi=[1, 0, 0, 0] saved=[1, 0, 0, 0] cubes=321 rocket=kept PASS"
else:
    line = "[old-ledger] PASS" if stage in (2, 4) else "[game] played and saved"
fault = os.environ.get("FAKE_FAULT", "") if stage == int(os.environ.get("FAKE_STAGE", "0")) else ""
if fault == "wrong":
    print("some other check: PASS", flush=True)
elif fault == "unsaved":
    print(line.replace("saved=true", "saved=false"), flush=True)
elif fault != "missing":
    print(line, flush=True)
if fault == "crash":
    sys.exit(134)
if fault == "timeout":
    sys.exit(124)
if fault == "script":
    print("SCRIPT ERROR: injected after the success marker", flush=True)
if fault == "fail":
    print("[reload] FAIL" if mode == "orbit" else "[old-ledger] FAIL", flush=True)
'''


class SaveCheckTests(unittest.TestCase):
    def run_check(self, mode, stage=0, fault="", source=None):
        if not shutil.which("timeout"):
            self.skipTest("timeout is required by the game's shell checks")
        with tempfile.TemporaryDirectory(prefix="greenfall-checks-") as tmp:
            root = Path(tmp)
            (root / "tools").mkdir()
            (root / "bin").mkdir()
            name = "orbit_reload_check.sh" if mode == "orbit" else "check_old_ledger_save.sh"
            src = source or Path(__file__).with_name(name)
            shutil.copyfile(src, root / "tools" / name)
            fake = root / "bin" / "godot"
            fake.write_text(FAKE_GODOT)
            fake.chmod(0o755)
            env = dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                       FAKE_COUNTER=str(root / "counter"), FAKE_MODE=mode,
                       FAKE_STAGE=str(stage), FAKE_FAULT=fault)
            result = subprocess.run(["bash", str(root / "tools" / name)], env=env,
                                    text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
            return result

    def test_normal_markers_pass(self):
        for mode in ("orbit", "legacy"):
            with self.subTest(mode=mode):
                result = self.run_check(mode)
                self.assertEqual(result.returncode, 0, result.stdout)

    def test_every_process_failure_fails_even_after_a_pass_marker(self):
        for mode, stages in (("orbit", (1, 2)), ("legacy", (1, 2, 3, 4))):
            for stage in stages:
                for fault in ("crash", "timeout", "script", "fail"):
                    with self.subTest(mode=mode, stage=stage, fault=fault):
                        result = self.run_check(mode, stage, fault)
                        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_each_required_marker_must_come_from_its_own_phase(self):
        for mode, stages in (("orbit", (1, 2)), ("legacy", (2, 4))):
            for stage in stages:
                for fault in ("missing", "wrong"):
                    with self.subTest(mode=mode, stage=stage, fault=fault):
                        result = self.run_check(mode, stage, fault)
                        self.assertNotEqual(result.returncode, 0, result.stdout)

    def test_write_must_confirm_the_save_reached_disk(self):
        result = self.run_check("orbit", 1, "unsaved")
        self.assertNotEqual(result.returncode, 0, result.stdout)


if __name__ == "__main__":
    unittest.main()
