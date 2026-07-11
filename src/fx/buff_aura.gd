class_name BuffAura
extends Node3D
## The zombie's AoE-haste cast FX: an electric-cyan ring on the ground under the caster that
## tightens and brightens as the 3s channel fills, then bursts outward to the buff radius on
## release. The zombie spawns it on begin_channel(), drives set_progress(), and calls
## burst(range) when the channel lands. Reference via a preload const.

const COLOR := Color(0.35, 0.8, 1.0)     # electric cyan — distinct from the ember palette
const Y_LIFT := 0.07
const BASE_RADIUS := 1.2                 # channel-ring radius (burst scales up from this)
const TUBE := 0.10
const BURST_TIME := 0.45

var _mat: StandardMaterial3D
var _ring: MeshInstance3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.02, 0.05, 0.08)
	_mat.emission_enabled = true
	_mat.emission = COLOR
	_mat.emission_energy_multiplier = 3.0
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true                 # draw over terrain so hills never clip it
	var torus := TorusMesh.new()              # rotational axis is Y -> lies flat
	torus.inner_radius = BASE_RADIUS - TUBE
	torus.outer_radius = BASE_RADIUS + TUBE
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.position.y = Y_LIFT
	add_child(_ring)


## Channel progress 0..1: tighten the ring and brighten it as the cast completes.
func set_progress(p: float) -> void:
	var k := clampf(p, 0.0, 1.0)
	var s := lerpf(1.4, 0.85, k)
	_ring.scale = Vector3(s, 1.0, s)
	_mat.emission_energy_multiplier = 3.0 + 4.0 * k


## The channel landed — expand the ring out to `radius` (the buff range), fade, and free.
func burst(radius: float) -> void:
	var target := radius / BASE_RADIUS
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_ring, "scale", Vector3(target, 1.0, target), BURST_TIME).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_energy, 9.0, 0.0, BURST_TIME)
	tw.chain().tween_callback(queue_free)


func _set_energy(v: float) -> void:
	_mat.emission_energy_multiplier = v


func _process(delta: float) -> void:
	_ring.rotation.y += delta * 1.5           # slow spin while it lives
