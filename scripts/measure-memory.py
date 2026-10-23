#!/usr/bin/env python3
"""Read-only macOS process footprint sampler. Does not launch or stop the app."""

import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import statistics
import subprocess
import sys
import time


# rusage_info_v4 from the macOS SDK's sys/resource.h. The entire structure is
# needed: libproc writes every field, including ones we do not report.
class RUsageV4(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64) for name in (
            "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups",
            "pageins", "wired_size", "resident_size", "phys_footprint",
            "proc_start_abstime", "proc_exit_abstime", "child_user_time",
            "child_system_time", "child_pkg_idle_wkups", "child_interrupt_wkups",
            "child_pageins", "child_elapsed_abstime", "diskio_bytesread",
            "diskio_byteswritten", "cpu_time_qos_default", "cpu_time_qos_maintenance",
            "cpu_time_qos_background", "cpu_time_qos_utility", "cpu_time_qos_legacy",
            "cpu_time_qos_user_initiated", "cpu_time_qos_user_interactive",
            "billed_system_time", "serviced_system_time", "logical_writes",
            "lifetime_max_phys_footprint", "instructions", "cycles", "billed_energy",
            "serviced_energy", "interval_max_phys_footprint", "runnable_time",
        )
    ]


def read_process(pid):
    if pid <= 0:
        raise ValueError("pid must be positive")
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    library.proc_pid_rusage.restype = ctypes.c_int
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidpath.restype = ctypes.c_int
    usage = RUsageV4()
    if library.proc_pid_rusage(pid, 4, ctypes.byref(usage)) != 0:
        error = ctypes.get_errno()
        raise OSError(error, f"proc_pid_rusage failed for PID {pid}")
    path = ctypes.create_string_buffer(4096)
    if library.proc_pidpath(pid, path, len(path)) <= 0:
        error = ctypes.get_errno()
        raise OSError(error, f"cannot identify executable for PID {pid}")
    if not usage.phys_footprint or not usage.resident_size:
        raise OSError(f"PID {pid} returned no usable memory sample")
    return {
        "pid": pid,
        "executable": path.value.decode(),
        "start_abstime": usage.proc_start_abstime,
        "executable_uuid": bytes(usage.uuid).hex(),
        "footprint_bytes": usage.phys_footprint,
        "rss_bytes": usage.resident_size,
        "lifetime_peak_footprint_bytes": usage.lifetime_max_phys_footprint,
    }


def identity(sample):
    return tuple(sample[key] for key in ("pid", "executable", "start_abstime", "executable_uuid"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("--seconds must be at least 1")
    first = read_process(args.pid)
    samples = []
    started = time.monotonic()
    for index in range(args.seconds):
        time.sleep(max(0, started + index - time.monotonic()))
        sample = read_process(args.pid)
        if identity(sample) != identity(first):
            raise RuntimeError("process identity changed during sampling; discard this run")
        sample["elapsed_seconds"] = time.monotonic() - started
        samples.append(sample)
    # Recheck after sampling, including very short runs.
    if identity(read_process(args.pid)) != identity(first):
        raise RuntimeError("process identity changed after sampling; discard this run")
    report = {
        "sampled_at_utc": datetime.now(timezone.utc).isoformat(),
        "process": first,
        "executable_sha256": hashlib.sha256(Path(first["executable"]).read_bytes()).hexdigest(),
        "sample_count": len(samples),
        "samples": samples,
    }
    for metric in ("footprint_bytes", "rss_bytes"):
        values = [sample[metric] for sample in samples]
        report[metric] = {"median": statistics.median(values), "peak": max(values)}
        report[metric.replace("_bytes", "_mib")] = {
            key: value / (1024 * 1024) for key, value in report[metric].items()
        }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    raw_path = args.output.with_suffix(".vmmap.txt")
    try:
        vmmap = subprocess.run(["/usr/bin/vmmap", "-summary", str(args.pid)],
                               capture_output=True, text=True, timeout=20)
        raw_path.write_text(vmmap.stdout + vmmap.stderr)
        report["vmmap"] = {
            "exit_code": vmmap.returncode,
            "raw_file": str(raw_path.resolve()),
            "image_summary": [line for line in vmmap.stdout.splitlines()
                              if "CG Raster Data" in line or "CG Image" in line],
        }
        if vmmap.returncode:
            report["vmmap"]["diagnostic"] = "vmmap failed; footprint samples remain valid"
    except (OSError, subprocess.TimeoutExpired) as error:
        report["vmmap"] = {"diagnostic": str(error), "image_summary": []}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({key: report[key] for key in ("sample_count", "footprint_mib", "rss_mib")}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        print(f"memory measurement failed: {error}", file=sys.stderr)
        sys.exit(1)
