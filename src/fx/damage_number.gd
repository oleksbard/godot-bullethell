class_name DamageNumber
extends Label3D
## A floating damage number: billboarded 3D text that rises a little and fades out,
## then frees itself. Used for both damage dealt to imps and damage taken by the
## player. Spawn with DamageNumber.spawn(parent, world_pos, amount, color).

const Self := preload("res://src/fx/damage_number.gd")   # self-ref via path: bare class_name fails on a cold --path run (no global class cache)
const RISE := 1.1            # world units it drifts up over its life
const LIFETIME := 0.7

var _amount := 0.0
var _color := Color.WHITE
var _pos := Vector3.ZERO
var _prefix := ""            # e.g. "+" for a heal (+20); "" for plain damage


## Pop a number at `world_pos` under `parent` (parent must be unrotated/unscaled —
## the composition root or a spawner, both at origin here). `prefix` is prepended to
## the number (use "+" for a heal pickup).
static func spawn(parent: Node, world_pos: Vector3, amount: float, color: Color, prefix: String = "") -> void:
	var n := Self.new()
	n._amount = amount
	n._color = color
	n._pos = world_pos
	n._prefix = prefix
	parent.add_child(n)


func _ready() -> void:
	text = _prefix + str(roundi(_amount))
	modulate = _color
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	no_depth_test = true                 # always drawn over the world
	fixed_size = true                    # constant on-screen size
	font_size = 48
	outline_size = 6
	outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	pixel_size = 0.0014
	global_position = _pos

	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "position:y", position.y + RISE, LIFETIME).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "modulate:a", 0.0, LIFETIME).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)
