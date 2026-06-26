class_name LevelUpMenu
extends CanvasLayer
## Pause overlay shown on level-up. The player manages the grid inventory: left-click
## an item to pick it up (which removes it from its grid — so a pistol pulled out of
## the backpack is unequipped), SPACE rotates the held item, left-click a cell drops it
## where it fits. A stubbed 4-slot UPGRADES strip sits top-left (no picking yet).
## CONTINUE returns any held item, clears the HUD level-up medal, and unpauses.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS), like pause_menu.gd.
##
## Layout is a centered container that scales to ~TARGET_COVERAGE of the viewport:
## every size (grid cell, fonts, spacing) is set natively at base × k, so it stays
## crisp at any scale (no transform/bitmap upscaling) and hit-testing uses real sizes.

const GridViewScript := preload("res://src/ui/grid_view.gd")
const ItemTooltipScript := preload("res://src/ui/item_tooltip.gd")
const DragGhostScript := preload("res://src/ui/drag_ghost.gd")
const UiFxScript := preload("res://src/ui/ui_fx.gd")
const InventorySfxScript := preload("res://src/audio/inventory_sfx.gd")

const DIM := Color(0.02, 0.0, 0.0, 1.0)   # solid near-black: a clean modal backdrop (also hides the frozen HUD banner behind it)
const EMBER := Color(1.0, 0.45, 0.2)
const SOUL := Color(0.2, 0.85, 1.0)       # cyan soul-mote colour (matches the HUD counter)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const PANEL_BG := Color(0.06, 0.02, 0.02, 0.92)
const BTN_BG := Color(0.06, 0.02, 0.02, 0.92)
const DROP_FLASH := Color(1.0, 0.85, 0.55, 0.5)   # warm flash over a freshly-dropped item
const UPGRADE_SLOTS := 4

# Scaling: the centred content is sized to cover this fraction of the viewport's
# limiting dimension (so it fills the screen but keeps its aspect), centred.
const TARGET_COVERAGE := 0.70
const MIN_SCALE := 0.4

# Base (k = 1) sizes; everything is laid out at base × k.
const BASE_CELL := 44
const BASE_TITLE_FONT := 52
const BASE_SOULS_FONT := 30
const BASE_LABEL_FONT := 26
const BASE_BTN_FONT := 30
const BASE_STUB := 64
const BASE_TOOLTIP_FONT := 21
const BASE_BTN_SIZE := Vector2(260, 64)
const BASE_CONTENT_SEP := 18
const BASE_COL_SEP := 48
const BASE_INCOL_SEP := 12
const BASE_STUB_SEP := 10
const DESIGN_FALLBACK := Vector2(680, 600)   # used if the natural size can't be measured

var inventory: Node                 # Inventory; set by Main
var hud: Node                       # Hud (for clear_levelup_medals); set by Main
var stats: Node                     # PlayerStats (for the souls readout); set by Main

var _open := false
var _root: Control
var _content: VBoxContainer         # the centred panel block, scaled to TARGET_COVERAGE
var _columns: HBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _upgrade_row: HBoxContainer
var _title: Label
var _souls_label: Label             # "N SOULS" banked-currency readout under the title
var _section_labels: Array[Label] = []
var _stubs: Array[Panel] = []
var _continue: Button
var _base_natural := Vector2.ZERO   # content's natural size at k = 1, measured once
var _cell_size := BASE_CELL         # current scaled cell size (drives the ghost too)
var _tooltip_font := BASE_TOOLTIP_FONT   # current scaled tooltip body font
var _tooltip: ItemTooltipScript     # hover tooltip for the item under the cursor
var _backpack_view: GridViewScript
var _stash_view: GridViewScript
var _held: Object                   # InventoryItem or null
var _held_from: Object              # InventoryGrid the held item came from
var _held_origin: Vector2i          # where to return it on CONTINUE
var _ghost: DragGhostScript         # follows the cursor while holding (icon + fit tint)
var _sfx: InventorySfxScript        # pick/drop one-shot UI sounds (plays while paused)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11                       # above the pause menu's 10
	visible = false
	_build()


## Pause + show. Idempotent: a second level-up while open is ignored. Rescales to the
## current viewport so it always covers ~TARGET_COVERAGE, centred.
func open(_level: int = 0) -> void:
	if _open:
		return
	_open = true
	_souls_label.text = "%d SOULS" % (stats.souls if stats != null else 0)
	_apply_layout_scale()
	_refresh_views()
	visible = true
	get_tree().paused = true


## Return any held item to where it came from, clear the HUD medal, unpause, hide.
func close() -> void:
	if not _open:
		return
	if _held != null:
		inventory.drop(_held_from, _held, _held_origin)   # never lose a held item (origin is free)
		_end_hold()
	if _tooltip != null:
		_tooltip.hide_tip()
	_open = false
	visible = false
	get_tree().paused = false
	if hud != null and hud.has_method("clear_levelup_medals"):
		hud.clear_levelup_medals()


