#!/usr/bin/env python3
"""Measure menu-bar icon alignment from a real Agent Desktop screenshot.

Issue #30: the status-item glyph must sit on the battery-ring centre line, and
that ring must itself sit on the status button's centre. Three centres are
reported independently — never a whole-image alpha centroid (battery progress,
asymmetric volume dots and the top-gap glyph would bias it):

  * container centre  — the status button's AX/diagnostic rect
  * ring centre       — midpoint of the coloured ring's left/right extent
  * symbol centre     — geometric centre of the central glyph's ink bbox

Modes:
  --mode both       ring + central symbol in one composite screenshot
  --mode ring       ring only (use an isolated-ring fixture)
  --mode symbol     central ink bbox only (use an isolated-centre fixture)
  --mode accessory  top-gap accessory ink bbox (bolt / plug)
  --mode ink        any ink that differs from a blank reference (colour-agnostic)

Exit status: 0 when measured (PASS or FAIL in the JSON), 3 when INCONCLUSIVE.
"""

import argparse
import json
import sys

import numpy as np
from PIL import Image

HALF_PX_TOLERANCE = 0.5  # physical pixels, initial acceptance threshold


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int32)


def masks(reg, ink="white"):
    r, g, b = reg[:, :, 0], reg[:, :, 1], reg[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    green = (g > 100) & (g - r > 35) & (g - b > 35) & (mx > 120)
    white = (mx > 200) & (chroma < 45)
    blue = (r < 70) & (b > 150) & (b - r > 100)
    if ink == "white":
        glyph = white
    elif ink == "blue":
        glyph = blue
    else:
        glyph = white | blue
    return green, glyph


def label_components(mask, min_pixels=6):
    h, w = mask.shape
    seen = np.zeros_like(mask, dtype=bool)
    comps = []
    ys, xs = np.where(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if seen[sy, sx]:
            continue
        stack = [(sy, sx)]
        seen[sy, sx] = True
        pixels = []
        while stack:
            y, x = stack.pop()
            pixels.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        stack.append((ny, nx))
        if len(pixels) >= min_pixels:
            xs_c = [p[1] for p in pixels]
            ys_c = [p[0] for p in pixels]
            comps.append({
                "min_x": min(xs_c), "max_x": max(xs_c),
                "min_y": min(ys_c), "max_y": max(ys_c),
                "count": len(pixels),
                "cx": (min(xs_c) + max(xs_c) + 1) / 2.0,
                "cy": (min(ys_c) + max(ys_c) + 1) / 2.0,
            })
    return comps


def fit_circle(xs, ys):
    """Algebraic (Kasa) least-squares circle fit; robust ring centre even when
    the battery progress makes the arc's colour distribution asymmetric."""
    x = np.asarray(xs, dtype=float); y = np.asarray(ys, dtype=float)
    A = np.column_stack([2 * x, 2 * y, np.ones_like(x)])
    b = x * x + y * y
    sol, *_ = np.linalg.lstsq(A, b, rcond=None)
    cx, cy = sol[0], sol[1]
    r = float(np.sqrt(sol[2] + cx * cx + cy * cy))
    # residual-based sanity: points should lie near the fitted circle
    resid = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) - r
    return float(cx), float(cy), r, float(np.sqrt((resid ** 2).mean()))


def ring_extent(green, x0, y0):
    colcount = green.sum(axis=0)
    if colcount.max() < 2:
        return None
    cols = np.where(colcount >= 2)[0]
    rows = np.where(green.sum(axis=1) >= 2)[0]
    if len(cols) == 0 or len(rows) == 0:
        return None
    minx, maxx = int(cols.min()), int(cols.max())
    miny, maxy = int(rows.min()), int(rows.max())
    bbox_cx = (minx + maxx + 1) / 2.0 + x0
    bbox_cy = (miny + maxy + 1) / 2.0 + y0
    center_x, center_y, radius, rms = bbox_cx, bbox_cy, 0.0, -1.0
    gys, gxs = np.where(green)
    if len(gxs) >= 24:
        cx, cy, r, rr = fit_circle(gxs + x0, gys + y0)
        # accept the fit only when points are consistent with a circle
        if rr <= 2.5 and r > 4:
            center_x, center_y, radius, rms = cx, cy, r, rr
    return {
        "min_x": minx + x0, "max_x": maxx + x0,
        "min_y": miny + y0, "max_y": maxy + y0,
        "center_x": center_x, "center_y": center_y,
        "bbox_center_x": bbox_cx,
        "radius": radius, "circleFitRMS": rms,
        "width": maxx - minx + 1, "height": maxy - miny + 1,
    }


def bbox_of_components(comps, x0, y0):
    if not comps:
        return None
    minx = min(c["min_x"] for c in comps) + x0
    maxx = max(c["max_x"] for c in comps) + x0
    miny = min(c["min_y"] for c in comps) + y0
    maxy = max(c["max_y"] for c in comps) + y0
    count = sum(c["count"] for c in comps)
    return {
        "min_x": minx, "max_x": maxx, "min_y": miny, "max_y": maxy,
        "center_x": (minx + maxx + 1) / 2.0,
        "center_y": (miny + maxy + 1) / 2.0,
        "width": maxx - minx + 1, "height": maxy - miny + 1, "count": count,
    }


def pick_center_component(comps, ring, x0, y0):
    """The central glyph is the component nearest the ring's vertical centre,
    preferring the widest; footer dots are below and the top-gap glyph above."""
    if not comps:
        return None
    ring_cy = ((ring["min_y"] + ring["max_y"] + 1) / 2.0) if ring else None
    shifted = []
    for c in comps:
        d = dict(c)
        d["cx"] += x0
        d["cy"] += y0
        d["min_x"] += x0
        d["max_x"] += x0
        d["min_y"] += y0
        d["max_y"] += y0
        shifted.append(d)
    if ring is None:
        # No ring reference: take the widest component (the glyph dominates).
        return max(shifted, key=lambda c: c["max_x"] - c["min_x"])
    inside = [c for c in shifted if ring["min_x"] + 2 <= c["cx"] <= ring["max_x"] - 2]
    pool = inside or shifted
    pool.sort(key=lambda c: (abs(c["cy"] - ring_cy), -(c["max_x"] - c["min_x"])))
    return pool[0]


def annotate(path, button, guides, out_prefix):
    im = Image.open(path).convert("RGB")
    bx0, by0, bw, bh = button
    left, top = max(0, bx0 - 8), max(0, by0 - 4)
    right, bottom = bx0 + bw + 8, by0 + bh + 4
    crop = im.crop((left, top, right, bottom))
    crop.resize((crop.width * 8, crop.height * 8), Image.NEAREST).save(f"{out_prefix}-8x.png")
    crop.save(f"{out_prefix}-crop.png")
    ann = crop.copy()
    px = ann.load()

    def vline(cx, color):
        col = int(round(cx - left))
        if 0 <= col < ann.width:
            for yy in range(ann.height):
                px[col, yy] = color

    for cx, color in guides:
        vline(cx, color)
    ann.save(f"{out_prefix}-annotated.png")


def run_ink_mode(args, img, bx0, by0, bx1, by1):
    if not args.reference:
        print("--mode ink requires --reference", file=sys.stderr)
        return 3
    ref = load(args.reference)
    if ref.shape != img.shape:
        print("reference size mismatch", file=sys.stderr)
        return 3
    reg = img[by0:by1, bx0:bx1]
    refreg = ref[by0:by1, bx0:bx1]
    diff = np.abs(reg - refreg).max(axis=2)
    ink = diff > args.ink_threshold
    ys, xs = np.where(ink)
    container_center_x = (bx0 + bx1) / 2.0
    result = {
        "displayScale": args.scale, "iconSize": args.icon_size, "state": args.state,
        "mode": "ink", "buttonRectPx": [bx0, by0, bx1, by1],
        "containerCenterX": container_center_x, "tolerancePx": args.tolerance_px,
    }
    if len(xs) < 8:
        result.update({"status": "INCONCLUSIVE", "reason": "no ink differs from reference"})
        emit(result, args)
        return 3
    minx, maxx = int(xs.min()) + bx0, int(xs.max()) + bx0
    miny, maxy = int(ys.min()) + by0, int(ys.max()) + by0
    center = (minx + maxx + 1) / 2.0
    offset = center - container_center_x
    result.update({
        "ink": {"min_x": minx, "max_x": maxx, "min_y": miny, "max_y": maxy,
                "width": maxx - minx + 1, "height": maxy - miny + 1, "count": int(len(xs))},
        "inkCenterX": center, "inkOffsetPx": offset, "inkOffsetPt": offset / args.scale,
        "status": "PASS" if abs(offset) <= args.tolerance_px + 1e-9 else "FAIL",
    })
    if args.out_prefix:
        guides = [(container_center_x, (0, 255, 0)), (center, (0, 220, 255))]
        annotate(args.screenshot, (bx0, by0, bx1 - bx0, by1 - by0), guides, args.out_prefix)
        result["images"] = [f"{args.out_prefix}-crop.png", f"{args.out_prefix}-8x.png",
                            f"{args.out_prefix}-annotated.png"]
    emit(result, args)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--screenshot", required=True)
    ap.add_argument("--button-rect", required=True,
                    help="X0,Y0,X1,Y1 physical pixels (exclusive right/bottom)")
    ap.add_argument("--scale", type=float, required=True)
    ap.add_argument("--icon-size", type=float, required=True)
    ap.add_argument("--mode", choices=["both", "ring", "symbol", "accessory", "ink"], default="both")
    ap.add_argument("--reference", default=None, help="blank-reference screenshot for --mode ink")
    ap.add_argument("--ink-threshold", type=float, default=60.0)
    ap.add_argument("--ink", choices=["white", "blue", "auto"], default="auto")
    ap.add_argument("--state", default="auto")
    ap.add_argument("--out-json", default=None)
    ap.add_argument("--out-prefix", default=None)
    ap.add_argument("--tolerance-px", type=float, default=HALF_PX_TOLERANCE)
    ap.add_argument("--container-center-x", type=float, default=None,
                    help="override the container centre used for offsets (sub-pixel)")
    args = ap.parse_args()

    bx0, by0, bx1, by1 = [int(round(float(v))) for v in args.button_rect.split(",")]
    img = load(args.screenshot)
    H, W, _ = img.shape
    bx0, by0 = max(0, bx0), max(0, by0)
    bx1, by1 = min(W, bx1), min(H, by1)
    if bx1 - bx0 < 8 or by1 - by0 < 8:
        print("button rect too small", file=sys.stderr)
        return 3
    reg = img[by0:by1, bx0:bx1]
    if args.mode == "ink":
        return run_ink_mode(args, img, bx0, by0, bx1, by1)
    green, glyph = masks(reg, args.ink)
    ring = ring_extent(green, bx0, by0)
    container_center_x = args.container_center_x if args.container_center_x is not None else (bx0 + bx1) / 2.0

    result = {
        "displayScale": args.scale,
        "iconSize": args.icon_size,
        "state": args.state,
        "mode": args.mode,
        "buttonRectPx": [bx0, by0, bx1, by1],
        "containerCenterX": container_center_x,
        "tolerancePx": args.tolerance_px,
    }
    guides = [(container_center_x, (0, 255, 0))]
    checks = []

    if args.mode in ("both", "ring"):
        if ring is None:
            result.update({"status": "INCONCLUSIVE", "reason": "ring not detected"})
            emit(result, args)
            return 3
        ring_offset = ring["center_x"] - container_center_x
        result["ring"] = ring
        result["ringCenterX"] = ring["center_x"]
        result["ringOffsetPx"] = ring_offset
        result["ringOffsetPt"] = ring_offset / args.scale
        guides.append((ring["center_x"], (255, 0, 0)))
        checks.append(("ring", abs(ring_offset)))

    if args.mode in ("both", "symbol", "accessory"):
        comps = label_components(glyph, min_pixels=6)
        if args.mode == "both":
            chosen = pick_center_component(comps, ring, bx0, by0)
            symbol = None if chosen is None else {
                k: chosen[k] for k in ("min_x", "max_x", "min_y", "max_y", "count")
            }
            if symbol is not None:
                symbol["center_x"] = chosen["cx"]
                symbol["center_y"] = chosen["cy"]
                symbol["width"] = chosen["max_x"] - chosen["min_x"] + 1
                symbol["height"] = chosen["max_y"] - chosen["min_y"] + 1
        else:
            symbol = bbox_of_components(comps, bx0, by0)
        if symbol is None:
            result.update({"status": "INCONCLUSIVE", "reason": "no glyph ink detected"})
            emit(result, args)
            return 3
        symbol_offset = symbol["center_x"] - container_center_x
        result["symbol"] = symbol
        result["symbolCenterX"] = symbol["center_x"]
        result["symbolOffsetPx"] = symbol_offset
        result["symbolOffsetPt"] = symbol_offset / args.scale
        guides.append((symbol["center_x"], (0, 220, 255)))
        checks.append(("glyph", abs(symbol_offset)))

    if args.mode == "both":
        result["symbolToRingOffsetPx"] = result["symbolCenterX"] - result["ringCenterX"]
        result["symbolToRingOffsetPt"] = result["symbolToRingOffsetPx"] / args.scale
        checks.append(("symbolToRing", abs(result["symbolToRingOffsetPx"])))

    result["status"] = "PASS" if all(v <= args.tolerance_px + 1e-9 for _, v in checks) else "FAIL"

    if args.out_prefix:
        annotate(args.screenshot, (bx0, by0, bx1 - bx0, by1 - by0), guides, args.out_prefix)
        result["images"] = [f"{args.out_prefix}-crop.png",
                            f"{args.out_prefix}-8x.png",
                            f"{args.out_prefix}-annotated.png"]
    emit(result, args)
    return 0


def emit(result, args):
    text = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out_json:
        with open(args.out_json, "w") as f:
            f.write(text + "\n")
    print(text)


if __name__ == "__main__":
    sys.exit(main())
