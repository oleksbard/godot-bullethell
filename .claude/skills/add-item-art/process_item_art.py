#!/usr/bin/env python3
"""Fit a pixel-art icon to an inventory item's cell footprint, then write it into
the repo so GridView can draw it.

Generic over any cell mask. The hard part is orientation: a generator may emit the
art rotated to the side (e.g. the pistol lying horizontal). We don't trust the
input orientation -- we try all 4 rotations and keep the one whose opaque-pixel
silhouette best matches the item's canonical (rot-0) cell mask. For the pistol
that means "make it vertical and fit the L".

Usage:
  process_item_art.py SRC.png --kind pistol [--out art/items/pistol.png] [--cell 44]
  process_item_art.py --selftest

Exit code 0 = imported (warnings are non-fatal and printed). Non-zero = error.
"""
import argparse
import os
import sys
from PIL import Image

CELL = 44  # px per grid cell; mirror of GridView.CELL -- keep in sync

# kind -> occupied cells (col, row), CANONICAL rot-0 footprint. The pistol is an
# L: barrel up the left column, grip foot bottom-right, top-right corner empty.
KINDS = {
    "pistol": [(0, 0), (0, 1), (0, 2), (1, 2)],
}

FIT_WARN = 0.6      # warn if the best orientation scores below this IoU
SPILL_THRESH = 0.30  # a cell counts as "opaque" if its mean alpha exceeds this


def bbox_of(cells):
    cols = max(c for c, _ in cells) + 1
    rows = max(r for _, r in cells) + 1
    return cols, rows


def autocrop_alpha(img):
    """Trim fully-transparent margins so orientation is judged on content, not padding."""
    img = img.convert("RGBA")
    box = img.getchannel("A").getbbox()
    return img if box is None else img.crop(box)


def cell_occupancy(img, cols, rows):
    """Downsample alpha to one value per cell (area-average); return the set of
    cells whose mean alpha clears SPILL_THRESH."""
    alpha = img.convert("RGBA").getchannel("A").resize((cols, rows), Image.Resampling.BOX)
    px = alpha.load()
    occ = set()
    for r in range(rows):
        for c in range(cols):
            if px[c, r] / 255.0 > SPILL_THRESH:
                occ.add((c, r))
    return occ


def iou(a, b):
    if not a and not b:
        return 1.0
    union = len(a | b)
    return len(a & b) / union if union else 0.0


def _aspect_factor(w, h, cols, rows):
    """1.0 when the content's aspect matches the target bbox; <1 the further off.
    Demotes the 90/270 rotations (which squish a sideways image into the grid and
    would otherwise win on an inflated silhouette score)."""
    a = w / h
    t = cols / rows
    return min(a, t) / max(a, t)


def best_orientation(img, cells):
    """Try all 4 rotations; return (score, turns, oriented_img, occupancy) for the
    rotation whose silhouette best fits the target mask. Score = silhouette IoU
    weighted by aspect-ratio match, so we both orient AND fit the shape."""
    cols, rows = bbox_of(cells)
    target = set(cells)
    best = None
    for turns in range(4):
        cand = autocrop_alpha(img.rotate(90 * turns, expand=True, fillcolor=(0, 0, 0, 0)))
        occ = cell_occupancy(cand, cols, rows)
        score = iou(occ, target) * _aspect_factor(cand.width, cand.height, cols, rows)
        if best is None or score > best[0]:
            best = (score, turns, cand, occ)
    return best


def process(src, kind, out, cell=CELL):
    cells = KINDS[kind]
    cols, rows = bbox_of(cells)
    img = autocrop_alpha(Image.open(src))
    score, turns, oriented, occ = best_orientation(img, cells)

    empties = {(c, r) for c in range(cols) for r in range(rows)} - set(cells)
    spill = occ & empties

    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    oriented.resize((cols * cell, rows * cell), Image.Resampling.NEAREST).save(out)

    print(f"  fit score (IoU vs {kind} mask): {score:.2f}  rotated {turns * 90}deg")
    print(f"  written: {out}  ({cols * cell}x{rows * cell}px)")
    if score < FIT_WARN:
        print(f"  WARN: silhouette barely matches the item shape (score {score:.2f} < {FIT_WARN}). "
              f"Regenerate the art -- check the prompt's orientation/empty-corner.")
    if spill:
        print(f"  WARN: opaque pixels land in cells that should be empty: {sorted(spill)}.")
    return score, turns, spill


def _render_mask(cells, s=12):
    """A clean per-cell block image of a mask -- used only by the selftest."""
    cols, rows = bbox_of(cells)
    img = Image.new("RGBA", (cols * s, rows * s), (0, 0, 0, 0))
    px = img.load()
    occ = set(cells)
    for (c, r) in occ:
        for y in range(r * s, (r + 1) * s):
            for x in range(c * s, (c + 1) * s):
                px[x, y] = (200, 80, 30, 255)
    return img


def selftest():
    cells = KINDS["pistol"]
    target = set(cells)

    # An image that already IS the L must score 1.0 at 0 turns.
    correct = _render_mask(cells)
    score, _turns, _img, occ = best_orientation(correct, cells)
    assert occ == target and score == 1.0, (occ, score)

    # The same L rotated to the side must be detected and rotated back to fit.
    for k in (1, 2, 3):
        sideways = correct.rotate(90 * k, expand=True, fillcolor=(0, 0, 0, 0))
        score, _turns, _img, occ = best_orientation(sideways, cells)
        assert occ == target, (k, occ)
        assert score > 0.99, (k, score)

    # A mirrored L is the wrong chirality -- no rotation can make it a perfect fit,
    # so it must never masquerade as one (we rotate, we don't flip).
    mirrored = correct.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    score, _turns, _img, _occ = best_orientation(mirrored, cells)
    assert score < 0.99, score

    print("selftest OK")


def main():
    ap = argparse.ArgumentParser(description="Fit a pixel-art icon to an inventory item shape.")
    ap.add_argument("src", nargs="?", help="source PNG (transparent background)")
    ap.add_argument("--kind", default="pistol", choices=sorted(KINDS))
    ap.add_argument("--out", default=None, help="output path (default art/items/<kind>.png)")
    ap.add_argument("--cell", type=int, default=CELL)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return
    if not args.src:
        ap.error("src PNG is required (or pass --selftest)")

    out = args.out or f"art/items/{args.kind}.png"
    process(args.src, args.kind, out, args.cell)


if __name__ == "__main__":
    main()
