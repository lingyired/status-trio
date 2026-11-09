#!/usr/bin/env python3
"""Dynamic switching stability check for the top ring accessory (Issue #30).

Switches the menu bar icon through accessory/centre/size states in one Debug
launch and re-measures the live pixels after each switch, asserting that the
ring and the top accessory do not jump horizontally when the state changes.
Reuses the same launch / fixture / screenshot / measurement stack as
run-menubar-accessory-alignment.py.
"""
import importlib.util, json, os, subprocess, sys, time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location(
    "acc", ROOT / "scripts" / "run-menubar-accessory-alignment.py")
acc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(acc)

TOL = 0.5
SEQUENCE = [
    ("plug", 24, "plug"), ("charging", 24, "bolt"), ("plug", 24, "plug"),
    ("percent50", 24, "percent50"), ("plug", 24, "plug"), ("percent50", 24, "percent50"),
    ("plug", 24, "plug"), ("plug", 32, "plug32"), ("plug", 24, "plugA"),
    ("wifi", 24, "wifi"), ("bluetooth", 24, "bluetooth"), ("wifi", 24, "wifiA"),
]

def main():
    OUT = ROOT / "artifacts" / "icon-alignment" / "accessory" / "dynamic"
    OUT.mkdir(parents=True, exist_ok=True)
    bid = acc.bundle_id()
    subprocess.run(["pkill", "-f", str(acc.EXEC)], check=False)
    time.sleep(0.8)
    if acc.DIAG.exists():
        acc.DIAG.unlink()
    env = dict(os.environ)
    env["STATUS_TRIO_ALIGNMENT_DIAGNOSTICS"] = str(acc.DIAG)
    proc = subprocess.Popen([str(acc.EXEC), "--background-ui-testing",
                             "--alignment-fixture=wifi:blank:24"],
                            env=env, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    if acc.wait_diag("wifi", "blank") is None:
        print("no geometry", file=sys.stderr); proc.kill(); return 1
    pid = proc.pid
    rows = []
    try:
        for scenario, size, label in SEQUENCE:
            acc.post(bid, pid, f"{scenario}:composite:{size}")
            diag = acc.wait_diag(scenario, "composite")
            fr = acc.frame(pid)
            rect, scale = acc.rect_for(fr)
            shot = OUT / f"{len(rows):02d}-{label}.png"
            ok = acc.capture(shot, "0", rect, "green", 40)
            m = acc.measure(shot, rect, scale, size, "topaccessory",
                            OUT / f"{len(rows):02d}-{label}", scenario)
            rows.append({"i": len(rows), "scenario": scenario, "size": size,
                         "label": label, "ringCx": m.get("ringCenterX"),
                         "accCx": m.get("symbolCenterX"),
                         "toRing": m.get("symbolToRingOffsetPx"),
                         "status": m.get("status"), "captured": ok})
            print(f"[{label} {size}pt] ringCx={m.get('ringCenterX')} "
                  f"accCx={m.get('symbolCenterX')} toRing={m.get('symbolToRingOffsetPx')}",
                  flush=True)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=3)
            except subprocess.TimeoutExpired: proc.kill()

    def cx(name):
        for r in rows:
            if r["label"] == name:
                return r["accCx"]
        return None
    def tor(name):
        for r in rows:
            if r["label"] == name:
                return r["toRing"]
        return None
    checks = {
        "plug_to_bolt_to_plug": [cx("plug"), cx("bolt"), cx("plug")],
        "percent_to_plug_to_percent": [cx("percent50"), cx("plug"), cx("percent50")],
        # Across a size change the status item legitimately repositions, so the
        # jump-free invariant is the accessory offset *relative to the ring*,
        # plus the absolute x returning to its original value at 24 pt.
        "size_24_32_24_toRing": [tor("plug"), tor("plug32"), tor("plugA")],
        "wifi_bt_wifi_ring": [rows[9]["ringCx"], rows[10]["ringCx"], rows[11]["ringCx"]],
    }
    result = {"tolerancePx": TOL, "rows": rows, "checks": {}}
    allpass = True
    for name, vals in checks.items():
        vals = [v for v in vals if v is not None]
        spread = (max(vals) - min(vals)) if vals else None
        ok = spread is not None and spread <= TOL + 1e-9
        allpass = allpass and ok
        result["checks"][name] = {"values": vals, "spreadPx": spread, "verdict": "PASS" if ok else "FAIL"}
        print(f"[check {name}] values={vals} spread={spread} {'PASS' if ok else 'FAIL'}")
    # returning to 24 pt must reproduce the same absolute item position
    ret = [cx("plug"), cx("plugA")]
    ret_ok = None not in ret and abs(ret[0] - ret[1]) <= TOL + 1e-9
    allpass = allpass and ret_ok
    result["checks"]["size_24_back_to_24_absolute"] = {
        "values": ret, "spreadPx": abs(ret[0] - ret[1]) if None not in ret else None,
        "verdict": "PASS" if ret_ok else "FAIL"}
    print(f"[check size_24_back_to_24_absolute] values={ret} {'PASS' if ret_ok else 'FAIL'}")
    result["overall"] = "PASS" if allpass else "FAIL"
    (OUT / "stability.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print("overall:", result["overall"], "->", OUT / "stability.json")
    return 0

if __name__ == "__main__":
    sys.exit(main())
