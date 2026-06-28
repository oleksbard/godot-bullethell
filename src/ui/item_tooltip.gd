class_name ItemTooltip
extends Control
## A generic hover tooltip for any InventoryItem. It reads display_name()/rarity()/
## level()/stats()/flavor() off the item and knows nothing about specific kinds, so
## new item types get a tooltip for free. It is CUSTOM-DRAWN (not a Container): the
## content is measured and stacked by hand and the control's size is set to exactly
## that, so the box always hugs its content — no stale-min-size empty space. Layout:
## name header, "rarity · Lvl N" subtitle, a two-column stat list, then flavour text.
## Hides any false boolean or zero-valued number and renders booleans as "Yes".
## Follows the cursor, offset and clamped so it never spills off-screen.

const EMBER := Color(1.0, 0.45, 0.2)
const EMBER_DIM := Color(0.72, 0.42, 0.28)
const VALUE_COL := Color(0.95, 0.92, 0.85)
const BUFF_COL := Color(0.45, 1.0, 0.55)     # stat value raised by an artifact (green = buffed)
const FLAVOR_COL := Color(0.7, 0.64, 0.56)
const PANEL_BG := Color(0.08, 0.035, 0.03, 0.97)
const SEP_COL := Color(0.5, 0.25, 0.15, 0.8)
const BORDER_COL := Color(0.5, 0.25, 0.15, 0.9)
const TAG_BG := Color(0.22, 0.1, 0.06, 0.95)
const TAG_BORDER := Color(0.6, 0.3, 0.16, 1.0)
const TAG_TEXT := Color(0.95, 0.62, 0.4)
const POWER_TEX: Texture2D = preload("res://art/ui/power.svg")   # game-icons.net power-lightning
const SOUL_TEX: Texture2D = preload("res://art/ui/soul.svg")     # game-icons.net spectre (soul = the currency)
const POWER_COLOR := Color(1.0, 0.55, 0.2)   # ember tint for the Power chip
const PRICE_COLOR := Color(0.2, 0.85, 1.0)   # cyan tint for the Price chip (matches the souls UI)
const HL_GAP := 0.35     # icon -> value gap, × body font
const HL_CHIP_GAP := 0.9 # gap between the Power chip and the Price chip, × body font

const CURSOR_OFFSET := 16.0
const FLAVOR_WRAP_CHARS := 34
const PAD := 0.65        # inner padding, × body font
const COL_GAP := 1.1     # gap between the stat label column and the value column, × body font
const ROW_GAP := 0.18    # extra gap between stat rows, × body font (tight)
const SECTION_GAP := 0.45  # gap around each separator line, × body font
const TAG_HPAD := 0.45   # tag pill horizontal text padding, × tag font
const TAG_VPAD := 0.16   # tag pill vertical text padding, × tag font
const TAG_GAP := 0.4     # gap between tag pills, × tag font

# Rarity tier -> name colour. Only "Normal" exists in-game now; the rest are ready
# for when loot rarity lands.
const RARITY_COLORS := {
	"Normal": Color(0.82, 0.82, 0.82),
	"Rare": Color(0.4, 0.7, 1.0),
	"Unique": Color(0.7, 0.45, 1.0),
	"Legendary": Color(1.0, 0.6, 0.15),
}

var _item: Object                   # the item currently shown
var _font: Font

# Rendered model: built in show_for, consumed by _draw. y values are line tops.
var _name_text := ""
var _sub_text := ""
var _sub_color := EMBER_DIM
var _tags: Array = []               # header pill strings (Type + traits)
var _tag_rects: Array[Rect2] = []   # pill rects (relative to this control)
# Highlight chips: Power (always) + Price (BUY for shop offers / SELL for owned items).
var _price_val := -1                # souls; -1 = no price chip
var _price_is_buy := false          # true -> "BUY", false -> "SELL"
var _show_power := true              # false for items with no power (e.g. expansions)
var _power_text := ""
var _price_text := ""               # "" when _price_val < 0
var _hl_y := 0.0                    # highlight row top
var _hl_pw_text_x := 0.0            # power value text x
var _hl_mote_cx := -1.0             # price mote centre x (-1 = no price chip)
var _hl_price_text_x := 0.0         # price value text x
var _rows: Array = []               # [[label, value_str], ...]
var _row_buffed: Array = []         # parallel to _rows: true where an artifact raised the value
var _source_icons: Array = []       # artifact icons that buff this gun (drawn in a row)
var _icons_y := -1.0                # icon row top (-1 = none)
var _icon_px := 0                   # icon square size
var _last_sig := ""                 # mods+icons signature, so a buff change rebuilds the model
var _flavor_lines: PackedStringArray = PackedStringArray()
var _s_name := 0
var _s_sub := 0
var _s_tag := 0
var _s_stat := 0                    # body size; also the "is this built for px" key
var _s_flavor := 0
var _value_x := 0.0
var _name_y := 0.0
var _sub_y := 0.0
var _sep1_y := 0.0
var _row_ys: PackedFloat32Array = PackedFloat32Array()
var _sep2_y := -1.0
var _flavor_ys: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE      # never eats clicks meant for the grids/button
	_font = get_theme_default_font()                # same font the menu's labels use


