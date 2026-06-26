class_name XpOrb
extends MeshInstance3D
## A collectible experience orb dropped by a dead imp. It bobs/spins in place until the
## marine comes within MAGNET_RADIUS, then flies in at a ramping speed and is collected
## within COLLECT_RADIUS (crediting the marine's XP). vacuum() forces the fly-in from any
## distance — used at wave clear so no earned XP is left behind.
## Created by XpOrbField; `player`/`xp_value` are set right after instancing.

const RADIUS := 0.09                       # small soul-mote (half the original size)
const COLOR := Color(0.2, 0.85, 1.0)       # cold cyan "soul" — pops against the ember-red world
const EMISSION_ENERGY := 2.6               # above the env glow threshold -> blooms
const REST_Y := 0.5                        # idle hover height
const BOB := 0.12                          # idle vertical bob amplitude
const BOB_FREQ := 3.0
const SPIN := 2.4                          # idle spin (rad/s)
const PULSE_FREQ := 5.0                    # twinkle rate (scale + emission)
const PULSE_SCALE := 0.18                  # ± scale wobble while alive
const PULSE_EMISSION := 0.4                # ± emission-energy twinkle
const MAGNET_RADIUS := 4.0                 # marine distance at which it starts flying in
const COLLECT_RADIUS := 0.6                # distance at which it's collected
const SPEED_MIN := 6.0                     # fly-in speed when magnetising starts
const SPEED_MAX := 14.0                    # ramps to this as it closes in
const ACCEL := 24.0                        # fly-in speed ramp (units/s^2)

var player: Node3D
var xp_value := 1.0

var _t := 0.0
var _speed := 0.0
var _vacuum := false
var _mat: StandardMaterial3D


## Force this orb to fly to the marine regardless of distance (wave-clear vacuum).
func vacuum() -> void:
	_vacuum = true


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLOR
	_mat.emission_enabled = true
	_mat.emission = COLOR
	_mat.emission_energy_multiplier = EMISSION_ENERGY
	material_override = _mat
	position.y = REST_Y


func _process(delta: float) -> void:
	_t += delta
	_animate(delta)                          # spin + twinkle, always
	if player == null or not is_instance_valid(player):
		_bob()
		return
	var to_player := player.global_position - global_position
	var dist := to_player.length()
	if not _vacuum and dist > MAGNET_RADIUS:
		_bob()
		return
	# Magnetised (in range or vacuuming): fly in, speed ramping up so it snaps to the marine.
	_speed = (minf(_speed + ACCEL * delta, SPEED_MAX)) if _speed > 0.0 else SPEED_MIN
	if dist > 0.001:
		global_position += to_player / dist * _speed * delta
	if dist <= COLLECT_RADIUS:
		if player.has_method("gain_xp"):
			player.gain_xp(xp_value)
		queue_free()


## Spin + a scale/emission twinkle — runs whether idle or flying in.
func _animate(delta: float) -> void:
	rotate_y(SPIN * delta)
	var s := sin(_t * PULSE_FREQ)
	scale = Vector3.ONE * (1.0 + s * PULSE_SCALE)
	if _mat != null:
		_mat.emission_energy_multiplier = EMISSION_ENERGY * (1.0 + s * PULSE_EMISSION)


## Hover-bob while waiting to be magnetised (flying overrides Y directly).
func _bob() -> void:
	position.y = REST_Y + sin(_t * BOB_FREQ) * BOB
