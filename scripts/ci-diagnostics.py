#!/usr/bin/env python3
"""Record observable failures; do not infer timing or environment root causes."""

import html
import json
import math
import os
from pathlib import Path
import re
import sys
import time


def diagnose(stage, code, text):
    lines = text.splitlines()
    resource = bool(re.search(
        r"(unable to find bundle|missing .*resource bundle|"
        r"Localizable\.strings.*(?:missing|not found)|"
        r"resource_bundle_accessor.*(?:fatal error|error:))", text, re.I))
    unit = next((line for line in lines if re.search(
        r"(?:\.swift:\d+(?::\d+)?:.*(?:XCTAssert|failed|Expectation failed|Issue recorded)|"
        r"Test Case .* failed|[✘].*(?:recorded an issue|failed)|"
        r"Test .+ recorded an issue|Expectation failed:)", line)), None)
    compile_error = next((line for line in lines if re.search(
        r"\.swift:\d+:\d+: (?:fatal )?error:|error: (?:emit-module|compile|fatalError)", line)), None)
    # Prefer a location-bearing assertion to the final aggregate failure line.
    failure = unit or compile_error or next((line for line in lines if re.search(
        r"(?:error:|fatal error:|^FAIL|failed|Error:)", line, re.I)), None)
    if code == 0:
        category = "passed"
    elif unit:
        category = "unit-test"
    elif compile_error:
        category = "compile"
    elif stage == "native":
        category = "native-contract"
    elif stage == "preflight":
        category = "static-contract"
    else:
        category = "unknown"
    return category, (failure or (lines[-1] if lines else "No command output"))[:1500], resource


def resource_diagnostics(root):
    print("SwiftPM resource bundle diagnostics (resource-related failure):")
    build = root / ".build"
    # Bound diagnostics without closing a producer's pipe early under pipefail.
    count = 0
    if build.is_dir():
        for directory, dirs, files in os.walk(build):
            dirs[:] = [d for d in dirs if d not in ("checkouts", "repositories")]
            for name in dirs + files:
                if name == "StatusTrio_StatusTrioCore.bundle" or name == "Localizable.strings":
                    print(Path(directory) / name)
                    count += 1
                    if count == 50:
                        return


def record(stage, code, started, directory):
    directory = Path(directory)
    text = (directory / f"{stage}.log").read_text(errors="replace")
    category, failure, resource = diagnose(stage, code, text)
    data = {
        "stage": stage, "exit_code": code, "classification": category,
        "duration_seconds": round(max(0, time.monotonic() - started), 3),
        "failure": failure if code else "", "resource_failure": resource and code != 0,
        "recorded_at": time.time(),
    }
    temporary = directory / f"{stage}.json.tmp"
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(directory / f"{stage}.json")
    print(f"CI stage {stage}: exit={code}, classification={category}, "
          f"duration={data['duration_seconds']:.3f}s")
    if code:
        print(f"Primary failure: {failure}")
        if resource:
            resource_diagnostics(Path.cwd())


def cell(value):
    return html.escape(str(value)).replace("|", "&#124;").replace("\n", " ").replace("`", "&#96;")


def summary(directory):
    records = []
    warnings = []
    for path in Path(directory).glob("*.json"):
        try:
            data = json.loads(path.read_text())
            for field in ("stage", "classification", "failure"):
                if not isinstance(data[field], str):
                    raise ValueError("invalid diagnostic text")
            for field in ("recorded_at", "duration_seconds", "exit_code"):
                if not isinstance(data[field], (int, float)) or not math.isfinite(data[field]):
                    raise ValueError("invalid diagnostic number")
            records.append(data)
        except (OSError, ValueError, KeyError, TypeError):
            warnings.append(f"Unreadable diagnostic record: {cell(path.name)}; see the original step log.")
    records.sort(key=lambda d: d["recorded_at"])
    job_status = os.environ.get("JOB_STATUS", "unknown")
    job_name = "native" if os.environ.get("CI_DIAGNOSTIC_JOB") == "native" else "verify"
    lines = [f"### {job_name.capitalize()} diagnostics ({cell(job_status)})", "",
             "| Stage | Classification | Exit | Seconds | First failure |",
             "| --- | --- | ---: | ---: | --- |"]
    for d in records:
        lines.append("| " + " | ".join(cell(d[k]) for k in (
            "stage", "classification", "exit_code", "duration_seconds", "failure")) + " |")
    if warnings:
        lines += ["", *warnings]
    if not records:
        lines += ["", "No recorded stages: job stopped before a recorded stage (checkout, toolchain, "
                  "candidate validation, or recovery validation). See the failed step log."]
    elif job_status == "failure" and all(d["exit_code"] == 0 for d in records):
        lines += ["", "Recorded stages passed; an unrecorded workflow step failed. See the failed step log."]
    lines += ["", "Classification describes the observed failure, not its root cause. "
              f"Raw {job_name} logs are retained in the {job_name}-diagnostics artifact."]
    base = os.environ.get("GITHUB_SERVER_URL", "")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run = os.environ.get("GITHUB_RUN_ID", "")
    if base and repo and run:
        lines += ["", f"Run: {cell(base)}/{cell(repo)}/actions/runs/{cell(run)}"]
    output = "\n".join(lines) + "\n"
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    if target:
        with open(target, "a") as handle:
            handle.write(output)
    else:
        print(output, end="")


def timing_summary(path):
    lines = ["### Package build phases", "",
             "| Phase | Seconds | Exit |", "| --- | ---: | ---: |"]
    phases = []
    warnings = []
    if Path(path).is_file():
        for index, line in enumerate(Path(path).read_text(errors="replace").splitlines(), 1):
            try:
                name, seconds, code = line.split("\t")
                if not math.isfinite(float(seconds)):
                    raise ValueError("invalid timing")
                int(code)
            except ValueError:
                warnings.append(f"Unreadable timing row {index}; see the original step log.")
                continue
            phases.append((name, seconds, code))
            lines.append(f"| {cell(name)} | {cell(seconds)} | {cell(code)} |")
    if not phases:
        lines += ["", "No recorded build phases. See the first failed workflow step."]
    if warnings:
        lines += ["", *warnings]
    failed = next((name for name, _, code in phases if int(code)), None)
    if failed:
        category = ("notarization" if "notarization" in failed else
                    "signing" if "codesign" in failed else "package/build")
        lines += ["", f"Observed failure stage: {cell(failed)} ({category})."]
    lines += ["", "Parent phases include child phases; do not add all rows together. "
              "Notarization includes Apple/network wait. Cache transfer and artifact "
              "upload are separate Actions steps. No remote performance gain is "
              "established by these local timings."]
    target = os.environ.get("GITHUB_STEP_SUMMARY")
    output = "\n".join(lines) + "\n"
    if target:
        with open(target, "a") as handle:
            handle.write(output)
    else:
        print(output, end="")


if __name__ == "__main__":
    if sys.argv[1] == "record":
        record(sys.argv[2], int(sys.argv[3]), float(sys.argv[4]), sys.argv[5])
    elif sys.argv[1] == "summary":
        summary(sys.argv[2])
    elif sys.argv[1] == "timings":
        timing_summary(sys.argv[2])
    else:
        raise SystemExit("Expected record or summary")
