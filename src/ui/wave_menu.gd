class_name WaveMenu
extends CanvasLayer
## Pause overlay shown between waves (opened once the cleared wave's souls have flown in —
## XpOrbField.drained). The player manages the grid inventory: left-click an item to pick it
## up (which removes it from its grid — so a pistol pulled out of the backpack is unequipped),
## SPACE rotates the held item, left-click a cell drops it where it fits. A 5-slot SHOP sits
## top-left. CONTINUE returns any held item, clears the HUD level-up medal, emits `closed`
## (Main resumes the spawner), and unpauses.
## Runs while the tree is paused (PROCESS_MODE_ALWAYS), like pause_menu.gd.
##
## Layout is a centered container that scales to ~TARGET_COVERAGE of the viewport:
## every size (grid cell, fonts, spacing) is set natively at base × k, so it stays
## crisp at any scale (no transform/bitmap upscaling) and hit-testing uses real sizes.

signal closed()                  # CONTINUE pressed -> Main tells the spawner to resume

const GridViewScript := preload("res://src/ui/grid_view.gd")
const ItemTooltipScript := preload("res://src/ui/item_tooltip.gd")
const DragGhostScript := preload("res://src/ui/drag_ghost.gd")
const UiFxScript := preload("res://src/ui/ui_fx.gd")
const InventorySfxScript := preload("res://src/audio/inventory_sfx.gd")
const InventoryItemScript := preload("res://src/inventory/inventory_item.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")
const ArtifactResolverScript := preload("res://src/artifacts/artifact_resolver.gd")
const RecapViewScript := preload("res://src/ui/recap_view.gd")
const LOCK_TEX: Texture2D = preload("res://art/ui/lock.svg")

const DIM := Color(0.02, 0.0, 0.0, 1.0)   # solid near-black: a clean modal backdrop (also hides the frozen HUD banner behind it)
const EMBER := Color(1.0, 0.45, 0.2)
const SOUL := Color(0.2, 0.85, 1.0)       # cyan soul-mote colour (matches the HUD counter)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const PANEL_BG := Color(0.06, 0.02, 0.02, 0.92)
const BTN_BG := Color(0.06, 0.02, 0.02, 0.92)
const DROP_FLASH := Color(1.0, 0.85, 0.55, 0.5)   # warm flash over a freshly-dropped item
const SHOP_SLOTS := 5                              # rolled offers per wave
const ARTIFACT_OFFER_CHANCE := 0.35              # chance a rolled slot is a (wave-gated) artifact
const EXPANSION_OFFER_CHANCE := 0.25              # chance a rolled slot is an expansion (else a weapon)
const ARTIFACT_BORDER := Color(0.7, 0.45, 0.9)    # purple offer border for artifacts
const UNAFFORDABLE := Color(0.7, 0.35, 0.3)        # price colour when you can't afford it
const SOLD_DIM := Color(0.5, 0.5, 0.5, 0.8)        # icon tint for an unaffordable offer
const SELL_HI := Color(0.45, 1.0, 0.55)            # sell-zone accent (green = you get paid)
const DENY := Color(1.0, 0.3, 0.3, 0.5)           # flash over an extender that can't be picked up (gun on it)

# Scaling: the centred content is sized to cover this fraction of the viewport's
# limiting dimension (so it fills the screen but keeps its aspect), centred.
const TARGET_COVERAGE := 0.70
const MIN_SCALE := 0.4