# --- building ---------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()         # centres the content block on screen
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_content)

	_title = Label.new()
	_title.text = "LEVEL UP"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_title.add_theme_color_override("font_color", EMBER)
	_content.add_child(_title)

	_souls_label = Label.new()
	_souls_label.text = "0 SOULS"
	_souls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_souls_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_souls_label.add_theme_color_override("font_color", SOUL)
	_content.add_child(_souls_label)

	_columns = HBoxContainer.new()
	_columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_columns)

	# Left column: UPGRADES (stub) on top, STASH below.
	_left = VBoxContainer.new()
	_columns.add_child(_left)
	_left.add_child(_section_label("UPGRADES"))
	_upgrade_row = HBoxContainer.new()
	for _i in UPGRADE_SLOTS:
		var s := _stub_slot()
		_stubs.append(s)
		_upgrade_row.add_child(s)
	_left.add_child(_upgrade_row)
	_left.add_child(_section_label("STASH"))
	_stash_view = GridViewScript.new()
	_stash_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stash_view.setup(inventory.stash)
	_left.add_child(_stash_view)

	# Right column: BACKPACK (equipped) + CONTINUE.
	_right = VBoxContainer.new()
	_columns.add_child(_right)
	_right.add_child(_section_label("BACKPACK"))
	_backpack_view = GridViewScript.new()
	_backpack_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_backpack_view.setup(inventory.backpack)
	_right.add_child(_backpack_view)
	_continue = _make_button("CONTINUE", close)
	_right.add_child(_continue)

	# Hover tooltip, on top of everything (above the ghost's z_index 100).
	_tooltip = ItemTooltipScript.new()
	_tooltip.z_index = 200
	_root.add_child(_tooltip)

	# Pick/drop UI sounds (non-visual; plays while the tree is paused).
	_sfx = InventorySfxScript.new()
	add_child(_sfx)

	# Measure the natural size at base scale once, then scale to the viewport.
	_set_sizes(1.0)
	_base_natural = _content.get_combined_minimum_size()
	if _base_natural.x < 1.0 or _base_natural.y < 1.0:
		_base_natural = DESIGN_FALLBACK
	_apply_layout_scale()


## Scale the whole layout so the centred content covers ~TARGET_COVERAGE of the
## viewport's limiting dimension (keeping aspect), then re-centre via the container.
func _apply_layout_scale() -> void:
	if _base_natural.x < 1.0 or _base_natural.y < 1.0:
		return
	var vp := get_viewport().get_visible_rect().size
	var k := TARGET_COVERAGE * minf(vp.x / _base_natural.x, vp.y / _base_natural.y)
	_set_sizes(maxf(k, MIN_SCALE))


## Apply base × k to every size-driving property. Native sizing keeps it crisp.
func _set_sizes(k: float) -> void:
	_cell_size = maxi(8, roundi(BASE_CELL * k))
	_tooltip_font = maxi(13, roundi(BASE_TOOLTIP_FONT * k))   # floor so stats stay readable
	_title.add_theme_font_size_override("font_size", maxi(8, roundi(BASE_TITLE_FONT * k)))
	_souls_label.add_theme_font_size_override("font_size", maxi(8, roundi(BASE_SOULS_FONT * k)))
	for l in _section_labels:
		l.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_LABEL_FONT * k)))
	_continue.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_BTN_FONT * k)))
	_continue.custom_minimum_size = BASE_BTN_SIZE * k
	for s in _stubs:
		s.custom_minimum_size = Vector2(BASE_STUB, BASE_STUB) * k
	_content.add_theme_constant_override("separation", roundi(BASE_CONTENT_SEP * k))
	_columns.add_theme_constant_override("separation", roundi(BASE_COL_SEP * k))
	_left.add_theme_constant_override("separation", roundi(BASE_INCOL_SEP * k))
	_right.add_theme_constant_override("separation", roundi(BASE_INCOL_SEP * k))
	_upgrade_row.add_theme_constant_override("separation", roundi(BASE_STUB_SEP * k))
	_backpack_view.cell_size = _cell_size
	_backpack_view.refresh()
	_stash_view.cell_size = _cell_size
	_stash_view.refresh()


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", EMBER)
	_section_labels.append(l)
	return l


