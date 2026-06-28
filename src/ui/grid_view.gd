class_name GridView
extends Control
## Renders one InventoryGrid: a dark ember-bordered slot per valid cell and a
## placeholder coloured block per placed item (real item art comes later). Also maps
## a local mouse position to a grid cell so the WaveMenu can pick/place. Pure view:
## it reads the grid live and redraws; it never mutates the grid.

const ItemTooltipScript := preload("res://src/ui/item_tooltip.gd")   # shared rarity palette
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")   # per-weapon icon + placeholder colour

const CELL := 44                  # px per cell
const GAP := 2                    # px between cells
const ITEM_INSET := 3.0           # shrink item blocks so the slot grid shows through
const RARITY_BG_ALPHA := 0.30     # translucency of the rarity backing behind non-Normal items

const SLOT_BG := Color(0.05, 0.02, 0.02, 0.9)
const SLOT_BORDER := Color(0.62, 0.22, 0.1)
const LOCKED_BG := Color(0.02, 0.0, 0.0, 0.6)      # dim "not yet unlocked" fill
const LOCKED_BORDER := Color(0.25, 0.12, 0.08)     # dim border + hatch line
const SUBSTRATE_ALPHA := 0.28                       # placed expansions draw faint (a marker, not an item)
const STAR_COLOR := Color(1.0, 0.85, 0.2)          # marks a gun cell buffed by the hovered artifact
const STAR_OUTLINE := Color(0.15, 0.08, 0.0, 0.95)

var grid: Object                  # InventoryGrid; set via setup()
var cell_size := CELL             # px per cell; raised by the menu to scale the grid up crisply
var star_cells: Array = []        # cells to mark with a ★ (guns buffed by the hovered artifact)

static var _icon_cache: Dictionary = {}   # Kind -> Texture2D (or null when no art on disk); shared


## Bind a grid and size the control to span it.
func setup(g: Object) -> void:
	grid = g
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixel-art icons
	custom_minimum_size = _span()
	queue_redraw()


## Re-measure + redraw after the grid's contents change.
func refresh() -> void:
	custom_minimum_size = _span()
	queue_redraw()


## Mark `cells` with a ★ (the menu sets this to the guns a hovered artifact buffs); [] clears.
func set_stars(cells: Array) -> void:
	star_cells = cells
	queue_redraw()


## A filled 5-point star centred in `rect`, with a thin dark outline for contrast.
func _draw_star(rect: Rect2) -> void:
	var c := rect.get_center()
	var ro := rect.size.x * 0.36
	var ri := ro * 0.42
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + float(i) * PI / 5.0
		var r := ro if i % 2 == 0 else ri
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	draw_colored_polygon(pts, STAR_COLOR)
	pts.append(pts[0])
	draw_polyline(pts, STAR_OUTLINE, maxf(1.0, rect.size.x * 0.03))


## Local pixel position -> grid cell (may be outside the mask; caller checks fits()).
func cell_at(local_pos: Vector2) -> Vector2i:
	var step := cell_size + GAP
	return Vector2i(floori(local_pos.x / step), floori(local_pos.y / step))


## Top-left pixel of a cell (local space).
func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell.x, cell.y) * float(cell_size + GAP)


func _draw() -> void:
	if grid == null:
		return
	var inset := ITEM_INSET * float(cell_size) / float(CELL)   # scale the inset with the cell
	# Cell backing: the full field when expandable (locked cells marked), else just valid.
	if grid.has_method("field_cells"):
		for cell in grid.field_cells():
			var r := Rect2(cell_origin(cell), Vector2(cell_size, cell_size))
			if grid.valid.has(cell):
				draw_rect(r, SLOT_BG)
				draw_rect(r, SLOT_BORDER, false, 2.0)
			else:
				draw_rect(r, LOCKED_BG)
				draw_rect(r, LOCKED_BORDER, false, 1.0)
				draw_line(r.position, r.position + r.size, LOCKED_BORDER, 1.0)   # corner hatch = "locked"
	else:
		for cell in grid.valid:
			var r := Rect2(cell_origin(cell), Vector2(cell_size, cell_size))
			draw_rect(r, SLOT_BG)
			draw_rect(r, SLOT_BORDER, false, 2.0)
	# Substrate (extenders) drawn faint, under the content items.
	if grid.has_method("substrate_items"):
		for ext in grid.substrate_items():
			_draw_item(ext, grid.ext_origin[ext], inset, SUBSTRATE_ALPHA)
	# Content items (guns) on top, fully opaque.
	for item in grid.items_in_reading_order():
		_draw_item(item, grid.origin_of[item], inset)
	# Stars over guns buffed by the artifact currently hovered (set via set_stars()).
	for cell in star_cells:
		_draw_star(Rect2(cell_origin(cell), Vector2(cell_size, cell_size)))


