#!/usr/bin/env python3
"""Measure the top ring-accessory alignment matrix (plug / bolt / percentage)
against the battery ring on a real menu bar, across icon sizes.

Reuses the existing screenshot + measurement stack (no second preview system):
  * in-memory Debug render fixtures from StatusBarAlignmentDiagnostics;
  * state switched over the process-scoped notification via
    scripts/post-alignment-request.swift;
  * status-item rect from scripts/menubar-item-frame.swift;
  * pixels measured by scripts/test-menubar-icon-alignment.py.

Two independent pixel measurements per size, both in the *same* button rect:
  * ring centre  — green-mask bbox centre of a full-ring fixture (--mode ring);
  * accessory centre — white-mask bbox centre of the accessory fixture
    (--mode accessory). The faint progress-0 track is grey, below the white
    threshold, so only the accessory ink is measured.
`accessory − ring` is then the true "top accessory vs ring" residual, immune to
the desktop colour and to status-window coordinate-mapping uncertainty. (An
empty blank reference is deliberately NOT used: a blank icon is narrower and the
menu bar reflows, shifting neighbours into the measured rect.)

Usage: python3 scripts/run-menubar-accessory-alignment.py [--sizes 24,28,32]
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "dist" / "StatusTrio.app"
EXEC = APP / "Contents" / "MacOS" / "StatusTrio"
OUT = ROOT / "artifacts" / "icon-alignment" / "accessory"
DIAG = Path("/tmp/status-trio-alignment-diag.json")

ACCESSORIES = [
    ("plug", "accessory", "plug"),
    ("charging", "accessory", "bolt"),
    ("percent8", "accessory", "percent-8"),
    ("percent50", "accessory", "percent-50"),
    ("percent100", "accessory", "percent-100"),
]

TOLERANCE_PX = 0.5  # physical pixels


def bundle_id():
    branch = subprocess.check_output(
        ["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip()
    suffix = "-".join(p for p in "".join(
        c if c.isalnum() else "-" for c in branch.lower()).split("-") if p)
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
    subprocess.run(
        ["swift", str(ROOT / "scripts" / "post-alignment-request.swift"),
         bid, str(pid), fixture],
        check=True, stdout=subprocess.DEVNULL)


def frame(pid):
    return json.loads(subprocess.check_output(
        ["swift", str(ROOT / "scripts" / "menubar-item-frame.swift"), str(pid)], text=True))


def rect_for(fr):
    s = float(fr["mainScale"])
    x, y, w, h = fr["x"], fr["y"], fr["w"], fr["h"]
    return [round(x * s), round(y * s), round((x + w) * s), round((y + h) * s)], s


def ink_count(path, rect, kind):
    """Count green (ring) or white (accessory) pixels inside rect; guards that a
    screenshot actually captured the requested state before it is measured."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(int)
    bx0, by0, bx1, by1 = rect
    sub = im[max(0, by0):by1, max(0, bx0):bx1]
    r, g, b = sub[:, :, 0], sub[:, :, 1], sub[:, :, 2]
    if kind == "green":
        mask = (g > 100) & (g - r > 35) & (g - b > 35)
    else:
        mx, mn = sub.max(2), sub.min(2)
        mask = (mx > 200) & ((mx - mn) < 45)
    return int(mask.sum())


def capture(shot, screen, rect, kind, min_ink, attempts=6):
    for _ in range(attempts):
        time.sleep(0.35)
        subprocess.run(["agent-desktop", "screenshot", "--screen", screen, str(shot)],
                       check=True, stdout=subprocess.DEVNULL)
        if kind is None or ink_count(shot, rect, kind) >= min_ink:
            return True
    return False