# Base (k = 1) sizes; everything is laid out at base × k.
const BASE_CELL := 44
const BASE_TITLE_FONT := 52
const BASE_SOULS_FONT := 30
const BASE_POWER_FONT := 28
const BASE_PRICE_FONT := 22
const BASE_LABEL_FONT := 26
const BASE_BTN_FONT := 30
const BASE_STUB := 64
const BASE_SELL := Vector2(180, 52)   # sell drop-zone base size
const BASE_TOOLTIP_FONT := 21
const BASE_BTN_SIZE := Vector2(260, 64)
const BASE_LOCK_FONT := 16
const REROLL_GROWTH := 3                            # per-reroll cost multiplier within a wave
const REROLL_BASE_FRACTION := 0.02                  # base reroll cost = this fraction of total souls collected
const BASE_REROLL_SIZE := Vector2(220, 40)          # reroll button base size (k = 1)
const BASE_CONTENT_SEP := 18
const BASE_COL_SEP := 48
const BASE_INCOL_SEP := 12
const BASE_STUB_SEP := 10
const DESIGN_FALLBACK := Vector2(680, 600)   # used if the natural size can't be measured

var inventory: Node                 # Inventory; set by Main
var hud: Node                       # Hud (for clear_levelup_medals); set by Main
var stats: Node                     # PlayerStats (for the souls readout); set by Main
var tracker: Node                   # CombatTracker (set by Main); feeds the RECAP tab
var current_wave := 1               # set by Main (wave_started); gates which artifact tiers can roll

var _open := false
var _root: Control
var _content: VBoxContainer         # the centred panel block, scaled to TARGET_COVERAGE
var _columns: HBoxContainer
var _left: VBoxContainer
var _right: VBoxContainer
var _shop_row: HBoxContainer
var _title: Label
var _souls_label: Label             # "N SOULS" banked-currency readout under the title
var _power_label: Label             # "LOADOUT POWER N" — sum of equipped pistols' power
var _section_labels: Array[Label] = []
var _offer_buttons: Array[Button] = []   # the 5 shop offer slots
var _offer_icons: Array[TextureRect] = []
var _offer_prices: Array[Label] = []
var _offer_locks: Array[Button] = []   # per-slot lock toggles
var _offers: Array = []             # per-slot {item, price, sold, locked}
var _reroll_btn: Button
var _reroll_count := 0                  # rerolls used this wave (resets in open())
var _rng := RandomNumberGenerator.new()  # rolls offers (tests can seed it)
var _sell_zone: Panel               # drag an owned item here to sell it for 65%
var _sell_label: Label
var _continue: Button
var _base_natural := Vector2.ZERO   # content's natural size at k = 1, measured once
var _cell_size := BASE_CELL         # current scaled cell size (drives the ghost too)
var _tooltip_font := BASE_TOOLTIP_FONT   # current scaled tooltip body font
var _tooltip: ItemTooltipScript     # hover tooltip for the item under the cursor
var _tab := "shop"                  # active tab: "recap" | "shop" (shop is the default on open)
var _tab_row: HBoxContainer
var _recap_btn: Button
var _shop_btn: Button
var _recap_view: RecapViewScript
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
	_rng.randomize()
	_build()


