import fcntl
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "measure-memory-lifecycle.swift"
HARNESS = ROOT / "scripts" / "tests" / "memory-lifecycle-window-harness.swift"
PHASE_MARKER = ROOT / "scripts" / "tests" / "memory-lifecycle-phase-marker.swift"
PHASE_MARKER_MAIN = ROOT / "scripts" / "tests" / "memory-lifecycle-phase-marker-main.swift"
SWIFT_LOCK = (
    ROOT
    / ".superpowers"
    / "sdd"
    / "2026-10-20-memory-lifecycle-optimization"
    / "swift.lock"
)
WINDOW_HARNESS_ENABLED = os.environ.get("STATUS_TRIO_ENABLE_WINDOW_HARNESS_TESTS") == "1"


def wait_for_path(path, timeout=3):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if path.exists():
            return
        time.sleep(0.01)
    raise AssertionError(f"timed out waiting for {path}")


def compile_swift(sources, destination, definitions=()):
    SWIFT_LOCK.parent.mkdir(parents=True, exist_ok=True)
    with SWIFT_LOCK.open("a+") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return subprocess.run(
            [
                "swiftc",
                "-target",
                f"{platform.machine()}-apple-macosx13.0",
                *[f"-D{definition}" for definition in definitions],
                *map(str, sources),
                "-o",
                str(destination),
            ],
            capture_output=True,
            text=True,
        )


class MemoryLifecycleToolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory()
        cls.binary = Path(cls.tempdir.name) / "measure-memory-lifecycle"
        cls.harness_binary = Path(cls.tempdir.name) / "memory-lifecycle-window-harness"
        cls.phase_marker_binary = Path(cls.tempdir.name) / "phase-marker-test"
        cls.compile_error = None
        if not SCRIPT.is_file() or not PHASE_MARKER.is_file() or not PHASE_MARKER_MAIN.is_file():
            cls.compile_error = (
                f"Swift source does not exist: {SCRIPT}, {PHASE_MARKER}, or {PHASE_MARKER_MAIN}"
            )
            return

        tool_result = compile_swift(
            [SCRIPT],
            cls.binary,
            definitions=("MEMORY_LIFECYCLE_TEST_HOOKS",),
        )
        if tool_result.returncode:
            cls.compile_error = (
                f"tool swiftc exited {tool_result.returncode}\n"
                f"stdout:\n{tool_result.stdout}\n"
                f"stderr:\n{tool_result.stderr}"
            )
            return

        phase_result = compile_swift(
            [PHASE_MARKER, PHASE_MARKER_MAIN],
            cls.phase_marker_binary,
        )
        if phase_result.returncode:
            cls.compile_error = (
                f"phase marker swiftc exited {phase_result.returncode}\n"
                f"stdout:\n{phase_result.stdout}\n"
                f"stderr:\n{phase_result.stderr}"
            )
            return

        if WINDOW_HARNESS_ENABLED:
            harness_result = compile_swift(
                [PHASE_MARKER, HARNESS],
                cls.harness_binary,
            )
            if harness_result.returncode:
                cls.compile_error = (
                    f"harness swiftc exited {harness_result.returncode}\n"
                    f"stdout:\n{harness_result.stdout}\n"
                    f"stderr:\n{harness_result.stderr}"
                )

    @classmethod
    def tearDownClass(cls):
        cls.tempdir.cleanup()

    def setUp(self):
        if self.compile_error:
            self.fail(self.compile_error)

    def run_tool(self, *arguments, timeout=10):
        return subprocess.run(
            [str(self.binary), *map(str, arguments)],
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    def test_invalid_arguments_fail_without_output(self):
        cases = [
            [],
            ["--pid", "0", "--seconds", "0.2", "--interval-ms", "100"],
            ["--pid", "1", "--seconds", "0", "--interval-ms", "100"],
            ["--pid", "1", "--seconds", "0.2", "--interval-ms", "99"],
            ["--pid", "1", "--seconds", "0.2", "--interval-ms", "1001"],
            ["--pid", "not-a-pid", "--seconds", "0.2", "--interval-ms", "100"],
        ]
        missing_output = self.run_tool(
            "--pid", "1", "--seconds", "0.2", "--interval-ms", "100"
        )
        self.assertNotEqual(missing_output.returncode, 0)
        self.assertIn("usage:", missing_output.stderr.lower())

        for index, arguments in enumerate(cases):
            with self.subTest(arguments=arguments):
                output = Path(self.tempdir.name) / f"invalid-{index}.jsonl"
                command = list(arguments)
                command.extend(["--output", str(output)])
                result = self.run_tool(*command)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("usage:", result.stderr.lower())
                self.assertFalse(output.exists())

    def test_nonexistent_pid_fails_without_output(self):
        output = Path(self.tempdir.name) / "missing.jsonl"
        result = self.run_tool(
            "--pid",
            "999999",
            "--seconds",
            "0.2",
            "--interval-ms",
            "100",
            "--output",
            output,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("PID 999999", result.stderr)
        self.assertFalse(output.exists())

    def test_exited_pid_fails_without_output(self):
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        child.wait()
        output = Path(self.tempdir.name) / "exited.jsonl"
        result = self.run_tool(
            "--pid",
            child.pid,
            "--seconds",
            "0.2",
            "--interval-ms",
            "100",
            "--output",
            output,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"PID {child.pid}", result.stderr)
        self.assertFalse(output.exists())

    def test_process_exiting_during_sampling_fails_without_output(self):
        child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(0.35)"])
        output = Path(self.tempdir.name) / "early-exit.jsonl"
        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "0.8",
                "--interval-ms",
                "100",
                "--output",
                output,
            )
        finally:
            child.wait(timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_refuses_to_overwrite_existing_output(self):
        output = Path(self.tempdir.name) / "existing.jsonl"
        original = '{"source":"prior-run"}\n'
        output.write_text(original, encoding="utf-8")
        result = self.run_tool(
            "--pid",
            os.getpid(),
            "--seconds",
            "0.2",
            "--interval-ms",
            "100",
            "--output",
            output,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("already exists", result.stderr.lower())
        self.assertEqual(output.read_text(encoding="utf-8"), original)

    def test_exclusive_publication_preserves_concurrently_created_output(self):
        target = subprocess.Popen(["/bin/sleep", "2"])
        output = Path(self.tempdir.name) / "publication-race.jsonl"
        competitor = '{"source":"competing-creator"}\n'
        process = subprocess.Popen(
            [
                str(self.binary),
                "--pid",
                str(target.pid),
                "--seconds",
                "0.8",
                "--interval-ms",
                "100",
                "--output",
                str(output),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            deadline = time.monotonic() + 3
            temporary_outputs = []
            while time.monotonic() < deadline:
                temporary_outputs = list(
                    output.parent.glob(f".{output.name}.*.tmp")
                )
                if temporary_outputs:
                    break
                time.sleep(0.005)
            self.assertEqual(len(temporary_outputs), 1)

            output.write_text(competitor, encoding="utf-8")
            stdout, stderr = process.communicate(timeout=4)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            target.kill()
            target.wait(timeout=3)

        self.assertNotEqual(process.returncode, 0, stdout)
        self.assertIn("renameatx_np", stderr.lower())
        self.assertIn("file exists", stderr.lower())
        self.assertEqual(output.read_text(encoding="utf-8"), competitor)
        self.assertFalse(any(output.parent.glob(f".{output.name}.*.tmp")))

    def test_process_identity_change_fails_without_output(self):
        child = subprocess.Popen(
            [
                "/bin/sh",
                "-c",
                "sleep 0.35; exec /bin/sleep 2",
            ]
        )
        output = Path(self.tempdir.name) / "identity-change.jsonl"
        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "0.8",
                "--interval-ms",
                "100",
                "--output",
                output,
            )
        finally:
            child.kill()
            child.wait(timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exec", result.stderr.lower())
        self.assertFalse(output.exists())

    def test_same_binary_reexec_fails_without_output(self):
        child = subprocess.Popen(
            [
                "/bin/sh",
                "-c",
                "sleep 0.35; exec /bin/sh -c 'sleep 2'",
            ]
        )
        output = Path(self.tempdir.name) / "same-path-reexec.jsonl"
        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "0.8",
                "--interval-ms",
                "100",
                "--output",
                output,
            )
        finally:
            child.kill()
            child.wait(timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exec", result.stderr.lower())
        self.assertFalse(output.exists())

    def test_same_binary_reexec_at_registration_handshake_fails_without_output(self):
        registration_ready = Path(self.tempdir.name) / "registration-ready"
        registration_release = Path(self.tempdir.name) / "registration-release"
        child = subprocess.Popen(
            [
                "/bin/sh",
                "-c",
                (
                    f"while [ ! -e {registration_ready} ]; do sleep 0.01; done; "
                    f"exec /bin/sh -c '/usr/bin/touch {registration_release}; sleep 2'"
                ),
            ]
        )
        output = Path(self.tempdir.name) / "registration-handshake.jsonl"
        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "0.2",
                "--interval-ms",
                "100",
                "--output",
                output,
                "--test-registration-ready",
                registration_ready,
                "--test-registration-release",
                registration_release,
            )
        finally:
            child.kill()
            child.wait(timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exec", result.stderr.lower())
        self.assertFalse(output.exists())

    def test_exec_before_final_validation_boundary_fails_without_output(self):
        boundary_ready = Path(self.tempdir.name) / "final-boundary-ready"
        boundary_release = Path(self.tempdir.name) / "final-boundary-release"
        child = subprocess.Popen(
            [
                "/bin/sh",
                "-c",
                (
                    f"while [ ! -e {boundary_ready} ]; do sleep 0.01; done; "
                    f"exec /bin/sh -c '/usr/bin/touch {boundary_release}; sleep 2'"
                ),
            ]
        )
        output = Path(self.tempdir.name) / "before-final-boundary.jsonl"
        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "0.2",
                "--interval-ms",
                "100",
                "--output",
                output,
                "--test-before-final-boundary-ready",
                boundary_ready,
                "--test-before-final-boundary-release",
                boundary_release,
            )
        finally:
            child.kill()
            child.wait(timeout=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("exec", result.stderr.lower())
        self.assertFalse(output.exists())
        self.assertFalse(any(output.parent.glob(f".{output.name}.*.tmp")))

    def test_post_boundary_exec_and_path_replacement_do_not_revalidate_or_cleanup(self):
        publication_ready = Path(self.tempdir.name) / "publication-ready"
        publication_release = Path(self.tempdir.name) / "publication-release"
        exec_complete = Path(self.tempdir.name) / "target-exec-complete"
        child = subprocess.Popen(
            [
                "/bin/sh",
                "-c",
                (
                    f"while [ ! -e {publication_ready} ]; do sleep 0.01; done; "
                    "exec /bin/sh -c '"
                    f"/usr/bin/touch {exec_complete}; "
                    f"while [ ! -e {publication_release} ]; do sleep 0.01; done; "
                    "sleep 2'"
                ),
            ]
        )
        output = Path(self.tempdir.name) / "accepted-publication.jsonl"
        competitor = '{"source":"post-boundary-replacement"}\n'
        process = subprocess.Popen(
            [
                str(self.binary),
                "--pid",
                str(child.pid),
                "--seconds",
                "0.2",
                "--interval-ms",
                "100",
                "--output",
                str(output),
                "--test-after-publication-ready",
                str(publication_ready),
                "--test-after-publication-release",
                str(publication_release),
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            wait_for_path(publication_ready)
            wait_for_path(exec_complete)
            self.assertTrue(output.is_file())

            replacement = output.with_name("post-boundary-replacement")
            replacement.write_text(competitor, encoding="utf-8")
            os.replace(replacement, output)
            publication_release.write_text("release\n", encoding="utf-8")
            stdout, stderr = process.communicate(timeout=5)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=3)
            child.kill()
            child.wait(timeout=3)

        self.assertEqual(process.returncode, 0, stderr)
        self.assertIn(f"samples=3 output={output}", stdout)
        self.assertEqual(output.read_text(encoding="utf-8"), competitor)
        self.assertFalse(any(output.parent.glob(f".{output.name}.*.tmp")))

    def test_stable_target_emits_monotonic_identity_and_memory_samples(self):
        child = subprocess.Popen(["/bin/sleep", "2"])
        output = Path(self.tempdir.name) / "stable.jsonl"
        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "0.4",
                "--interval-ms",
                "100",
                "--output",
                output,
            )
        finally:
            child.kill()
            child.wait(timeout=3)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(output.is_file())
        samples = [
            json.loads(line)
            for line in output.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        self.assertGreaterEqual(len(samples), 4)

        timestamps = [sample["timestamp"] for sample in samples]
        elapsed = [sample["elapsed"] for sample in samples]
        self.assertEqual(timestamps, sorted(timestamps))
        self.assertEqual(elapsed, sorted(elapsed))
        self.assertEqual(len(set(timestamps)), len(timestamps))
        self.assertAlmostEqual(elapsed[0], 0.0, places=2)

        identities = {
            (
                sample["pid"],
                sample["executablePath"],
                sample["executableUUID"],
                sample["startAbstime"],
            )
            for sample in samples
        }
        self.assertEqual(len(identities), 1)
        for sample in samples:
            self.assertEqual(sample["pid"], child.pid)
            self.assertTrue(Path(sample["executablePath"]).is_file())
            self.assertNotEqual(sample["observer"]["pid"], sample["pid"])
            self.assertTrue(Path(sample["observer"]["executablePath"]).is_file())
            self.assertGreater(sample["footprintBytes"], 0)
            self.assertGreater(sample["rssBytes"], 0)
            self.assertGreater(sample["lifetimePeakFootprintBytes"], 0)
            self.assertGreaterEqual(sample["visibleWindowCount"], 0)
            self.assertNotIn("windowTitle", sample)
            self.assertNotIn("windowContent", sample)

    @unittest.skipUnless(
        WINDOW_HARNESS_ENABLED,
        "set STATUS_TRIO_ENABLE_WINDOW_HARNESS_TESTS=1 to run the desktop window probe",
    )
    def test_native_harness_records_expand_six_second_close_and_reopen(self):
        phase_log = Path(self.tempdir.name) / "window-phases.jsonl"
        output = Path(self.tempdir.name) / "window-cycles.jsonl"
        child = subprocess.Popen([str(self.harness_binary), str(phase_log)])
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            if phase_log.is_file() and phase_log.read_text(encoding="utf-8"):
                break
            time.sleep(0.02)
        self.assertTrue(phase_log.is_file() and phase_log.read_text(encoding="utf-8"))

        try:
            result = self.run_tool(
                "--pid",
                child.pid,
                "--seconds",
                "8.8",
                "--interval-ms",
                "100",
                "--output",
                output,
                timeout=12,
            )
        finally:
            child.terminate()
            try:
                child.wait(timeout=3)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait(timeout=3)

        self.assertEqual(result.returncode, 0, result.stderr)
        raw = output.read_text(encoding="utf-8")
        self.assertNotIn("privacy-canary-window-title", raw)
        self.assertFalse(output.with_name(f".{output.name}.1.tmp").exists())
        samples = [json.loads(line) for line in raw.splitlines() if line.strip()]
        phases = {
            item["phase"]: item["timestamp"]
            for item in (
                json.loads(line)
                for line in phase_log.read_text(encoding="utf-8").splitlines()
                if line.strip()
            )
        }
        self.assertEqual(set(phases), {"launch", "first-expand", "close", "reopen"})
        self.assertGreaterEqual(phases["reopen"] - phases["close"], 5.9)

        by_phase = {}
        for phase, start_key, end_key in [
            ("first-expand", "first-expand", "close"),
            ("closed", "close", "reopen"),
            ("reopened", "reopen", float("inf")),
        ]:
            phase_end = phases[end_key] if end_key != float("inf") else float("inf")
            phase_samples = [
                sample
                for sample in samples
                if phases[start_key] <= sample["timestamp"] < phase_end
            ]
            self.assertGreater(len(phase_samples), 2)
            by_phase[phase] = {
                "sample_count": len(phase_samples),
                "visible_window_counts": sorted(
                    {sample["visibleWindowCount"] for sample in phase_samples}
                ),
                "footprint_peak_mib": max(
                    sample["footprintMiB"] for sample in phase_samples
                ),
                "rss_peak_mib": max(sample["rssMiB"] for sample in phase_samples),
            }

        self.assertEqual(by_phase["first-expand"]["visible_window_counts"], [1])
        self.assertEqual(by_phase["closed"]["visible_window_counts"], [0])
        self.assertEqual(by_phase["reopened"]["visible_window_counts"], [1])
        for phase in by_phase.values():
            self.assertGreater(phase["footprint_peak_mib"], 0)
            self.assertGreater(phase["rss_peak_mib"], 0)

    @unittest.skipUnless(
        WINDOW_HARNESS_ENABLED,
        "set STATUS_TRIO_ENABLE_WINDOW_HARNESS_TESTS=1 to run the desktop window probe",
    )
    def test_native_harness_phase_write_failure_is_nonzero(self):
        unwritable = Path(self.tempdir.name) / "unwritable"
        unwritable.mkdir()
        unwritable.chmod(0o500)
        phase_log = unwritable / "phases.jsonl"
        try:
            result = subprocess.run(
                [str(self.harness_binary), str(phase_log)],
                capture_output=True,
                text=True,
                timeout=5,
            )
        finally:
            unwritable.chmod(0o700)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot write phase log", result.stderr.lower())

    def test_launch_marker_publication_failure_is_nonzero_without_gui(self):
        existing_directory = Path(self.tempdir.name) / "phase-log-directory"
        existing_directory.mkdir()
        result = subprocess.run(
            [str(self.phase_marker_binary), str(existing_directory)],
            capture_output=True,
            text=True,
            timeout=5,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cannot write phase log", result.stderr.lower())


if __name__ == "__main__":
    unittest.main()