def measure(shot, rect, scale, icon_size, mode, out_prefix, state):
    cmd = [sys.executable, str(ROOT / "scripts" / "test-menubar-icon-alignment.py"),
           "--screenshot", str(shot),
           "--button-rect", ",".join(str(v) for v in rect),
           "--scale", str(scale), "--icon-size", str(icon_size),
           "--mode", mode, "--state", state,
           "--tolerance-px", str(TOLERANCE_PX)]
    if out_prefix:
        cmd += ["--out-prefix", str(out_prefix)]
    run = subprocess.run(cmd, capture_output=True, text=True)
    try:
        return json.loads(run.stdout)
    except json.JSONDecodeError:
        return {"status": "INCONCLUSIVE", "stderr": run.stderr[-400:]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screen", default="0")
    ap.add_argument("--sizes", default="24,28,32")
    ap.add_argument("--pid", default=None)
    args = ap.parse_args()
    sizes = [float(s) for s in args.sizes.split(",") if s.strip()]
    if not EXEC.exists():
        print(f"missing dev app: {EXEC}", file=sys.stderr)
        return 1
    OUT.mkdir(parents=True, exist_ok=True)
    bid = bundle_id()

    proc = None
    if args.pid:
        pid = int(args.pid)
    else:
        subprocess.run(["pkill", "-f", str(EXEC)], check=False)
        time.sleep(0.8)
        if DIAG.exists():
            DIAG.unlink()
        env = dict(os.environ)
        env["STATUS_TRIO_ALIGNMENT_DIAGNOSTICS"] = str(DIAG)
        proc = subprocess.Popen(
            [str(EXEC), "--background-ui-testing",
             f"--alignment-fixture=wifi:blank:{int(sizes[0])}"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True)
        if wait_diag("wifi", "blank") is None:
            print("app did not report geometry", file=sys.stderr)
            proc.kill()
            return 1
        pid = proc.pid

    summary = {"branch": subprocess.check_output(
        ["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip(),
        "tolerancePx": TOLERANCE_PX, "sizes": {}}

    try:
        for size in sizes:
            isz = int(size)
            size_dir = OUT / f"{isz}pt"
            size_dir.mkdir(exist_ok=True)
            rec = {"size": size, "fixtures": {}}

            # One composite screenshot per accessory: ring + centre glyph +
            # accessory + footer. The ring (green) and the top accessory
            # (white) are measured from the SAME image, so their coordinate
            # mapping cancels and only the true accessory-vs-ring residual
            # remains.
            for scenario, _, label in ACCESSORIES:
                post(bid, pid, f"{scenario}:composite:{isz}")
                diag = wait_diag(scenario, "composite")
                fr = frame(pid)
                rect, scale = rect_for(fr)
                shot = size_dir / f"{label}.png"
                ok = capture(shot, args.screen, rect, "green", 40)
                m = measure(shot, rect, scale, isz, "topaccessory",
                            size_dir / label, scenario)
                to_ring = m.get("symbolToRingOffsetPx")
                rec["fixtures"][label] = {
                    "status": m.get("status"),
                    "accessoryCenterX": m.get("symbolCenterX"),
                    "ringCenterX": m.get("ringCenterX"),
                    "toRingPx": to_ring,
                    "toRingPt": None if to_ring is None else to_ring / scale,
                    "inkWidth": (m.get("symbol") or {}).get("width"),
                    "inkHeight": (m.get("symbol") or {}).get("height"),
                    "capturedGreen": ok,
                    "overlayFrame": None if diag is None else diag.get("overlayFrame"),
                    "imageRectCenterOffset": None if diag is None else diag.get("imageRectCenterOffset"),
                    "verdict": ("PASS" if to_ring is not None
                                and abs(to_ring) <= TOLERANCE_PX + 1e-9 else "FAIL"),
                }
                print(f"[{isz}pt {label}] accCx={m.get('symbolCenterX')} "
                      f"ringCx={m.get('ringCenterX')} toRing={to_ring} captured={ok} "
                      f"verdict={rec['fixtures'][label]['verdict']}", flush=True)

            summary["sizes"][f"{isz}pt"] = rec
            (size_dir / "measure.json").write_text(
                json.dumps(rec, indent=2, ensure_ascii=False) + "\n")

        (OUT / "summary.json").write_text(
            json.dumps(summary, indent=2, ensure_ascii=False) + "\n")
        print(f"summary: {OUT / 'summary.json'}")
    finally:
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
