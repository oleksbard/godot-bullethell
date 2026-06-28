class_name RecapView
extends Control
## Custom-drawn wave recap: damage dealt/taken (bars), kills per type, souls + duration,
## and a per-gun card (icon over its rarity block, DPS / damage / accuracy), gun cards
## sorted by DPS, with the top-damage gun crowned MVP. Fed a WaveStats via show_stats();
## shown on the shop's RECAP tab. Numbers count up on show; runs while the tree is paused
## (PROCESS_MODE_ALWAYS), like the menu that hosts it.

const GridViewScript := preload("res://src/ui/grid_view.gd")

const EMBER := Color(1.0, 0.45, 0.2)
const VALUE := Color(0.95, 0.92, 0.85)
const DIMMED := Color(0.7, 0.64, 0.56)
const DEALT_COL := Color(1.0, 0.6, 0.2)
const TAKEN_COL := Color(0.85, 0.12, 0.08)
const MVP_COL := Color(1.0, 0.85, 0.2)
const CARD_BG := Color(0.06, 0.02, 0.02, 0.92)
const CARD_BORDER := Color(0.62, 0.22, 0.1)
const TRACK_BG := Color(0.03, 0.01, 0.01, 0.9)
const ANIM_TIME := 0.5

const BASE_HEAD := 28
const BASE_LABEL := 18
const BASE_BIG := 30
const BASE_SMALL := 16
const BASE_PAD := 16.0
const BASE_ROW_H := 26.0
const BASE_BAR_W := 260.0
const BASE_BAR_H := 18.0
const BASE_CARD := Vector2(150.0, 196.0)
const BASE_CARD_GAP := 12.0
const BASE_ICON := 54.0

var _stats: Object = null
var _k := 1.0
var _anim := 1.0
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # passive display: never intercept clicks (the tabs sit above it)
	_font = get_theme_default_font()


## Render `stats` (a WaveStats; null -> blank) and restart the count-up. `_backpack` is
## kept in the signature for the caller but unused (artifact icons were removed).
func show_stats(stats: Object, _backpack: Object) -> void:
	_stats = stats
	_anim = 0.0
	custom_minimum_size = _measure()
	queue_redraw()


## Scale every size to the host menu's k (matches the shop's crisp native scaling).
func set_scale_k(k: float) -> void:
	_k = maxf(0.4, k)
	custom_minimum_size = _measure()
	queue_redraw()


func _process(delta: float) -> void:
	if _anim < 1.0:
		_anim = minf(1.0, _anim + delta / ANIM_TIME)
		queue_redraw()


## The header string (kept in one place so _measure can size to fit it).
func _header_text() -> String:
	if _stats == null:
		return ""
	return "WAVE %d CLEARED      ·      %.1fs      ·      +%d souls" % [
		int(_stats.wave), float(_stats.duration), int(_stats.souls_earned)]


## Natural size: wide enough for the header / the two-bar block / the card row, plus
## the stacked rows + one card row tall. (Width must fit the header so it can't clip.)
func _measure() -> Vector2:
	var pad := BASE_PAD * _k
	var cards := 1
	if _stats != null:
		cards = maxi(1, (_stats.guns as Array).size())
	var cards_w := float(cards) * (BASE_CARD.x * _k) + float(maxi(0, cards - 1)) * BASE_CARD_GAP * _k
	var head_w := 0.0
	if _font != null:
		head_w = _font.get_string_size(_header_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, _sz(BASE_HEAD)).x
	var w := maxf(maxf(head_w, cards_w), BASE_BAR_W * _k) + pad * 2.0
	var h := pad * 2.0 + BASE_ROW_H * _k * 5.6 + BASE_CARD.y * _k
	return Vector2(w, h)


func _draw() -> void:
	if _stats == null or _font == null:
		return
	var pad := BASE_PAD * _k
	var row := BASE_ROW_H * _k
	var x := pad
	var y := pad
	var width := size.x - pad * 2.0

	_line(_header_text(), Vector2(x, y), _sz(BASE_HEAD), EMBER, HORIZONTAL_ALIGNMENT_CENTER, width)
	y += row * 1.6

	var cap := maxf(1.0, maxf(float(_stats.damage_dealt), float(_stats.damage_taken)))
	var col_gap := pad
	var col_w := (width - col_gap) * 0.5      # two columns side by side, each fits its bar + number
	_stat_bar("DAMAGE DEALT", float(_stats.damage_dealt) * _anim, cap, DEALT_COL, Vector2(x, y), col_w)
	_stat_bar("DAMAGE TAKEN", float(_stats.damage_taken) * _anim, cap, TAKEN_COL, Vector2(x + col_w + col_gap, y), col_w)
	y += row * 2.4

	_line("KILLS", Vector2(x, y), _sz(BASE_LABEL), DIMMED)
	var kx := x + _font.get_string_size("KILLS    ", HORIZONTAL_ALIGNMENT_LEFT, -1, _sz(BASE_LABEL)).x
	for type in _stats.kills_by_type:
		var txt := "%s ×%d" % [str(type), int(_stats.kills_by_type[type])]
		_line(txt, Vector2(kx, y), _sz(BASE_LABEL), VALUE)
		kx += _font.get_string_size(txt + "      ", HORIZONTAL_ALIGNMENT_LEFT, -1, _sz(BASE_LABEL)).x
	y += row * 1.7

	_line("GUNS", Vector2(x, y), _sz(BASE_LABEL), DIMMED)
	y += row
	var mvp: Dictionary = _stats.mvp()
	var guns: Array = (_stats.guns as Array).duplicate()        # shallow copy; same card refs -> is_same still works
	guns.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _stats.dps(a) > _stats.dps(b))
	var n: int = guns.size()
	var cards_w := float(n) * (BASE_CARD.x * _k) + float(maxi(0, n - 1)) * BASE_CARD_GAP * _k
	var cx := x + maxf(0.0, (width - cards_w) * 0.5)         # centre the card row in the view
	for card in guns:
		_draw_card(card, Vector2(cx, y), is_same(card, mvp))     # ponytail: single row; many guns overflow right
		cx += BASE_CARD.x * _k + BASE_CARD_GAP * _k


