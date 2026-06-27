class_name StatusIcon
extends Control
## One buff/debuff badge for the HUD status row: a circular icon with a radial
## cooldown sweep (a dark wedge that drains as the effect wears off), a stack-count
## badge, and a seconds readout. Custom-drawn so the sweep + badge stay crisp at any
## size. Generic — set `icon` + `accent`, then drive it with set_state() each frame.

const BG := Color(0.1, 0.03, 0.03, 0.92)        # dark disc behind the icon
const COOLDOWN_DIM := Color(0.0, 0.0, 0.0, 0.55) # the draining sweep overlay
const BADGE_TEXT := Color(1.0, 0.96, 0.92)
const SECONDS_COL := Color(1.0, 0.92, 0.86)
const SHADOW := Color(0.0, 0.0, 0.0, 0.85)

var icon: Texture2D
var accent := Color(0.95, 0.25, 0.14)           # ring + badge colour (red for a debuff)
var icon_tint := Color(1.0, 0.6, 0.5)           # tint applied to the icon glyph

var _stacks := 0
var _frac := 0.0                                 # cooldown remaining, 0..1 (drives the sweep)
var _seconds := 0.0
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()


## Update the badge: how many stacks, the cooldown fraction remaining (1->0), and the
## seconds to show. Triggers a redraw.
func set_state(stacks: int, frac: float, seconds: float) -> void:
	_stacks = stacks
	_frac = clampf(frac, 0.0, 1.0)
	_seconds = seconds
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5

	draw_circle(c, r, BG)
	if icon != null:
		var isz := r * 1.3                        # glyph a touch larger than the inner disc
		draw_texture_rect(icon, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, icon_tint)

	# Radial cooldown: a dark wedge over the remaining fraction, sweeping clockwise
	# from 12 o'clock, so the icon is revealed as the effect wears off.
	if _frac > 0.0:
		var pts := PackedVector2Array([c])
		var steps := maxi(2, int(_frac * 48.0))
		for i in steps + 1:
			var a := -PI * 0.5 + _frac * TAU * (float(i) / float(steps))
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, COOLDOWN_DIM)

	draw_arc(c, r - 1.5, 0.0, TAU, 48, accent, 3.0, true)   # crisp ring border

	if _seconds > 0.0:
		var sf := maxi(10, int(r * 0.5))
		_draw_centered("%.1f" % _seconds, Vector2(c.x, size.y - r * 0.32), sf, SECONDS_COL)

	# Stack badge (top-right), only when it actually stacks.
	if _stacks >= 2:
		var br := r * 0.6
		var bc := Vector2(size.x - br, br)
		draw_circle(bc, br, accent)
		draw_arc(bc, br, 0.0, TAU, 24, SHADOW, 2.0, true)
		_draw_centered(str(_stacks), bc, maxi(10, int(br * 1.15)), BADGE_TEXT)


## Draw text centred (both axes) on `center`, with a 1px shadow for legibility.
func _draw_centered(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var sz := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y - sz.y * 0.5 + _font.get_ascent(font_size)
	var x := center.x - sz.x * 0.5
	draw_string(_font, Vector2(x + 1.0, baseline + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SHADOW)
	draw_string(_font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