## Pause + show. Idempotent: a re-open while already open is ignored. Rescales to the
## current viewport so it always covers ~TARGET_COVERAGE, centred. (arg-less so it can
## bind straight to WaveSpawner.wave_cleared.)
func open(_wave: int = 0) -> void:
	if _open:
		return
	if _wave > 0:
		current_wave = _wave         # else keep what Main set via wave_started
	_open = true
	_souls_label.text = "%d SOULS" % (stats.souls if stats != null else 0)
	_reroll_count = 0
	_roll_offers()                   # fresh shop offers, rolled off the player's level + luck
	_apply_layout_scale()
	_refresh_views()                 # also refreshes the loadout-power readout
	_refresh_reroll()
	_tab = "shop"
	_show_tab()
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
	closed.emit()                    # Main -> spawner.resume_after_menu (breather, then next wave)


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
	_title.text = "WAVE CLEARED"
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

	_power_label = Label.new()
	_power_label.text = "LOADOUT POWER 0"
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_power_label.add_theme_color_override("font_color", EMBER)
	_content.add_child(_power_label)

	_tab_row = HBoxContainer.new()
	_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_recap_btn = _make_tab("RECAP", func() -> void: _set_tab("recap"))
	_shop_btn = _make_tab("SHOP", func() -> void: _set_tab("shop"))
	_tab_row.add_child(_recap_btn)
	_tab_row.add_child(_shop_btn)
	_content.add_child(_tab_row)

	_columns = HBoxContainer.new()
	_columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_columns)

	_recap_view = RecapViewScript.new()
	_recap_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_recap_view.visible = false
	_content.add_child(_recap_view)

	# Left column: SHOP (5 rolled offers) on top, STASH below.
	_left = VBoxContainer.new()
	_columns.add_child(_left)
	_left.add_child(_section_label("SHOP"))
	_shop_row = HBoxContainer.new()
	for i in SHOP_SLOTS:
		_shop_row.add_child(_offer_slot(i))
	_left.add_child(_shop_row)
	_reroll_btn = _make_button("REROLL", _reroll)
	_reroll_btn.custom_minimum_size = BASE_REROLL_SIZE
	_reroll_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_left.add_child(_reroll_btn)
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
	_sell_zone = _make_sell_zone()
	_right.add_child(_sell_zone)
	_style_sell(false)
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
	_power_label.add_theme_font_size_override("font_size", maxi(8, roundi(BASE_POWER_FONT * k)))
	for l in _section_labels:
		l.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_LABEL_FONT * k)))
	_continue.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_BTN_FONT * k)))
	_continue.custom_minimum_size = BASE_BTN_SIZE * k
	if _reroll_btn != null:
		_reroll_btn.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_BTN_FONT * k * 0.7)))
		_reroll_btn.custom_minimum_size = BASE_REROLL_SIZE * k
	for b in _offer_buttons:
		b.custom_minimum_size = Vector2(BASE_STUB, BASE_STUB) * k
	for p in _offer_prices:
		p.add_theme_font_size_override("font_size", maxi(7, roundi(BASE_PRICE_FONT * k)))
	for lk in _offer_locks:
		lk.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_LOCK_FONT * k)))
		lk.custom_minimum_size = Vector2(BASE_STUB * k, 0)
	_sell_zone.custom_minimum_size = BASE_SELL * k
	_sell_label.add_theme_font_size_override("font_size", maxi(6, roundi(BASE_LABEL_FONT * k)))
	_content.add_theme_constant_override("separation", roundi(BASE_CONTENT_SEP * k))
	_columns.add_theme_constant_override("separation", roundi(BASE_COL_SEP * k))
	_left.add_theme_constant_override("separation", roundi(BASE_INCOL_SEP * k))
	_right.add_theme_constant_override("separation", roundi(BASE_INCOL_SEP * k))
	_shop_row.add_theme_constant_override("separation", roundi(BASE_STUB_SEP * k))
	_backpack_view.cell_size = _cell_size
	_backpack_view.refresh()
	_stash_view.cell_size = _cell_size
	_stash_view.refresh()
	for b in [_recap_btn, _shop_btn]:
		if b != null:
			b.add_theme_font_size_override("font_size", maxi(10, roundi(BASE_LABEL_FONT * k)))
	_tab_row.add_theme_constant_override("separation", roundi(BASE_INCOL_SEP * k))
	if _recap_view != null:
		_recap_view.set_scale_k(k)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", EMBER)
	_section_labels.append(l)
	return l


## A shop offer slot: a clickable icon button bordered in its rarity colour, with the
## soul price on its own line beneath (legible at any scale). Buying is wired through
## the button's `pressed` -> _buy(index).
func _offer_slot(index: int) -> Control:
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var b := Button.new()
	b.custom_minimum_size = Vector2(BASE_STUB, BASE_STUB)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.clip_contents = true
	b.pressed.connect(_buy.bind(index))
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 3
	icon.offset_top = 3
	icon.offset_right = -3
	icon.offset_bottom = -3
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	col.add_child(b)

	var price := Label.new()
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.add_theme_color_override("font_color", SOUL)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(price)

	var lock := Button.new()
	lock.toggle_mode = true
	lock.text = "LOCK"
	lock.icon = LOCK_TEX
	lock.expand_icon = true
	lock.focus_mode = Control.FOCUS_NONE
	lock.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lock.custom_minimum_size = Vector2(BASE_STUB, 0)
	lock.toggled.connect(_on_lock_toggled.bind(index))
	col.add_child(lock)
	_offer_locks.append(lock)
	_style_lock(lock, false)

	_offer_buttons.append(b)
	_offer_icons.append(icon)
	_offer_prices.append(price)
	_style_offer(b, EMBER_DIM)
	return col


