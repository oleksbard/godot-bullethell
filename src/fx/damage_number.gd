class_name DamageNumber
extends Label3D
## A floating damage number: billboarded 3D text that rises and fades, then frees
## itself. Repeated hits on the SAME target accumulate into one number — keep the node
## spawn() returns and call add() while it's alive: it bumps the running total, pulses,
## flies back to its start, refreshes its lifespan, and grows the font toward BASE_FONT.
## Numbers start small (SMALL_FONT) and only grow as a target is hit again and again.

const Self := preload("res://src/fx/damage_number.gd")   # self-ref via path: bare class_name fails on a cold --path run (no global class cache)

const RISE := 1.1            # world units it drifts up over its life
const LIFETIME := 0.7        # base seconds; each new hit refreshes it (so it lingers while a target is worked)
const BASE_FONT := 48        # the full size a heavily-hit number grows up to ("current value")
const SMALL_FONT := 22       # default size for a single, un-accumulated hit
const FONT_GROW := 7         # font px added per accumulated hit (capped at BASE_FONT)
const BASE_PIXEL := 0.0014   # on-screen scale; the pulse momentarily inflates this
const FLYBACK := 0.12        # seconds to fly back to the start position on a fresh hit
const PULSE_SCALE := 1.4     # how big the pulse pops on a hit (× BASE_PIXEL)
const PULSE_TIME := 0.2

var _amount := 0.0
var _color := Color.WHITE
var _pos := Vector3.ZERO
var _prefix := ""            # e.g. "+" for a heal (+20); "" for plain damage
var _tw: Tween
var _pulse_tw: Tween


## Pop a number at `world_pos` under `parent` (parent must be unrotated/unscaled).
## Returns the node — keep it and call add() to accumulate repeated hits into it.
static func spawn(parent: Node, world_pos: Vector3, amount: float, color: Color, prefix: String = "") -> Self:
	var n := Self.new()
	n._amount = amount
	n._color = color
	n._pos = world_pos
	n._prefix = prefix
	parent.add_child(n)
	return n


func _ready() -> void:
	modulate = _color
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true                 # always drawn over the world
	fixed_size = true                    # constant on-screen size
	font_size = SMALL_FONT
	outline_size = 6
	outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	pixel_size = BASE_PIXEL
	global_position = _pos
	_refresh_text()
	_animate(LIFETIME)


## Accumulate another hit into this number: bump the total, grow the font toward
## BASE_FONT, refresh the lifespan, and pulse + fly back to the start. Only valid
## while the node is still alive (callers guard with is_instance_valid).
func add(amount: float) -> void:
	_amount += amount
	font_size = mini(BASE_FONT, font_size + FONT_GROW)
	_refresh_text()
	_pulse()
	_animate(LIFETIME)


func _refresh_text() -> void:
	text = _prefix + str(roundi(_amount))


## (Re)start the rise + fade over `life` seconds, flying back to the start first so a
## fresh hit visibly snaps the number home before it drifts up again.
func _animate(life: float) -> void:
	if _tw != null and _tw.is_valid():
		_tw.kill()
	modulate.a = _color.a
	_tw = create_tween()
	_tw.tween_property(self, "global_position", _pos, FLYBACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "global_position:y", _pos.y + RISE, life).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(self, "modulate:a", 0.0, life).set_ease(Tween.EASE_IN)
	_tw.chain().tween_callback(queue_free)


## A quick scale pop (via pixel_size, which always honours fixed_size) on a fresh hit.
func _pulse() -> void:
	if _pulse_tw != null and _pulse_tw.is_valid():
		_pulse_tw.kill()
	pixel_size = BASE_PIXEL * PULSE_SCALE
	_pulse_tw = create_tween()
	_pulse_tw.tween_property(self, "pixel_size", BASE_PIXEL, PULSE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
