---
name: add-item-art
description: Generate, fit, and import a pixel-art inventory icon for a grid item (pistol, etc.). Use when adding or refreshing the art for an InventoryItem so GridView draws a real icon instead of the colored placeholder block. Fits the image to the item's cell footprint (orients + resizes), then imports it into the Godot project.
---

# add-item-art

Turns a pixel-art image into a fitted, imported inventory icon for a grid item.

The grid inventory (`src/inventory/`) stores each item as a set of cells (a shape).
`GridView` draws `res://art/items/<kind>.png` rotated to the item's `rot`, or a
colored block if the file is missing. This skill produces that PNG so it fits the
item's **canonical rot-0 footprint**.

## When to use

- "add art for the pistol", "give the inventory items real icons", "the pistol is
  still a blue block", or adding a brand-new item kind's icon.

## Item shapes (rot-0, canonical)

| kind   | footprint        | bbox | px (44/cell) |
|--------|------------------|------|--------------|
| pistol | `X. / X. / XX`   | 2×3  | 88×132       |

`X` = occupied cell, `.` = must be transparent. The source of truth for cells is
`KINDS` in `process_item_art.py` and `InventoryItem.PISTOL_CELLS`.

## Steps

### 1. Generate the image (PixelLab MCP)

Use a PixelLab MCP tool that makes a single top-down object (e.g.
`create_map_object`), transparent background, sized to the item's bbox ratio
(pistol = 2:3, ~64×96). Prompt for the **pistol**:

> Top-down pixel-art inventory icon of an infernal pistol — bold L-shaped / boot
> silhouette. The gun is rotated so the **barrel and slide point straight UP,
> perfectly vertical (not tilted, not diagonal)**, filling the **entire left edge
> top to bottom**; the **grip and magazine jut out to the lower-RIGHT** as a short
> foot at the base. The whole left column is solid and the bottom row is solid, so
> it reads as a capital **L** — with the **entire top-right area empty and
> transparent**. Grimy demonic hand-cannon: pitted blackened steel, glowing
> ember-orange cracks along the barrel, bone-white grip plate, a tiny hellish rune
> etched on the slide. Dark charred palette, hot ember accents. Transparent
> background, single object, no drop shadow, thick readable silhouette. Portrait 2:3.

Negative prompt (if supported): `diagonal, tilted, angled gun, barrel horizontal,
empty bottom-left corner, centered, gun crossing the middle, drop shadow, background`.

The single most important ask is **barrel straight up** — a side-profile gun drawn
at its natural ~45° lean comes out diagonal and won't fit the L (the fitter rotates
but never flips, and no rotation turns a diagonal into an L). Chirality (grip on the
**right**) matters. Size doesn't have to be exact — step 2 fixes it. Save the PNG
anywhere (e.g. the scratchpad).

### 2. Fit + write into the repo

```sh
python3 .claude/skills/add-item-art/process_item_art.py <SRC.png> --kind pistol
# -> writes art/items/pistol.png at 88×132, oriented to fit the L
```

It tries all 4 rotations, keeps the one whose silhouette best fits the cell mask
(weighted by aspect match), resizes nearest-neighbor, and writes
`art/items/<kind>.png`. Read the printed **fit score** and any **WARN** lines:

- `fit score < 0.6` → the art doesn't match the shape; regenerate (check
  orientation / the empty corner / grip side).
- `opaque pixels land in cells that should be empty` → trim the art's top-right.

Self-test the fitter logic: `python3 .claude/skills/add-item-art/process_item_art.py --selftest`

### 3. Import into Godot

A new PNG needs a `.import` before the game can `load()` it on a cold run:

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --import --path .
# (fallback if --import is unavailable: --headless --editor --quit-after 5)
```

Then `GridView` shows it automatically — no code change. Verify headless:

```sh
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120
```

## Adding a new item kind

1. Add its cells to `KINDS` in `process_item_art.py` (matching the item's
   `*_CELLS` in `src/inventory/inventory_item.gd`).
2. Add `Kind -> "res://art/items/<kind>.png"` to `ITEM_TEXTURE_PATHS` in
   `src/ui/grid_view.gd`.
3. Add a prompt for it above, run steps 1–3.

The fitter and the renderer are both generic over the cell mask — only these two
tables and a prompt are per-kind.