## Draw one item (rarity backing, then icon or placeholder colour) at `origin`,
## scaled to `alpha` (1.0 = opaque; faint for placed expansions).
func _draw_item(item: Object, origin: Vector2i, inset: float, alpha := 1.0) -> void:
	var bg := rarity_bg(item)
	if bg.a > 0.0:
		var bgc := Color(bg.r, bg.g, bg.b, bg.a * alpha)
		for c in item.cells():
			draw_rect(Rect2(cell_origin(origin + c), Vector2(cell_size, cell_size)), bgc)
	var tex := icon_for(item)
	if tex != null:
		draw_icon(self, tex, item, cell_origin(origin), cell_size, alpha)
	else:
		var col := color_for(item)
		col.a *= alpha
		for c in item.cells():
			var r := Rect2(cell_origin(origin + c), Vector2(cell_size, cell_size)).grow(-inset)
			draw_rect(r, col)


func _span() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	var cells: Array = grid.field_cells() if grid.has_method("field_cells") else grid.valid.keys()
	var max_c := 0
	var max_r := 0
	for cell in cells:
		max_c = maxi(max_c, cell.x)
		max_r = maxi(max_r, cell.y)
	return Vector2(float(max_c + 1) * (cell_size + GAP), float(max_r + 1) * (cell_size + GAP))


## Placeholder block colour for an item (when it has no icon art), from its catalog
## def. Static so any item view can reuse it.
static func color_for(item: Object) -> Color:
	return WeaponCatalogScript.get_def(item.kind).placeholder_color


## Translucent rarity backing for an item, or fully-transparent for Normal (no tint).
## Uses the shared rarity palette so it matches the tooltip / shop borders. Static so
## it's testable and so any item view can reuse it. (Does NOT touch the drag ghost.)
static func rarity_bg(item: Object) -> Color:
	var rarity: String = item.rarity()
	if rarity == "Normal":
		return Color(0.0, 0.0, 0.0, 0.0)
	var base: Color = ItemTooltipScript.RARITY_COLORS.get(rarity, Color(0.0, 0.0, 0.0, 0.0))
	return Color(base.r, base.g, base.b, RARITY_BG_ALPHA)


## Cached rot-0 icon for an item's kind, or null if no art file exists. Static +
## shared so the drag ghost can reuse it without re-loading.
static func icon_for(item: Object) -> Texture2D:
	var kind: int = item.kind
	if not _icon_cache.has(kind):
		var path: String = WeaponCatalogScript.get_def(kind).icon_path
		_icon_cache[kind] = load(path) if path != "" and ResourceLoader.exists(path) else null
	return _icon_cache[kind]


## Blit an item's rot-0 icon across its pixel bbox with `top_left` at the bbox's
## corner (in `ci`'s local space), spun by its quarter-turn `rot`. The art is
## authored at rot 0; a 90/180/270 turn is an exact (lossless) rotation. Static so
## both the grid (placed items) and the drag ghost draw icons identically.
static func draw_icon(ci: CanvasItem, tex: Texture2D, item: Object, top_left: Vector2, cell_px: int, alpha := 1.0) -> void:
	var bc := 0
	var br := 0
	for c in item.cells():
		bc = maxi(bc, c.x)
		br = maxi(br, c.y)
	bc += 1
	br += 1
	var screen_size := Vector2(float(bc) * cell_px + float(bc - 1) * GAP, float(br) * cell_px + float(br - 1) * GAP)
	var base_size := screen_size if item.rot % 2 == 0 else Vector2(screen_size.y, screen_size.x)
	ci.draw_set_transform(top_left + screen_size * 0.5, float(item.rot) * PI * 0.5, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-base_size * 0.5, base_size), false, Color(1.0, 1.0, 1.0, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
