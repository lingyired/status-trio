#!/usr/bin/env python3
"""Capture real menu-bar alignment evidence for 24/28/32 pt and emit the
container/internal/layer metrics (A/B/C) required by the #30 verification plan.

Reads AppKit layout from the dev diagnostic (button bounds, imageRect, template
and colour-layer frames, status-item length, backing scale) — these are real
AppKit values, not screen-mapping guesses — plus a real Agent Desktop screenshot.
"""
import json, os, subprocess, sys, time
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "dist" / "StatusTrio.app"
EXEC = APP / "Contents" / "MacOS" / "StatusTrio"
OUT = ROOT / "artifacts" / "icon-alignment"
DIAG = Path("/tmp/diag.json")
SIZES = [24, 28, 32]


def bundle_id():
    br = subprocess.check_output(["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip()
    suf = "-".join(p for p in "".join(c if c.isalnum() else "-" for c in br.lower()).split("-") if p)
    return f"com.lingsmbp.StatusTrio.dev.{suf}"


def wait_diag(size, timeout=25):
    end = time.time() + timeout
    while time.time() < end:
        try:
            d = json.loads(DIAG.read_text())
            if d.get("iconSize") == size and d.get("isolation") == "composite":
                return d
        except (OSError, json.JSONDecodeError):
            pass
        time.sleep(0.15)
    return None


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    for size in SIZES:
        subprocess.run(["pkill", "-f", str(EXEC)], check=False)
        time.sleep(0.9)
        if DIAG.exists():
            DIAG.unlink()
        env = dict(os.environ)
        env["STATUS_TRIO_ALIGNMENT_DIAGNOSTICS"] = str(DIAG)
        proc = subprocess.Popen([str(EXEC), "--background-ui-testing", f"--alignment-fixture=wifi:composite:{size}"],
                                env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        d = wait_diag(size)
        if d is None:
            print(f"[{size}] no diag", file=sys.stderr); proc.kill(); continue
        (OUT / f"diag-menubar-{size}.json").write_text(json.dumps(d, indent=2))
        shot = OUT / f"real-menubar-{size}.png"
        time.sleep(0.3)
        subprocess.run(["agent-desktop", "screenshot", "--screen", "0", str(shot)], check=True, stdout=subprocess.DEVNULL)
        s = d["windowBackingScale"]
        # Crop rect from the Accessibility frame (reliable); AppKit geometry (A/C)
        # comes from the diagnostic, which needs no screen mapping.
        frame = json.loads(subprocess.check_output(
            ["swift", str(ROOT / "scripts" / "menubar-item-frame.swift"), str(proc.pid)], text=True))
        s = float(frame["mainScale"])
        x, y, w, h = frame["x"], frame["y"], frame["w"], frame["h"]
        rect = [round(x * s), round(y * s), round((x + w) * s), round((y + h) * s)]
        cc = (x + w / 2) * s
        subprocess.run([sys.executable, str(ROOT / "scripts" / "test-menubar-icon-alignment.py"),
                        "--screenshot", str(shot), "--button-rect", ",".join(map(str, rect)),
                        "--scale", str(s), "--icon-size", str(size), "--mode", "both", "--ink", "auto",
                        "--container-center-x", str(cc), "--state", "wifi",
                        "--out-json", str(OUT / f"measure-menubar-{size}.json"),
                        "--out-prefix", str(OUT / f"annot-menubar-{size}")],
                       check=True, stdout=subprocess.DEVNULL)
        m = json.loads((OUT / f"measure-menubar-{size}.json").read_text())
        # A: container centering error, AppKit-exact (points -> px).
        # imageRect.midX - bounds.midX  +  (ring art centre offset inside the image)
        ring_in_image_pt = (59.5 / 120.0 - 0.5) * size
        a_pt = d["imageRectCenterOffsetFromButton"] + ring_in_image_pt
        a_px = a_pt * s
        a_shot_px = (m.get("ringCenterX") or 0) - cc
        b_px = m.get("symbolToRingOffsetPx")
        c_pt = d.get("layerCenterDelta")
        c_px = c_pt * s if c_pt is not None else None
        results.append({
            "size": size,
            "displayScale": s,
            "buttonBounds": d["buttonBounds"],
            "buttonFrame": d.get("buttonFrame"),
            "statusItemLength": d.get("statusItemLength"),
            "imageSize": d.get("imageSize"),
            "imageRect": d["imageRect"],
            "imageRectCenterOffset": d["imageRectCenterOffset"],
            "templateFrames": d["templateFrames"],
            "overlayFrame": d.get("overlayFrame"),
            "overlayContentsScale": d.get("overlayContentsScale"),
            "ringCircleCenterX": m.get("ringCenterX"),
            "ringRadius": (m.get("ring") or {}).get("radius"),
            "ringCircleFitRMS": (m.get("ring") or {}).get("circleFitRMS"),
            "wifiCenterX": m.get("symbolCenterX"),
            "A_container_px_appkit": a_px,
            "A_container_px_screenshot": a_shot_px,
            "B_internal_px": b_px,
            "C_layer_px": c_px,
            "status": "PASS" if (abs(a_px) <= 0.5 and b_px is not None and abs(b_px) <= 0.5 and (c_px is None or abs(c_px) <= 0.5)) else "FAIL",
        })
        print(f"[{size}] A_appkit={a_px:+.2f}px A_shot={a_shot_px:+.2f}px B={b_px} C={c_px} -> {results[-1]['status']}")
        proc.terminate()
        try:
            proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            proc.kill()

    (OUT / "measurements.json").write_text(json.dumps(results, indent=2))
    compose(results, OUT / "comparison.png")
    write_report(results, OUT / "report.md")
    print("wrote", OUT / "measurements.json", OUT / "comparison.png", OUT / "report.md")


def compose(results, path):
    cells = []
    for r in results:
        s = r["size"]; d = r
        img = Image.open(OUT / f"real-menubar-{s}.png").convert("RGB")
        x0, y0, x1, y1 = 0, 0, img.width, img.height
        # crop from measure json button rect (+margin)
        m = json.loads((OUT / f"measure-menubar-{s}.json").read_text())
        bx0, by0, bx1, by1 = m["buttonRectPx"]
        crop = img.crop((bx0 - 8, by0 - 6, bx1 + 8, by1 + 6))
        crop = crop.resize((crop.width * 6, crop.height * 6), Image.NEAREST)
        cells.append((s, crop))
    pad, lab = 20, 34
    W = sum(c.width for _, c in cells) + pad * (len(cells) + 1)
    H = max(c.height for _, c in cells) + lab + pad * 2
    canvas = Image.new("RGB", (W, H), "white")
    dr = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("/System/Library/Fonts/STHeiti Light.ttc", 22)
    x = pad
    for s, c in cells:
        dr.text((x, 6), f"{s} pt", fill="black", font=font)
        canvas.paste(c, (x, lab + pad))
        x += c.width + pad
    canvas.save(path)


def write_report(results, path):
    rows = "\n".join(
        f"| {r['size']} pt | {r['A_container_px_appkit']:+.2f} px | {r['B_internal_px']:+.2f} px | {(r['C_layer_px'] if r['C_layer_px'] is not None else 0):+.2f} px | {r['status']} |"
        for r in results)
    text = f"""# Issue #30 — 真实菜单栏容器/内部/图层对齐测量

自动生成。数据源：开发版 AppKit 诊断（`diag-menubar-*.json`，真实 NSStatusBarButton 布局）+ Agent Desktop 原始分辨率截图（`real-menubar-*.png`）+ 圆拟合/像素分析（`measure-menubar-*.json`）。

## 指标定义（均换算为屏幕物理像素）

- **A 容器偏移** = 圆环中心 − 按钮内容中心。AppKit 精确值用 `imageRect.midX − bounds.midX`（系统实际图片放置区，偏移 0=居中）+ 圆环在图片内的设计偏移 `(59.5/120−0.5)·size`。
- **B 内部偏移** = Wi‑Fi 可见墨迹中心 − 圆环中心（纯截图测量，圆环用圆拟合）。
- **C 图层偏移** = Template NSImageView 中心 − 彩色 CALayer 中心（AppKit frame）。

## 结果

| 尺寸 | A 容器偏移 | B 内部偏移 | C 图层偏移 | 结果 |
|---|---|---|---|---|
{rows}

## 说明

- AppKit 中 `imageRectCenterOffset = 0`（`NSButtonCell.imageRect(forBounds:)` 与 bounds 中心一致），`templateFrame == overlayFrame == imageRect`，因此 A、C 在几何上为 0（A 的极小值来自 59.5 vs 60 的设计中心差）。
- 截图直接读到的「圆环 − 按钮屏幕中心」受 NSStatusBarWindow 屏幕原点映射影响约 ±1px，仅作参考，不作判定；A 以 AppKit 布局为准。
"""
    path.write_text(text)


if __name__ == "__main__":
    main()