func _stub_slot() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(BASE_STUB, BASE_STUB)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = EMBER_DIM
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BASE_BTN_SIZE
	b.add_theme_color_override("font_color", EMBER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var box := StyleBoxFlat.new()
	box.bg_color = BTN_BG
	box.border_color = EMBER_DIM
	box.set_border_width_all(3)
	box.set_corner_radius_all(5)
	b.add_theme_stylebox_override("normal", box)
	b.pressed.connect(handler)
	return b


# --- interaction ------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open:
		return
	# Swallow ESC while open so the pause menu can't toggle underneath us (CONTINUE-only).
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Only handle/consume clicks that land on a grid; clicks elsewhere must reach the
		# GUI so the CONTINUE button (and any other Control) still receives them.
		if not _view_and_cell(event.position).is_empty():
			_on_click(event.position)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _held != null:
			_update_ghost(event.position)        # dragging: the ghost tracks the cursor
		else:
			_update_tooltip(event.position)      # idle: show the hovered item's stats
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and _held != null:
		_held.rot = (_held.rot + 1) % 4
		_update_ghost(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()    # don't let SPACE also press a focused button


## Pick up the item under the cursor, or — if already holding — try to drop it there.
func _on_click(screen_pos: Vector2) -> void:
	var hit := _view_and_cell(screen_pos)
	if hit.is_empty():
		return
	var grid: Object = hit[1]
	var cell: Vector2i = hit[2]
	if _held == null:
		var it: Object = grid.item_at(cell)
		if it != null:
			_begin_hold(grid, it)
			_update_ghost(screen_pos)
	else:
		var view: Control = hit[0]
		var dropped: Object = _held
		if inventory.drop(grid, _held, cell):     # places + emits changed if it fits
			_sfx.play_drop()
			var rect := _footprint_rect(view, cell, dropped)
			_flash_rect(rect, DROP_FLASH)
			UiFxScript.ring(_root, rect.get_center(), EMBER, _cell_size * 1.5, maxf(3.0, _cell_size * 0.12))
			_end_hold()
			_refresh_views()


## Remove `item` from `grid` and start carrying it (the ghost tracks the cursor).
func _begin_hold(grid: Object, item: Object) -> void:
	_held = item
	_held_from = grid
	_held_origin = grid.origin_of[item]
	if _tooltip != null:
		_tooltip.hide_tip()                       # picked up -> no hover tooltip while dragging
	var center := _footprint_rect(_view_of(grid), _held_origin, item).get_center()
	inventory.pick_up(grid, item)                 # unequips if it was the backpack
	_sfx.play_pick()
	_refresh_views()
	_make_ghost()
	UiFxScript.ring(_root, center, EMBER, _cell_size * 1.5, maxf(3.0, _cell_size * 0.12))


## Show the tooltip for the item under the cursor, or hide it when over empty space.
func _update_tooltip(screen_pos: Vector2) -> void:
	var it: Object = null
	var hit := _view_and_cell(screen_pos)
	if not hit.is_empty():
		it = hit[1].item_at(hit[2])
	if it == null:
		_tooltip.hide_tip()
	else:
		_tooltip.show_for(it, screen_pos, _tooltip_font)


func _end_hold() -> void:
	_held = null
	_held_from = null
	_held_origin = Vector2i.ZERO
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null


## Which view+grid+cell is under `screen_pos`? Returns [view, grid, cell] or [].
func _view_and_cell(screen_pos: Vector2) -> Array:
	for pair in [[_backpack_view, inventory.backpack], [_stash_view, inventory.stash]]:
		var view: Control = pair[0]
		if view.get_global_rect().has_point(screen_pos):
			return [view, pair[1], view.cell_at(screen_pos - view.global_position)]
	return []


func _refresh_views() -> void:
	_backpack_view.refresh()
	_stash_view.refresh()


func _make_ghost() -> void:
	_ghost = DragGhostScript.new()
	_root.add_child(_ghost)
	_ghost.setup(_held, _cell_size)


## Snap the ghost to the hovered cell (green if it fits there, red if not); when off
## any grid, free-float at the cursor. Anchors the item's first cell to the cursor cell.
## The ghost draws the item's icon (spun to its rot) so a rotate is reflected at once.
func _update_ghost(screen_pos: Vector2) -> void:
	if _ghost == null:
		return
	var hit := _view_and_cell(screen_pos)
	var base: Vector2
	var fits := false
	if not hit.is_empty():
		var view: Control = hit[0]
		var grid: Object = hit[1]
		var cell: Vector2i = hit[2]
		base = view.global_position + view.cell_origin(cell)
		fits = grid.fits(_held, cell)
	else:
		base = screen_pos
	_ghost.position = base
	_ghost.set_fit(fits)
	_ghost.queue_redraw()                # reflect a SPACE-rotate (cells/icon change in place)


## A footprint's screen rect, for spawning pickup/drop FX over it.
func _footprint_rect(view: Control, origin: Vector2i, item: Object) -> Rect2:
	var bc := 0
	var br := 0
	for c in item.cells():
		bc = maxi(bc, c.x)
		br = maxi(br, c.y)
	var top_left: Vector2 = view.global_position + view.cell_origin(origin)
	var sz := Vector2(float(bc + 1) * _cell_size + float(bc) * GridViewScript.GAP,
		float(br + 1) * _cell_size + float(br) * GridViewScript.GAP)
	return Rect2(top_left, sz)


func _view_of(grid: Object) -> Control:
	return _backpack_view if grid == inventory.backpack else _stash_view


## A brief bright overlay over `rect` that fades out — the drop "land" flash.
func _flash_rect(rect: Rect2, color: Color) -> void:
	var cr := ColorRect.new()
	cr.process_mode = Node.PROCESS_MODE_ALWAYS
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.z_index = 90
	cr.color = color
	cr.position = rect.position
	cr.size = rect.size
	_root.add_child(cr)
	var tw := cr.create_tween()
	tw.tween_property(cr, "modulate:a", 0.0, 0.32).from(1.0)
	tw.tween_callback(cr.queue_free)