# --- public -----------------------------------------------------------------

## Show the tooltip for `item` near `screen_pos`, with the body font at `font_px`.
## `price` (>= 0) shows a Price chip — a BUY price for a shop offer (`price_is_buy`)
## or the SELL price for an owned item. Rebuilds the (cheap) model only when something
## it depends on changes.
## `mods` (GunMods or null) re-renders the gun's affected stats as their resolved value in
## BUFF_COL; `source_icons` are the artifact icons shown in a row beneath the stats.
func show_for(item: Object, screen_pos: Vector2, font_px: int, price: int = -1, price_is_buy: bool = false,
		mods: Object = null, source_icons: Array = []) -> void:
	var sig := _mods_sig(mods, source_icons)
	if item != _item or font_px != _s_stat or price != _price_val or price_is_buy != _price_is_buy or sig != _last_sig:
		_item = item
		_price_val = price
		_price_is_buy = price_is_buy
		_source_icons = source_icons
		_last_sig = sig
		_build_model(item, font_px, mods)
		queue_redraw()
	visible = true
	_place(screen_pos)


## A cheap signature of the buff inputs, so the model rebuilds when they change.
func _mods_sig(mods: Object, icons: Array) -> String:
	if mods == null:
		return ""
	return "%.3f_%.3f_%.3f_%d" % [mods.damage_mul, mods.fire_rate_mul, mods.reload_mul, icons.size()]


## Hide the tooltip and forget the item (so the next show_for rebuilds).
func hide_tip() -> void:
	visible = false
	_item = null


## Filter + format an item's stats for display: drop false booleans and zero
## numbers, render bools as "Yes", numbers without a needless decimal. Static so
## it's unit-testable without the scene tree. Returns an Array of [label, value_str].
static func format_stats(item: Object) -> Array:
	var out: Array = []
	for entry in item.stats():
		var label: String = entry[0]
		var value: Variant = entry[1]
		if value is bool:
			if value:
				out.append([label, "Yes"])
		elif value is int or value is float:
			if not is_zero_approx(float(value)):
				out.append([label, _fmt_num(value)])
		else:
			out.append([label, str(value)])
	return out


# --- layout (deterministic; no containers) ----------------------------------

