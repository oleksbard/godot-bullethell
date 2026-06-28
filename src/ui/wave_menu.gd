class_name WaveMenu
extends CanvasLayer
## Pause overlay shown between waves (opened once the cleared wave's souls have flown in —
## XpOrbField.drained). The player manages the grid inventory: left-click an item to pick it
## up (which removes it from its grid — so a pistol pulled out of the backpack is unequipped),
## SPACE rotates the held item, left-click a cell drops it where it fits. A 4-slot SHOP sits
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

const DIM := Color(0.02, 0.0, 0.0, 1.0)   # solid near-black: a clean modal backdrop (also hides the frozen HUD banner behind it)
const EMBER := Color(1.0, 0.45, 0.2)
const SOUL := Color(0.2, 0.85, 1.0)       # cyan soul-mote colour (matches the HUD counter)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const PANEL_BG := Color(0.06, 0.02, 0.02, 0.92)
const BTN_BG := Color(0.06, 0.02, 0.02, 0.92)
const DROP_FLASH := Color(1.0, 0.85, 0.55, 0.5)   # warm flash over a freshly-dropped item
const SHOP_SLOTS := 4                              # 4 rolled offers per level-up
const UNAFFORDABLE := Color(0.7, 0.35, 0.3)        # price colour when you can't afford it
const SOLD_DIM := Color(0.5, 0.5, 0.5, 0.8)        # icon tint for an unaffordable offer
const SELL_HI := Color(0.45, 1.0, 0.55)            # sell-zone accent (green = you get paid)

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
var _shop_row: HBoxContainer
var _title: Label
var _souls_label: Label             # "N SOULS" banked-currency readout under the title
var _power_label: Label             # "LOADOUT POWER N" — sum of equipped pistols' power
var _section_labels: Array[Label] = []
var _offer_buttons: Array[Button] = []   # the 4 shop offer slots
var _offer_icons: Array[TextureRect] = []
var _offer_prices: Array[Label] = []
var _offers: Array = []             # per-slot {item, price, sold}
var _rng := RandomNumberGenerator.new()  # rolls offers (tests can seed it)
var _sell_zone: Panel               # drag an owned item here to sell it for 65%
var _sell_label: Label
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
	_rng.randomize()
	_build()


## Pause + show. Idempotent: a re-open while already open is ignored. Rescales to the
## current viewport so it always covers ~TARGET_COVERAGE, centred. (arg-less so it can
## bind straight to WaveSpawner.wave_cleared.)
func open(_wave: int = 0) -> void:
	if _open:
		return
	_open = true
	_souls_label.text = "%d SOULS" % (stats.souls if stats != null else 0)
	_roll_offers()                   # 4 fresh shop offers, rolled off the player's level + luck
	_apply_layout_scale()
	_refresh_views()                 # also refreshes the loadout-power readout
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

	_columns = HBoxContainer.new()
	_columns.alignment = BoxContainer.ALIGNMENT_CENTER
	_columns.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_columns)

	# Left column: SHOP (4 rolled offers) on top, STASH below.
	_left = VBoxContainer.new()
	_columns.add_child(_left)
	_left.add_child(_section_label("SHOP"))
	_shop_row = HBoxContainer.new()
	for i in SHOP_SLOTS:
		_shop_row.add_child(_offer_slot(i))
	_left.add_child(_shop_row)
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
	for b in _offer_buttons:
		b.custom_minimum_size = Vector2(BASE_STUB, BASE_STUB) * k
	for p in _offer_prices:
		p.add_theme_font_size_override("font_size", maxi(7, roundi(BASE_PRICE_FONT * k)))
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

	_offer_buttons.append(b)
	_offer_icons.append(icon)
	_offer_prices.append(price)
	_style_offer(b, EMBER_DIM)
	return col


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
	var price := -1                              # owned -> sell price; shop offer -> buy price
	var is_buy := false
	var hit := _view_and_cell(screen_pos)
	if not hit.is_empty():
		it = hit[1].item_at(hit[2])
		if it != null:
			price = it.sell_price()
	else:
		it = _offer_at(screen_pos)               # hovering a shop offer shows its stats too
		if it != null:
			price = it.buy_price()
			is_buy = true
	if it == null:
		_tooltip.hide_tip()
	else:
		_tooltip.show_for(it, screen_pos, _tooltip_font, price, is_buy)


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

## Roll 4 fresh offers off the player's level + rarity_bonus, and paint the slots.
func _roll_offers() -> void:
	_offers.clear()
	var player_level: int = stats.level if stats != null else 1
	var rb: float = stats.rarity_bonus if stats != null else 0.0
	var kinds: Array = WeaponCatalogScript.weapon_kinds()
	for i in SHOP_SLOTS:
		var kind: int = kinds[_rng.randi_range(0, kinds.size() - 1)]
		var item := InventoryItemScript.rolled_weapon(kind, player_level, rb, _rng)
		_offers.append({"item": item, "price": item.buy_price(), "sold": false})
		_refresh_offer(i)


## Paint offer slot `index`: icon, price, rarity border, and affordable/sold state.
func _refresh_offer(index: int) -> void:
	var offer: Dictionary = _offers[index]
	var icon := _offer_icons[index]
	var price := _offer_prices[index]
	var btn := _offer_buttons[index]
	if offer["sold"]:
		icon.texture = null
		price.text = "SOLD"
		price.add_theme_color_override("font_color", EMBER_DIM)
		btn.disabled = true
		_style_offer(btn, EMBER_DIM)
		return
	var item: Object = offer["item"]
	var affordable: bool = stats != null and stats.souls >= int(offer["price"])
	icon.texture = GridViewScript.icon_for(item)
	icon.modulate = Color.WHITE if affordable else SOLD_DIM
	price.text = "%d" % int(offer["price"])
	price.add_theme_color_override("font_color", SOUL if affordable else UNAFFORDABLE)
	btn.disabled = false
	_style_offer(btn, ItemTooltipScript.RARITY_COLORS.get(item.rarity(), EMBER))


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
	_souls_label.text = "%d SOULS" % stats.souls
	for i in _offers.size():
		_refresh_offer(i)                        # fewer souls -> other offers may now be unaffordable
	_refresh_views()
	_sfx.play_drop()
	var center := _offer_buttons[index].get_global_rect().get_center()
	UiFxScript.ring(_root, center, SOUL, _cell_size * 1.5, maxf(3.0, _cell_size * 0.12))


## The item under `screen_pos` if it's an unsold shop offer, else null (for the tooltip).
func _offer_at(screen_pos: Vector2) -> Object:
	for i in _offer_buttons.size():
		if i < _offers.size() and not _offers[i]["sold"]:
			if _offer_buttons[i].get_global_rect().has_point(screen_pos):
				return _offers[i]["item"]
	return null


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