## Toggle the lock on offer `index` (the toggle's `toggled(pressed)` signal binds index).
func _on_lock_toggled(pressed: bool, index: int) -> void:
	if index >= _offers.size() or _offers[index] == null:
		return
	_offers[index]["locked"] = pressed
	_style_lock(_offer_locks[index], pressed)
	_refresh_reroll()


## Tint + border a lock toggle by its locked state.
func _style_lock(btn: Button, locked: bool) -> void:
	var col := EMBER if locked else EMBER_DIM
	btn.add_theme_color_override("font_color", col)
	btn.add_theme_color_override("font_hover_color", EMBER)
	btn.add_theme_color_override("icon_normal_color", col)
	btn.add_theme_color_override("icon_pressed_color", EMBER)
	btn.add_theme_color_override("icon_hover_color", EMBER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = col
	sb.set_border_width_all(2 if locked else 1)
	sb.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, sb)


## Border an offer button in `border` across all its visual states.
func _style_offer(b: Button, border: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = PANEL_BG
		sb.border_color = border
		sb.set_border_width_all(3 if state == "hover" else 2)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override(state, sb)


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


## A RECAP/SHOP toggle button in the ember style.
func _make_tab(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE                # no stray focus box; active state is the toggle
	b.add_theme_color_override("font_color", EMBER_DIM)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _tab_box(false))
	b.add_theme_stylebox_override("hover", _tab_box(false))
	b.add_theme_stylebox_override("pressed", _tab_box(true))
	b.add_theme_stylebox_override("hover_pressed", _tab_box(true))
	b.pressed.connect(handler)
	return b


## Tab button background: a filled ember-bordered box when active, a faint outline when not.
func _tab_box(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG if active else Color(0.0, 0.0, 0.0, 0.0)
	sb.border_color = EMBER if active else EMBER_DIM
	sb.set_border_width_all(2 if active else 1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 7
	sb.content_margin_bottom = 7
	return sb


## Switch the active tab and re-show.
func _set_tab(tab: String) -> void:
	_tab = tab
	_show_tab()


## Show the active tab's content (recap vs shop) and sync the toggle states. The recap
## tab feeds the view the just-cleared wave's stats; the shop tab restores the columns.
func _show_tab() -> void:
	if _recap_view == null:
		return
	var recap := _tab == "recap"
	_recap_view.visible = recap
	_columns.visible = not recap
	_power_label.visible = not recap
	_recap_btn.button_pressed = recap
	_shop_btn.button_pressed = not recap
	if recap and tracker != null:
		_recap_view.show_stats(tracker.last_wave, inventory.backpack if inventory != null else null)


# --- interaction ------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open:
		return
	# Swallow ESC while open so the pause menu can't toggle underneath us (CONTINUE-only).
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Holding an item and clicking the sell zone -> sell it for 65%.
		if _held != null and _sell_zone.get_global_rect().has_point(event.position):
			_sell_held()
			get_viewport().set_input_as_handled()
			return
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
			if grid.has_method("can_pick_up") and not grid.can_pick_up(it):
				var view: Control = hit[0]
				var rect := Rect2(view.global_position + view.cell_origin(cell), Vector2(_cell_size, _cell_size))
				_flash_rect(rect, DENY)
				return
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
	_backpack_view.set_stars([])                   # no artifact-buff stars while dragging
	_held = item
	_held_from = grid
	_held_origin = grid.origin_for(item)         # extenders live in a separate layer (not origin_of)
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
	if _tab != "shop":
		_tooltip.hide_tip()                      # RECAP tab has no shop items -> no tooltips
		return
	var it: Object = null
	var price := -1                              # owned -> sell price; shop offer -> buy price
	var is_buy := false
	var mods: Object = null                      # gun: its resolved artifact buffs (colours stats)
	var icons: Array = []                        # gun: icons of the artifacts buffing it
	var hit := _view_and_cell(screen_pos)
	_backpack_view.set_stars([])                 # clear last frame's stars; re-set below if hovering an artifact
	if not hit.is_empty():
		var grid: Object = hit[1]
		it = grid.item_at(hit[2])
		if it != null:
			price = it.sell_price()
			if grid == inventory.backpack:       # artifact context only applies inside the backpack
				var full: Dictionary = ArtifactResolverScript.resolve_full(inventory.backpack)
				if it.is_artifact():
					_show_artifact_stars(it, full)
				elif it.item_type == WeaponDefScript.ItemType.GUN:
					mods = full["mods"].get(it)
					icons = _artifact_icons(full["by_gun"].get(it, []))
	else:
		var oi := _offer_index_at(screen_pos)
		if oi >= 0:
			it = _offers[oi]["item"]
			price = int(_offers[oi]["price"])
			is_buy = true
	if it == null:
		_tooltip.hide_tip()
	else:
		_tooltip.show_for(it, screen_pos, _tooltip_font, price, is_buy, mods, icons)


## Star each gun that the hovered `artifact` buffs, on the gun cell touching the artifact
## (or the gun's origin cell for a global/relayed buff).
func _show_artifact_stars(artifact: Object, full: Dictionary) -> void:
	var cells: Array = []
	for gun in full["by_artifact"].get(artifact, []):
		cells.append(_star_cell_for_gun(artifact, gun))
	_backpack_view.set_stars(cells)


## The gun cell to mark: one 4-adjacent to the artifact's footprint, else the gun's origin.
func _star_cell_for_gun(artifact: Object, gun: Object) -> Vector2i:
	var art_cells: Dictionary = {}
	var ao: Vector2i = inventory.backpack.origin_for(artifact)
	for c in artifact.cells():
		art_cells[ao + c] = true
	var go: Vector2i = inventory.backpack.origin_for(gun)
	var dirs := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	for c in gun.cells():
		var gc: Vector2i = go + c
		for d in dirs:
			if art_cells.has(gc + d):
				return gc
	return go


## Icons of the `artifacts` buffing a gun (drops any that have no art).
func _artifact_icons(artifacts: Array) -> Array:
	var out: Array = []
	for a in artifacts:
		var tex: Texture2D = GridViewScript.icon_for(a)
		if tex != null:
			out.append(tex)
	return out


func _end_hold() -> void:
	_held = null
	_held_from = null
	_held_origin = Vector2i.ZERO
	if _ghost != null:
		_ghost.queue_free()
		_ghost = null
	_style_sell(false)


## Which view+grid+cell is under `screen_pos`? Returns [view, grid, cell] or [].
func _view_and_cell(screen_pos: Vector2) -> Array:
	# Only the SHOP tab has grids; on the RECAP tab the columns are hidden (their views
	# keep stale rects), so skip them — otherwise a tab/recap click is swallowed here
	# as a phantom grid click and never reaches the tab buttons.
	if _columns != null and not _columns.visible:
		return []
	for pair in [[_backpack_view, inventory.backpack], [_stash_view, inventory.stash]]:
		var view: Control = pair[0]
		if view.get_global_rect().has_point(screen_pos):
			return [view, pair[1], view.cell_at(screen_pos - view.global_position)]
	return []


func _refresh_views() -> void:
	_backpack_view.refresh()
	_stash_view.refresh()
	_update_loadout_power()


## Refresh the LOADOUT POWER readout from the currently-equipped pistols.
func _update_loadout_power() -> void:
	if _power_label == null:
		return
	var p: int = inventory.loadout_power() if inventory != null else 0
	_power_label.text = "LOADOUT POWER %d" % p


# --- shop -------------------------------------------------------------------

## Current reroll cost: max(1, 2% of lifetime souls) tripled per reroll already done this wave.
func reroll_cost() -> int:
	var total: int = stats.total_souls if stats != null else 0
	var base: int = maxi(1, roundi(REROLL_BASE_FRACTION * float(total)))
	return base * int(pow(float(REROLL_GROWTH), float(_reroll_count)))


## Spend souls to re-roll every non-locked slot (sold ones return as fresh items),
## preserving the composition guarantees, and raise the next reroll's cost.
func _reroll() -> void:
	if not _open:
		return
	var cost := reroll_cost()
	if stats == null or stats.souls < cost:
		return
	stats.spend_souls(cost)
	var free: Array = []
	for i in SHOP_SLOTS:
		var o: Variant = _offers[i]
		if o == null or not o.get("locked", false):
			free.append(i)
	_fill_offers(free)
	_reroll_count += 1
	_souls_label.text = "%d SOULS" % stats.souls
	_refresh_reroll()
	_refresh_views()
	_sfx.play_drop()
	var center := _reroll_btn.get_global_rect().get_center()
	UiFxScript.ring(_root, center, SOUL, _cell_size * 1.5, maxf(3.0, _cell_size * 0.12))


## Repaint the reroll button: show the live cost; disable when unaffordable or when
## every slot is locked (nothing to reroll).
func _refresh_reroll() -> void:
	if _reroll_btn == null:
		return
	var cost := reroll_cost()
	_reroll_btn.text = "REROLL  %d" % cost
	var any_free := false
	for o in _offers:
		if o != null and not o.get("locked", false):
			any_free = true
			break
	var affordable: bool = stats != null and stats.souls >= cost
	_reroll_btn.disabled = not (affordable and any_free)


## Re-roll the shop: keep locked+unsold slots (re-pricing them), fill the rest fresh.
func _roll_offers() -> void:
	if _offers.size() != SHOP_SLOTS:
		_offers.resize(SHOP_SLOTS)
	var free: Array = []
	for i in SHOP_SLOTS:
		var o: Variant = _offers[i]
		if o != null and o.get("locked", false) and not o.get("sold", false):
			_refresh_offer(i)                      # keep locked+unsold; just re-price
		else:
			free.append(i)
	_fill_offers(free)


## Fill the `free` slot indices with fresh offers, guaranteeing (across ALL slots,
## counting the kept/locked ones) >=1 gun, >=1 expander when the backpack still has a
## locked cell, and no duplicate artifact kinds. Slots not in `free` are left as-is.
func _fill_offers(free: Array) -> void:
	var has_gun := false
	var has_expander := false
	var used_artifacts: Dictionary = {}
	for i in SHOP_SLOTS:                            # survey what the kept slots already cover
		if free.has(i):
			continue
		var o: Variant = _offers[i]
		if o == null:
			continue
		var it: Object = o["item"]
		if it == null:
			continue
		if it.is_artifact():
			used_artifacts[it.kind] = true
		elif it.item_type == WeaponDefScript.ItemType.EXPANSION:
			has_expander = true
		else:
			has_gun = true
	var can_expand: bool = inventory != null and not inventory.backpack.locked_cells().is_empty()
	var items: Array = []
	if not has_gun and items.size() < free.size():
		items.append(_roll_gun())
	if can_expand and not has_expander and items.size() < free.size():
		items.append(_roll_expander())
	while items.size() < free.size():
		items.append(_roll_any(used_artifacts))
	for j in free.size():
		var idx: int = free[j]
		var item: Object = items[j]
		_offers[idx] = {"item": item, "price": _offer_price(item), "sold": false, "locked": false}
		_refresh_offer(idx)


## A leveled gun offer (random weapon kind).
func _roll_gun() -> Object:
	var player_level: int = stats.level if stats != null else 1
	var rb: float = stats.rarity_bonus if stats != null else 0.0
	var wk: Array = WeaponCatalogScript.weapon_kinds()
	return InventoryItemScript.rolled_weapon(wk[_rng.randi_range(0, wk.size() - 1)], player_level, rb, _rng)


## An inventory-expander offer (random expansion kind).
func _roll_expander() -> Object:
	var ek: Array = WeaponCatalogScript.expansion_kinds()
	return InventoryItemScript.for_kind(ek[_rng.randi_range(0, ek.size() - 1)])


## A random pool offer that avoids duplicating an artifact kind already in the shop;
## falls back to a gun if every eligible artifact is taken.
func _roll_any(used_artifacts: Dictionary) -> Object:
	for _attempt in 6:
		var item := _roll_offer_item()
		if item.is_artifact():
			if used_artifacts.has(item.kind):
				continue
			used_artifacts[item.kind] = true
		return item
	return _roll_gun()


## Roll one offer item from the combined pool: a wave-gated artifact (ARTIFACT_OFFER_CHANCE),
## an expansion (EXPANSION_OFFER_CHANCE, only when the backpack can still grow), or a
## leveled weapon. Arg-less (existing tests call it directly).
func _roll_offer_item() -> Object:
	var player_level: int = stats.level if stats != null else 1
	var rb: float = stats.rarity_bonus if stats != null else 0.0
	var can_expand: bool = inventory != null and not inventory.backpack.locked_cells().is_empty()
	var r := _rng.randf()
	var artifacts: Array = WeaponCatalogScript.kinds_for_wave(current_wave)
	if not artifacts.is_empty() and r < ARTIFACT_OFFER_CHANCE:
		return InventoryItemScript.for_kind(_weighted_artifact(artifacts))
	if can_expand and r < ARTIFACT_OFFER_CHANCE + EXPANSION_OFFER_CHANCE:
		var ek: Array = WeaponCatalogScript.expansion_kinds()
		return InventoryItemScript.for_kind(ek[_rng.randi_range(0, ek.size() - 1)])
	var wk: Array = WeaponCatalogScript.weapon_kinds()
	return InventoryItemScript.rolled_weapon(wk[_rng.randi_range(0, wk.size() - 1)], player_level, rb, _rng)


## Weight-roll an artifact kind from `pool` by its tier weight (rarer tiers less likely).
func _weighted_artifact(pool: Array) -> int:
	var total := 0
	for k in pool:
		total += WeaponCatalogScript.tier_weight(WeaponCatalogScript.get_def(k).tier)
	var pick := _rng.randi_range(1, maxi(1, total))
	var acc := 0
	for k in pool:
		acc += WeaponCatalogScript.tier_weight(WeaponCatalogScript.get_def(k).tier)
		if pick <= acc:
			return k
	return pool[0]


## An expansion's price escalates with how many you own; a weapon uses its buy price.
func _offer_price(item: Object) -> int:
	if item.item_type == WeaponDefScript.ItemType.EXPANSION:
		return inventory.expansion_price(item.kind)
	return item.buy_price()


## Paint offer slot `index`: icon, price, rarity border, and affordable/sold state.
func _refresh_offer(index: int) -> void:
	var offer: Dictionary = _offers[index]
	var icon := _offer_icons[index]
	var price := _offer_prices[index]
	var btn := _offer_buttons[index]
	var lock: Button = _offer_locks[index]
	var locked: bool = offer.get("locked", false)
	lock.set_pressed_no_signal(locked)             # programmatic set must not re-emit toggled
	lock.disabled = offer.get("sold", false)       # can't lock a sold slot
	_style_lock(lock, locked)
	if offer["sold"]:
		icon.texture = null
		price.text = "SOLD"
		price.add_theme_color_override("font_color", EMBER_DIM)
		btn.disabled = true
		_style_offer(btn, EMBER_DIM)
		return
	var item: Object = offer["item"]
	offer["price"] = _offer_price(item)          # live: expansions re-price as the owned count changes
	var affordable: bool = stats != null and stats.souls >= int(offer["price"])
	icon.texture = GridViewScript.icon_for(item)
	icon.modulate = Color.WHITE if affordable else SOLD_DIM
	price.text = "%d" % int(offer["price"])
	price.add_theme_color_override("font_color", SOUL if affordable else UNAFFORDABLE)
	btn.disabled = false
	var border: Color = ItemTooltipScript.RARITY_COLORS.get(item.rarity(), EMBER)
	if item.is_artifact():
		border = ARTIFACT_BORDER
	elif item.item_type == WeaponDefScript.ItemType.EXPANSION:
		border = EMBER_DIM
	_style_offer(btn, border)


## Try to buy offer `index`: needs souls + stash room. Spends souls, drops the item
## into the stash (drag it to the backpack to equip), and marks the slot sold.
func _buy(index: int) -> void:
	if not _open or index >= _offers.size():
		return
	var offer: Dictionary = _offers[index]
	if offer["sold"] or offer["item"] == null:
		return
	var price: int = int(offer["price"])
	if stats == null or stats.souls < price:
		return                                   # can't afford (price already shows red)
	if not inventory.add_to_stash(offer["item"]):
		return                                   # stash full -> no-op
	stats.spend_souls(price)
	offer["sold"] = true
	offer["locked"] = false                        # buying clears the lock
	_souls_label.text = "%d SOULS" % stats.souls
	for i in _offers.size():
		_refresh_offer(i)                        # fewer souls -> other offers may now be unaffordable
	_refresh_views()
	_sfx.play_drop()
	var center := _offer_buttons[index].get_global_rect().get_center()
	UiFxScript.ring(_root, center, SOUL, _cell_size * 1.5, maxf(3.0, _cell_size * 0.12))
	_refresh_reroll()


## The index of the unsold shop offer under `screen_pos`, or -1 (for the tooltip).
func _offer_index_at(screen_pos: Vector2) -> int:
	for i in _offer_buttons.size():
		if i < _offers.size() and not _offers[i]["sold"]:
			if _offer_buttons[i].get_global_rect().has_point(screen_pos):
				return i
	return -1


# --- sell -------------------------------------------------------------------

## A drop target: dragging an owned item onto it sells the item for 65% of its price.
func _make_sell_zone() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = BASE_SELL
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE     # drops are detected by rect in _input, not via GUI
	_sell_label = Label.new()
	_sell_label.text = "SELL"
	_sell_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sell_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sell_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sell_label.add_theme_color_override("font_color", SELL_HI)
	_sell_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_sell_label)
	return p


## Border the sell zone — brighter green while a held item hovers it.
func _style_sell(hot: bool) -> void:
	if _sell_zone == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = SELL_HI if hot else EMBER_DIM
	sb.set_border_width_all(3 if hot else 2)
	sb.set_corner_radius_all(5)
	_sell_zone.add_theme_stylebox_override("panel", sb)


## Sell the held item for 65% of its price: credit souls, discard it (it was removed
## from its grid on pick-up), and refresh. CONTINUE no longer has it to return.
func _sell_held() -> void:
	if _held == null or stats == null:
		return
	var amount: int = _held.sell_price()
	stats.add_souls(amount)                          # emits souls_changed -> HUD + offers update
	_souls_label.text = "%d SOULS" % stats.souls
	var center := _sell_zone.get_global_rect().get_center()
	_end_hold()                                      # discard: do NOT return the item to a grid
	_sfx.play_drop()
	UiFxScript.ring(_root, center, SELL_HI, _cell_size * 1.6, maxf(3.0, _cell_size * 0.12))
	for i in _offers.size():                          # more souls -> some offers may now be affordable
		_refresh_offer(i)
	_refresh_views()
	_style_sell(false)
	_refresh_reroll()


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
	_style_sell(_sell_zone.get_global_rect().has_point(screen_pos))   # glow the sell zone when hovered


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