## Measure the content at `px` and stack it, setting our exact size. No autolayout,
## so the box always fits — content height is computed with the same steps _draw uses.
func _build_model(item: Object, px: int, mods: Object = null) -> void:
	_s_stat = px
	_s_name = roundi(px * 1.3)
	_s_sub = maxi(9, roundi(px * 0.92))
	_s_tag = maxi(9, roundi(px * 0.82))
	_s_flavor = maxi(9, roundi(px * 0.78))

	_name_text = item.display_name()
	var rarity: String = item.rarity()
	var lvl: int = item.level()
	_sub_text = ("%s · Lvl %d" % [rarity, lvl]) if lvl > 0 else rarity
	_sub_color = RARITY_COLORS.get(rarity, EMBER_DIM)
	_tags = item.tags()
	_power_text = str(item.power())
	_show_power = item.power() > 0
	_price_text = "" if _price_val < 0 else "%d %s" % [_price_val, "BUY" if _price_is_buy else "SELL"]
	_rows = format_stats(item)
	_row_buffed = []
	_row_buffed.resize(_rows.size())
	_row_buffed.fill(false)
	if mods != null:
		_apply_mods(item, mods)
	var flavor: String = item.flavor()
	_flavor_lines = _wrap(flavor, FLAVOR_WRAP_CHARS).split("\n") if flavor != "" else PackedStringArray()

	var pad := px * PAD
	var sect := px * SECTION_GAP

	# Column widths for the stats.
	var label_w := 0.0
	var value_w := 0.0
	for r in _rows:
		label_w = maxf(label_w, _font.get_string_size(r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, _s_stat).x)
		value_w = maxf(value_w, _font.get_string_size(r[1], HORIZONTAL_ALIGNMENT_LEFT, -1, _s_stat).x)
	_value_x = pad + label_w + px * COL_GAP

	# Stack vertically; record each line's top y.
	var y := pad
	_name_y = y
	y += _font.get_height(_s_name)
	_sub_y = y
	y += _font.get_height(_s_sub)

	# Tags row: pills laid left-to-right; record their rects.
	_tag_rects = []
	var tags_right := pad
	if _tags.size() > 0:
		y += sect * 0.6
		var thpad := _s_tag * TAG_HPAD
		var tvpad := _s_tag * TAG_VPAD
		var tag_h := _font.get_height(_s_tag) + tvpad * 2.0
		var tx := pad
		for t in _tags:
			var tw := _font.get_string_size(str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, _s_tag).x + thpad * 2.0
			_tag_rects.append(Rect2(tx, y, tw, tag_h))
			tx += tw + _s_tag * TAG_GAP
		tags_right = tx - _s_tag * TAG_GAP
		y += tag_h

	# Highlight row: a Power chip (when power > 0) and a Price chip (when set).
	var hl_icon := float(_s_stat)
	var hl_gap := _s_stat * HL_GAP
	var hl_right := pad
	var has_hl := _show_power or _price_text != ""
	if has_hl:
		y += sect * 0.6
		_hl_y = y
		if _show_power:
			_hl_pw_text_x = pad + hl_icon + hl_gap
			hl_right = _hl_pw_text_x + _font.get_string_size(_power_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _s_stat).x
		if _price_text != "":
			if _show_power:
				hl_right += _s_stat * HL_CHIP_GAP
			_hl_mote_cx = hl_right + hl_icon * 0.5
			_hl_price_text_x = hl_right + hl_icon + hl_gap
			hl_right = _hl_price_text_x + _font.get_string_size(_price_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _s_stat).x
		else:
			_hl_mote_cx = -1.0
		y += maxf(hl_icon, _font.get_height(_s_stat))
	else:
		_hl_y = -1.0
		_hl_mote_cx = -1.0

	y += sect
	_sep1_y = y
	y += sect
	_row_ys = PackedFloat32Array()
	for r in _rows:
		_row_ys.append(y)
		y += _font.get_height(_s_stat) + px * ROW_GAP

	# Artifact source icons: a row beneath the stats listing what buffs this gun.
	_icon_px = roundi(px * 1.25)
	if _source_icons.size() > 0:
		y += sect
		_icons_y = y
		y += float(_icon_px)
	else:
		_icons_y = -1.0

	if _flavor_lines.size() > 0:
		y += sect
		_sep2_y = y
		y += sect
		_flavor_ys = PackedFloat32Array()
		for ln in _flavor_lines:
			_flavor_ys.append(y)
			y += _font.get_height(_s_flavor)
	else:
		_sep2_y = -1.0
		_flavor_ys = PackedFloat32Array()

	# Width = padding + the widest of: name, sub, tags row, stat row, flavour line.
	var content_w := _font.get_string_size(_name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _s_name).x
	content_w = maxf(content_w, _font.get_string_size(_sub_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _s_sub).x)
	content_w = maxf(content_w, tags_right - pad)
	content_w = maxf(content_w, hl_right - pad)
	content_w = maxf(content_w, _value_x - pad + value_w)
	content_w = maxf(content_w, float(_source_icons.size()) * (float(_icon_px) + px * 0.2))
	for ln in _flavor_lines:
		content_w = maxf(content_w, _font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, _s_flavor).x)

	size = Vector2(content_w + pad * 2.0, y + pad)


