import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import unittest

SPEC = importlib.util.spec_from_file_location("measure_memory", Path(__file__).parents[1] / "measure-memory.py")


class MemoryMeasurementTests(unittest.TestCase):
    def test_current_process_has_nonzero_memory_and_stable_identity(self):
        module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(module)
        first = module.read_process(os.getpid())
        second = module.read_process(os.getpid())
        self.assertGreater(first["footprint_bytes"], 0)
        self.assertGreater(first["rss_bytes"], 0)
        self.assertEqual(module.identity(first), module.identity(second))
        self.assertTrue(Path(first["executable"]).is_file())

    def test_exited_process_is_an_error_not_zero_memory(self):
        module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(module)
        child = subprocess.Popen([sys.executable, "-c", "pass"])
        child.wait()
        with self.assertRaises(OSError):
            module.read_process(child.pid)


if __name__ == "__main__":
    unittest.main()
