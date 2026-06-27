class_name HealthVial
extends Node3D
## A health pickup dropped onto the island by HealthVialField. It sits in a green halo
## (an emissive ground ring + a soft green light, both blooming via the world glow) and
## the model bounces with a ball-like squash-and-stretch + a lazy spin. Unlike an XP orb
## it does NOT magnetise, so reaching it is a deliberate trip (off-screen ones are flagged
## by a "+" token on the screen border). On contact it heals the marine — but only while
## it's hurt, so a full marine leaves it for later — then pops: the halo flares outward and
## a green "+X" floats up for the amount restored. Registers in GROUP so the field can cap
## how many exist and the indicator can find off-screen ones. `player`/`heal_amount` are set
## right after instancing by HealthVialField.

const MODEL: PackedScene = preload("res://models/health_vial.glb")
const DamageNumberScript := preload("res://src/fx/damage_number.gd")

const GROUP := "health_vials"
const VIAL_HEIGHT := 0.9        # model auto-scaled so its height = this (world units)
const COLLECT_RADIUS := 1.0     # marine distance (on the ground plane) at which it's picked up
const HEAL := 20.0              # HP restored on pickup (HealthVialField may override per drop)

# Bounce: the model rides abs(sin) so it kisses the ground and pops up like a ball, squashing
# wide-and-flat as it lands and stretching tall at the apex.
const GROUND_CLEAR := 0.04      # lowest the base sits above the ground (at the bottom of a bounce)
const BOUNCE_HEIGHT := 0.55     # apex height of the base above the ground
const BOUNCE_FREQ := 3.0        # bounce rate
const SQUASH_Y := 0.22          # flatten up to this fraction at the landing
const SQUASH_XZ := 0.16         # widen up to this fraction at the landing
const SPIN := 2.4               # idle spin (rad/s)

# Green halo: an emissive ground ring + a soft point light. Emission/energy clear the world's
# glow threshold so the ring blooms into a halo, and both pulse brighter at the bounce apex.
const HALO_COLOR := Color(0.3, 1.0, 0.5)
const HALO_RADIUS := 0.72       # ring outer radius
const HALO_TUBE := 0.07         # ring thickness
const HALO_EMISSION := 3.2      # > env glow_hdr_threshold -> blooms
const LIGHT_RANGE := 3.4
const LIGHT_ENERGY := 2.2

# Consumption pop: the halo ring detaches and flares outward as it fades.
const POP_TIME := 0.35
const POP_SCALE := 3.2
const NUMBER_COLOR := Color(0.45, 1.0, 0.55)

var player: Node3D
var heal_amount := HEAL

var _t := 0.0
var _model: Node3D
var _fit_scale := 1.0           # uniform scale that fit the model to VIAL_HEIGHT
var _aabb_min_y := 0.0          # model-local mesh min-y (to anchor the base while squashing)
var _halo: MeshInstance3D       # the emissive ground ring (detaches into the pop on pickup)
var _halo_mat: StandardMaterial3D
var _light: OmniLight3D
var _taken := false


func _ready() -> void:
	add_to_group(GROUP)
	_build_model()
	_build_halo()


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	var b := absf(sin(_t * BOUNCE_FREQ))      # 0 at the floor .. 1 at the apex
	_animate(b, delta)

	if player == null or not is_instance_valid(player):
		return
	var flat := player.global_position - global_position
	flat.y = 0.0
	# On contact: heal the marine. gain_health returns the HP actually restored (0 when it's
	# already full), so the vial is only consumed on a real heal — otherwise it's left for later.
	if flat.length() <= COLLECT_RADIUS and player.has_method("gain_health"):
		var healed: float = player.gain_health(heal_amount)
		if healed > 0.0:
			_collect(healed)


## Drive the bounce (squash-and-stretch) + spin on the model and pulse the halo with it.
func _animate(b: float, delta: float) -> void:
	if _model != null:
		var land := 1.0 - b                   # 1 at the floor (full squash) .. 0 at the apex
		var sx := 1.0 + land * SQUASH_XZ
		var sy := 1.0 - land * SQUASH_Y
		_model.scale = Vector3(_fit_scale * sx, _fit_scale * sy, _fit_scale * sx)
		var base_y := GROUND_CLEAR + b * BOUNCE_HEIGHT
		_model.position.y = base_y - _aabb_min_y * _fit_scale * sy   # keep the base on the bounce, not drifting
		_model.rotate_y(SPIN * delta)
	if _halo_mat != null:
		_halo_mat.emission_energy_multiplier = HALO_EMISSION * (0.65 + 0.35 * b)
	if _light != null:
		_light.light_energy = LIGHT_ENERGY * (0.7 + 0.3 * b)


## Heal landed: pop a green "+X", flare the halo outward, and free.
func _collect(healed: float) -> void:
	_taken = true
	DamageNumberScript.spawn(get_parent(), global_position + Vector3(0.0, 1.2, 0.0), healed, NUMBER_COLOR, "+")
	_pop_halo()
	queue_free()


## Detach the halo ring and tween it expanding + fading, so the pickup leaves a green flare
## behind after this node frees. Mirrors Imp._spawn_corpse (reparent to survive queue_free).
func _pop_halo() -> void:
	var parent := get_parent()
	if _halo == null or parent == null:
		return
	var ring := _halo
	ring.reparent(parent)                     # keeps world transform; survives our queue_free()
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", ring.scale * POP_SCALE, POP_TIME).set_ease(Tween.EASE_OUT)
	if _halo_mat != null:
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tw.tween_property(_halo_mat, "emission_energy_multiplier", 0.0, POP_TIME)
		tw.tween_property(_halo_mat, "albedo_color:a", 0.0, POP_TIME)
	tw.chain().tween_callback(ring.queue_free)


## Instance the vial model and scale it to VIAL_HEIGHT (the bounce sets its Y each frame).
func _build_model() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	var aabb := _merged_aabb(model)
	if aabb.size.y > 0.001:
		_fit_scale = VIAL_HEIGHT / aabb.size.y
		_aabb_min_y = aabb.position.y
		model.scale = Vector3.ONE * _fit_scale
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model = model


## Build the green halo: an emissive ground ring (blooms via the world glow) + a soft light.
func _build_halo() -> void:
	var torus := TorusMesh.new()
	torus.outer_radius = HALO_RADIUS
	torus.inner_radius = HALO_RADIUS - HALO_TUBE
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.albedo_color = HALO_COLOR
	_halo_mat.emission_enabled = true
	_halo_mat.emission = HALO_COLOR
	_halo_mat.emission_energy_multiplier = HALO_EMISSION
	_halo = MeshInstance3D.new()
	_halo.mesh = torus
	_halo.material_override = _halo_mat
	_halo.position.y = 0.03                   # just off the ground to avoid z-fighting
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)

	_light = OmniLight3D.new()
	_light.light_color = HALO_COLOR
	_light.omni_range = LIGHT_RANGE
	_light.light_energy = LIGHT_ENERGY
	_light.position.y = 0.4
	add_child(_light)


## Combined AABB of the model's meshes, in the model's local space.
func _merged_aabb(model: Node3D) -> AABB:
	var inv := model.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var local := inv * (mi as MeshInstance3D).global_transform
		var a := local * (mi as MeshInstance3D).get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out