func _draw() -> void:
	if _item == null:
		return
	var pad := _s_stat * PAD
	draw_rect(Rect2(Vector2.ZERO, size), PANEL_BG)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COL, false, 2.0)
	_draw_line_text(Vector2(pad, _name_y), _name_text, _s_name, EMBER)
	_draw_line_text(Vector2(pad, _sub_y), _sub_text, _s_sub, _sub_color)
	for i in _tags.size():
		_draw_tag(_tag_rects[i], str(_tags[i]))
	if _hl_y >= 0.0:
		var hl_icon := float(_s_stat)
		var hl_h := _font.get_height(_s_stat)
		var icon_top := _hl_y + (hl_h - hl_icon) * 0.5
		if _show_power:
			draw_texture_rect(POWER_TEX, Rect2(pad, icon_top, hl_icon, hl_icon), false, POWER_COLOR)
			_draw_line_text(Vector2(_hl_pw_text_x, _hl_y), _power_text, _s_stat, VALUE_COL)
		if _hl_mote_cx >= 0.0:
			draw_texture_rect(SOUL_TEX, Rect2(_hl_mote_cx - hl_icon * 0.5, icon_top, hl_icon, hl_icon), false, PRICE_COLOR)
			_draw_line_text(Vector2(_hl_price_text_x, _hl_y), _price_text, _s_stat, PRICE_COLOR)
	draw_line(Vector2(pad, _sep1_y), Vector2(size.x - pad, _sep1_y), SEP_COL, 1.0)
	for i in _rows.size():
		_draw_line_text(Vector2(pad, _row_ys[i]), _rows[i][0], _s_stat, EMBER_DIM)
		var vcol: Color = BUFF_COL if (i < _row_buffed.size() and _row_buffed[i]) else VALUE_COL
		_draw_line_text(Vector2(_value_x, _row_ys[i]), _rows[i][1], _s_stat, vcol)
	if _icons_y >= 0.0:
		var ix := _s_stat * PAD
		var igap := _s_stat * 0.2
		for tex in _source_icons:
			if tex != null:
				draw_texture_rect(tex, Rect2(ix, _icons_y, _icon_px, _icon_px), false)
			ix += float(_icon_px) + igap
	if _sep2_y >= 0.0:
		draw_line(Vector2(pad, _sep2_y), Vector2(size.x - pad, _sep2_y), SEP_COL, 1.0)
	for i in _flavor_lines.size():
		_draw_line_text(Vector2(pad, _flavor_ys[i]), _flavor_lines[i], _s_flavor, FLAVOR_COL)


## Re-render a buffed gun's affected stat rows as their artifact-resolved value (in
## BUFF_COL). Maps the known stat labels to GunMods fields; leaves others untouched.
func _apply_mods(item: Object, mods: Object) -> void:
	for i in _rows.size():
		match _rows[i][0]:
			"Damage":
				if not is_equal_approx(mods.damage_mul, 1.0):
					_rows[i][1] = _fmt_num(roundi(item.damage_value() * mods.damage_mul))
					_row_buffed[i] = true
			"Rate of Fire":
				if not is_equal_approx(mods.fire_rate_mul, 1.0):
					_rows[i][1] = _fmt_num(roundi(60.0 * mods.fire_rate_mul / item.fire_interval_value()))
					_row_buffed[i] = true
			"Reload":
				if not is_equal_approx(mods.reload_mul, 1.0):
					_rows[i][1] = _fmt_num(item.reload_time_value() * mods.reload_mul)
					_row_buffed[i] = true


## Draw a tag "pill": a filled, ember-bordered box with the tag text centred in it.
func _draw_tag(rect: Rect2, text: String) -> void:
	draw_rect(rect, TAG_BG)
	draw_rect(rect, TAG_BORDER, false, 1.0)
	var ty := rect.position.y + (rect.size.y - _font.get_height(_s_tag)) * 0.5 + _font.get_ascent(_s_tag)
	draw_string(_font, Vector2(rect.position.x + _s_tag * TAG_HPAD, ty),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, _s_tag, TAG_TEXT)


## Draw one line of text whose TOP-left is `top_left` (we add the ascent for baseline).
func _draw_line_text(top_left: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(_font, Vector2(top_left.x, top_left.y + _font.get_ascent(font_size)),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Offset from the cursor, then clamp so NO part of the panel leaves the viewport.
func _place(screen_pos: Vector2) -> void:
	var sz := size
	var vp := get_viewport_rect().size
	var p := screen_pos + Vector2(CURSOR_OFFSET, CURSOR_OFFSET)
	if p.x + sz.x > vp.x:
		p.x = screen_pos.x - CURSOR_OFFSET - sz.x        # flip to the cursor's left
	if p.y + sz.y > vp.y:
		p.y = screen_pos.y - CURSOR_OFFSET - sz.y        # flip above the cursor
	p.x = clampf(p.x, 0.0, maxf(0.0, vp.x - sz.x))       # hard-clamp both axes inside the viewport
	p.y = clampf(p.y, 0.0, maxf(0.0, vp.y - sz.y))
	position = p


static func _fmt_num(v: Variant) -> String:
	var f := float(v)
	if absf(f - roundf(f)) < 0.05:
		return str(roundi(f))
	return "%.1f" % f


## Greedy word-wrap `text` into lines of at most `max_chars`, joined with newlines.
static func _wrap(text: String, max_chars: int) -> String:
	var lines: PackedStringArray = []
	var cur := ""
	for word in text.split(" ", false):
		if cur.is_empty():
			cur = word
		elif cur.length() + 1 + word.length() <= max_chars:
			cur += " " + word
		else:
			lines.append(cur)
			cur = word
	if not cur.is_empty():
		lines.append(cur)
	return "\n".join(lines)
