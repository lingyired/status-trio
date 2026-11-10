#!/usr/bin/env python3
"""Measure the Issue #30 menu-bar alignment matrix on a real screen.

One Debug launch, then in-memory render fixtures are switched over a process-
scoped notification so the status item never moves and every state is measured
against a blank reference of the same button region (colour-agnostic; the blue
menu-bar gradient no longer confuses the masks). No settings, battery, radio or
display state is changed.

Usage: python3 scripts/run-menubar-alignment-states.py [--screen 0] [--size 24]
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "dist" / "StatusTrio.app"
EXEC = APP / "Contents" / "MacOS" / "StatusTrio"
STATES = ROOT / "artifacts" / "icon-alignment" / "states"
DIAG = Path("/tmp/status-trio-alignment-diag.json")


def bundle_id():
    branch = subprocess.check_output(
        ["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip()
    suffix = "-".join(p for p in "".join(c if c.isalnum() else "-" for c in branch.lower()).split("-") if p)
    return f"com.lingsmbp.StatusTrio.dev.{suffix}"


def wait_diag(scenario, isolation, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data = json.loads(DIAG.read_text())
            if data.get("scenario") == scenario and data.get("isolation") == isolation:
                return data
        except (json.JSONDecodeError, OSError):
            pass
        time.sleep(0.1)
    return None


def post(bid, pid, fixture):
    subprocess.run(["swift", str(ROOT / "scripts" / "post-alignment-request.swift"), bid, pid, fixture],
                   check=True, stdout=subprocess.DEVNULL)


def screenshot(path, screen):
    time.sleep(0.15)
    subprocess.run(["agent-desktop", "screenshot", "--screen", screen, str(path)],
                   check=True, stdout=subprocess.DEVNULL)


def measure(shot, reference, rect, scale, mode, threshold, out_prefix, state):
    cmd = [sys.executable, str(ROOT / "scripts" / "test-menubar-icon-alignment.py"),
           "--screenshot", str(shot), "--button-rect", ",".join(str(v) for v in rect),
           "--scale", str(scale), "--icon-size", "24", "--mode", mode,
           "--ink-threshold", str(threshold), "--state", state,
           "--out-prefix", str(out_prefix)]
    if reference:
        cmd += ["--reference", str(reference)]
    run = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return json.loads(run.stdout)
    except json.JSONDecodeError:
        return {"status": "INCONCLUSIVE", "stderr": run.stderr[-400:]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", default="0")
    args = ap.parse_args()
    if not EXEC.exists():
        print(f"missing dev app: {EXEC}", file=sys.stderr)
        return 1
    STATES.mkdir(parents=True, exist_ok=True)
    bid = bundle_id()

    subprocess.run(["pkill", "-f", str(EXEC)], check=False)
    time.sleep(0.8)
    if DIAG.exists():
        DIAG.unlink()
    env = dict(os.environ)
    env["STATUS_TRIO_ALIGNMENT_DIAGNOSTICS"] = str(DIAG)
    proc = subprocess.Popen([str(EXEC), "--background-ui-testing", "--alignment-fixture=wifi:blank:24"],
                            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                            start_new_session=True)
    if wait_diag("wifi", "blank") is None:
        print("app did not report geometry", file=sys.stderr)
        proc.kill()
        return 1

    frame = json.loads(subprocess.check_output(
        ["swift", str(ROOT / "scripts" / "menubar-item-frame.swift"), str(proc.pid)], text=True))
    scale = float(frame["mainScale"])
    x, y, w, h = frame["x"], frame["y"], frame["w"], frame["h"]
    rect = [round(x * scale), round(y * scale), round((x + w) * scale), round((y + h) * scale)]

    blank_dir = STATES / "blank"
    blank_dir.mkdir(exist_ok=True)
    reference = blank_dir / "screen.png"
    screenshot(reference, args.screen)

    # (scenario, isolation, ink mode, threshold, analyse?)
    fixtures = [
        ("wifi", "ring", "ink", 60, True),
        ("wifi", "center", "ink", 60, True),
        ("weakWifi", "center", "ink", 60, True),
        ("bluetooth", "center", "ink", 60, True),
        ("inputSource", "center", "ink", 60, True),
        ("charging", "accessory", "ink", 100, True),
        ("plug", "accessory", "ink", 100, True),
        ("animatedWifi", "center", "ink", 60, True),
        ("wifi", "composite", "both", 60, False),
        ("charging", "composite", "both", 60, False),
    ]

    results = []
    for scenario, isolation, mode, threshold, analyse in fixtures:
        name = f"{scenario}-{isolation}"
        outdir = STATES / name
        outdir.mkdir(exist_ok=True)
        post(bid, str(proc.pid), f"{scenario}:{isolation}:24")
        diag = wait_diag(scenario, isolation)
        shot = outdir / "screen.png"
        screenshot(shot, args.screen)
        entry = {"fixture": name, "mode": mode,
                 "imageRectCenterOffset": None if diag is None else diag.get("imageRectCenterOffset"),
                 "overlayFrame": None if diag is None else diag.get("overlayFrame"),
                 "templateFrames": None if diag is None else diag.get("templateFrames")}
        if diag is None:
            entry["status"] = "INCONCLUSIVE"
        elif analyse:
            m = measure(shot, reference, rect, scale, mode, threshold, outdir / "icon", scenario)
            entry.update({"status": m.get("status"), "inkOffsetPx": m.get("inkOffsetPx"),
                          "inkCenterX": m.get("inkCenterX"), "reason": m.get("reason")})
        else:
            entry["status"] = "CAPTURED"
        results.append(entry)
        print(f"[{name}] {json.dumps(entry, ensure_ascii=False)}")

    # symbolToRing = symbol isolation offset - ring isolation offset (same launch,
    # same container centre, so offsets are directly comparable).
    def offset(name):
        for r in results:
            if r["fixture"] == name:
                return r.get("inkOffsetPx")
        return None
    for combo in ("wifi", "weakWifi", "bluetooth", "inputSource", "animatedWifi"):
        ring = offset("wifi-ring")
        sym = offset(f"{combo}-center")
        if ring is not None and sym is not None:
            results.append({"fixture": f"{combo}-symbolToRing",
                            "symbolToRingOffsetPx": sym - ring,
                            "status": "PASS" if abs(sym - ring) <= 0.5 + 1e-9 else "FAIL"})

    (STATES / "summary.json").write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(f"summary: {STATES / 'summary.json'}")
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