func _draw_card(card: Dictionary, pos: Vector2, is_mvp: bool) -> void:
	var cw := BASE_CARD.x * _k
	var ch := BASE_CARD.y * _k
	var pad := 8.0 * _k
	draw_rect(Rect2(pos, Vector2(cw, ch)), CARD_BG)
	draw_rect(Rect2(pos, Vector2(cw, ch)), MVP_COL if is_mvp else CARD_BORDER, false, (3.0 if is_mvp else 2.0) * _k)
	var y := pos.y + pad

	if is_mvp:
		_line("★ MVP", Vector2(pos.x + pad, y), _sz(BASE_SMALL), MVP_COL)
	y += BASE_SMALL * _k + pad

	var item: Object = card.get("item", null)
	var iw := BASE_ICON * _k
	var box := Rect2(pos.x + (cw - iw) * 0.5, y, iw, iw)
	if item != null:
		var rb: Color = GridViewScript.rarity_bg(item)
		if rb.a > 0.0:
			draw_rect(box, rb)
		var tex: Texture2D = GridViewScript.icon_for(item)
		if tex != null:
			draw_texture_rect(tex, _fit(tex, box), false)   # keep the art's aspect — no skew
		else:
			draw_rect(box.grow(-2.0 * _k), GridViewScript.color_for(item))
	y += iw + pad

	_line(str(card.get("name", "Gun")), Vector2(pos.x + pad, y), _sz(BASE_SMALL), VALUE, HORIZONTAL_ALIGNMENT_CENTER, cw - pad * 2.0)
	y += BASE_SMALL * _k + pad * 0.5

	var dps := int(round(_stats.dps(card) * _anim))
	_line("%d DPS" % dps, Vector2(pos.x + pad, y), _sz(BASE_BIG), EMBER, HORIZONTAL_ALIGNMENT_CENTER, cw - pad * 2.0)
	y += BASE_BIG * _k + pad * 0.4

	_line("%d dmg" % int(round(float(card.get("damage", 0.0)) * _anim)),
		Vector2(pos.x + pad, y), _sz(BASE_SMALL), DIMMED, HORIZONTAL_ALIGNMENT_CENTER, cw - pad * 2.0)
	y += BASE_SMALL * _k + pad * 0.3
	_line("%d%% acc" % int(round(_stats.accuracy(card) * _anim * 100.0)),
		Vector2(pos.x + pad, y), _sz(BASE_SMALL), DIMMED, HORIZONTAL_ALIGNMENT_CENTER, cw - pad * 2.0)


## A rect inside `box` holding `tex` at its true aspect ratio, centred (letterboxed).
func _fit(tex: Texture2D, box: Rect2) -> Rect2:
	var ts := Vector2(tex.get_size())
	if ts.x <= 0.0 or ts.y <= 0.0:
		return box
	var s := minf(box.size.x / ts.x, box.size.y / ts.y)
	var dsz := ts * s
	return Rect2(box.position + (box.size - dsz) * 0.5, dsz)


## A labelled bar that fits inside `col_w`: the value number is drawn after the bar,
## and the bar is shortened to leave room for it, so nothing spills past the column.
func _stat_bar(label: String, value: float, cap: float, color: Color, pos: Vector2, col_w: float) -> void:
	var h := BASE_BAR_H * _k
	_line(label, pos, _sz(BASE_LABEL), DIMMED)
	var by := pos.y + BASE_LABEL * _k + 4.0 * _k
	var num := "%d" % int(round(value))
	var num_w := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, _sz(BASE_LABEL)).x
	var bar_w := maxf(8.0 * _k, col_w - num_w - 8.0 * _k)
	draw_rect(Rect2(pos.x, by, bar_w, h), TRACK_BG)
	var frac := clampf(value / cap, 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(pos.x, by, bar_w * frac, h), color)
	_line(num, Vector2(pos.x + bar_w + 6.0 * _k, by), _sz(BASE_LABEL), VALUE)


func _line(text: String, pos: Vector2, sz: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos + Vector2(0.0, _font.get_ascent(sz)), text, align, width, sz, color)


func _sz(base: int) -> int:
	return maxi(8, roundi(float(base) * _k))
