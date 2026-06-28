class_name Imp
extends Node3D
## A weak imp enemy: the optimized imp.glb model, walked + attacked entirely in a
## vertex shader (no skeleton — see imp_anim.gdshader). It drifts toward the player,
## and within ATTACK_RANGE plays a forward-jab attack pose (no damage yet). Registers
## in the "imps" group so weapons can target it and the off-screen indicator finds it.

signal died(world_pos: Vector3, xp_value: float, soul_value: int)   # for the XP-orb field; emitted once on death

const Gore := preload("res://src/fx/gore.gd")
const DamageNumberScript := preload("res://src/fx/damage_number.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const ObstacleFieldScript := preload("res://src/world/obstacle_field.gd")
const MODEL: PackedScene = preload("res://models/imp_opt.glb")
const ANIM_SHADER: Shader = preload("res://src/enemies/imp_anim.gdshader")

const GROUP := "imps"
const ENEMY_NAME := "Imp"        # display label for the recap's kills-by-type tally
const SPEED := 2.3           # drift toward the player (set 0 for static)
const EDGE_MARGIN := 0.6     # keep the imp this far inside the coast (can't chase onto the void)
const BODY_RADIUS := 0.4     # collision radius vs. columns + lava
const STOP_DIST := 0.8       # don't climb onto the player
const SEP_RADIUS := 1.2      # personal space — push apart inside this
const SEP_WEIGHT := 1.6      # how hard separation overrides the pull to the player
const BODY_COLOR := Color(0.45, 0.08, 0.08)   # blood/gib tint + albedo fallback if the model has no texture
const EMERGE_SCALE_FROM := 0.2   # materializes up from this scale while in the portal
const BASE_HP := 3.0             # wave-1 HP; one pistol bolt (dmg 5) one-shots it. Spawner scales it up per wave.
const BASE_XP := 1.0             # wave-1 XP value; the spawner scales it up per wave

# Model fitting + animation tuning (the glb's scale/orientation are unknown, so fit it).
const IMP_HEIGHT := 1.3      # model auto-scaled so its height = this (world units)
const MODEL_YAW := PI        # imp.glb faces +Z; PI turns it to face the player (-Z). jab dir follows.
const ATTACK_RANGE := 1.4    # within this distance it plays the attack jab
const ATTACK_SMOOTH := 6.0   # how fast it blends into / out of the attack pose
const ATTACK_COOLDOWN := 0.8 # seconds between melee hits on the player
const BASE_ATTACK_DAMAGE := 1.0  # wave-1 hit damage; the spawner scales it up per wave
const DEATH_TIME := 0.4      # how long the detached corpse takes to crumple + sink
const DMG_NUMBER_COLOR := Color(1.0, 0.95, 0.7)  # warm flying number for damage dealt to this imp

# Glowing eyes — socket location as fractions of the model's mesh AABB (so it tracks any
# model), turned into a mesh-local point in _build_model and painted by imp_anim.gdshader.
const EYE_X_FRAC := 0.20     # offset from the centreline, as a fraction of half-width
const EYE_Y_FRAC := 0.82     # height up the model (0 feet .. 1 crown)
const EYE_Z_FRAC := 0.82     # depth front..back (1 = front face, +Z)
const EYE_RADIUS := 0.10     # glow patch radius (mesh-local units)
const EYE_COLOR := Color(1.0, 0.6, 0.15)   # searing amber demon eyes
const EYE_ENERGY := 3.0      # emission energy; must clear the env glow_hdr_threshold to bloom

# Reaction to a hit that doesn't kill: a white flash, a shove back along the bolt,
# and a brief slow.
const HIT_FLASH_TIME := 0.12   # seconds of white hurt-flash
const DEATH_FLASH := 0.22      # white pop as it dies (same glow as a hit), fading out
const KNOCKBACK := 6.5         # initial shove speed (units/s) along the bolt's travel
const KNOCKBACK_DAMP := 14.0   # how fast the shove decays
const HIT_SLOW_TIME := 0.45    # seconds of reduced speed after a hit
const HIT_SLOW_FACTOR := 0.45  # speed multiplier while slowed

var player: Node3D
var obstacles: ObstacleFieldScript   # island columns/lava/rocks; set by the spawner
var max_hp := BASE_HP
var hp := BASE_HP                # set by the spawner per wave; depleted by take_damage()
var attack_damage := BASE_ATTACK_DAMAGE   # damage per melee hit; spawner scales per wave
var xp_value := BASE_XP          # XP this imp grants when killed; spawner scales per wave
var body_scale := 1.0            # full-grown node scale; spawner bumps it for elite-wave champions
var soul_value := 1              # souls this imp drops (1 + difficulty/champion bonus); spawner sets it
var _attack_cd := 0.0            # cooldown until this imp can hit the player again
var _dead := false
var _emerge := 0.0               # seconds left frozen in the spawn portal
var _emerge_total := 0.0
var _model: Node3D               # the instanced glb (detached as a corpse on death)
var _anim_mats: Array[ShaderMaterial] = []   # per-mesh shader materials we drive (attack uniform)
var _attack := 0.0               # 0 idle .. 1 attacking, smoothed
var _hit_flash := 0.0            # seconds left of the white hurt-flash
var _knock := Vector3.ZERO       # decaying knockback velocity from the last hit
var _slow := 0.0                 # seconds left of the post-hit slow
var _dmg_number: DamageNumberScript = null   # this imp's active floating number; repeated hits accumulate into it


func _ready() -> void:
	add_to_group(GROUP)
	_build_model()


## Killed by a projectile: leave gore, drop out of the target group, vanish.
## `blood_spatters` is set by the killing projectile (its type decides how gory);
## `hit_dir` is the bolt's travel direction so the blood + gibs spray forward.
## The defaults cover non-combat clears (e.g. wiping a wave → random spray dir).
func die(blood_spatters: int = 3, hit_dir: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return                          # guard: two bolts can land the same frame
	_dead = true
	remove_from_group(GROUP)            # stop other guns/bolts targeting a corpse
	died.emit(global_position, xp_value, soul_value)   # the orb field drops the XP orb + any bonus soul-motes here
	Gore.spawn_death(get_parent(), global_position, BODY_COLOR, blood_spatters, hit_dir)
	_spawn_corpse()                     # detach the body to crumple + sink on its own
	queue_free()


## Detach the model as an independent corpse that crumples (shader `death`) and sinks
## into the ground, then frees itself — so the imp node can die instantly (group/logic)
## while the body animates out. No-op if the rig/model is missing.
func _spawn_corpse() -> void:
	var parent := get_parent()
	if _model == null or parent == null:
		return
	var corpse := _model
	var mats := _anim_mats              # captured by the tween — does not touch this (freed) imp
	corpse.reparent(parent)             # keeps world transform; survives our queue_free()
	var set_death := func(v: float) -> void:
		for m in mats:
			m.set_shader_parameter("death", v)
	var set_hit := func(v: float) -> void:        # same white glow as a non-lethal hit
		for m in mats:
			m.set_shader_parameter("hit", v)
	var tw := corpse.create_tween().set_parallel(true)
	tw.tween_method(set_death, 0.0, 1.0, DEATH_TIME)
	tw.tween_method(set_hit, 1.0, 0.0, DEATH_FLASH)   # flash white on the killing blow, fading out
	tw.tween_property(corpse, "position:y", corpse.position.y - IMP_HEIGHT, DEATH_TIME).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(corpse.queue_free)


## Take `amount` damage; dies (with gore) when HP reaches 0, else survives the hit.
## blood_spatters/hit_dir are forwarded to the death spray only on the killing blow.
## Returns true if the hit was lethal (the imp died), false if it survived.
func take_damage(amount: float, blood_spatters: int = 3, hit_dir: Vector3 = Vector3.ZERO) -> bool:
	if _dead:
		return false
	if is_instance_valid(_dmg_number):
		_dmg_number.add(amount)                      # already showing -> accumulate into the one number
	else:
		_dmg_number = DamageNumberScript.spawn(get_parent(), global_position + Vector3(0.0, IMP_HEIGHT * 0.9, 0.0), amount, DMG_NUMBER_COLOR)
	hp -= amount
	if hp <= 0.0:
		die(blood_spatters, hit_dir)
		return true
	Gore.spawn_hit(get_parent(), global_position, BODY_COLOR, hit_dir)   # survived: 1 decal + flesh
	_react_to_hit(hit_dir)
	return false


## The enemy-type label for the recap's kills-by-type tally.
func enemy_type() -> String:
	return ENEMY_NAME


## Survived a hit: flash white, get shoved back along the bolt, and slow briefly.
func _react_to_hit(hit_dir: Vector3) -> void:
	_hit_flash = HIT_FLASH_TIME
	_slow = HIT_SLOW_TIME
	var d := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if d.length() > 0.001:
		_knock = d.normalized() * KNOCKBACK   # along travel = away from the shooter


## Spawn frozen in a portal for `duration` seconds, scaling up as it materializes.
## It won't move (or even turn) until fully emerged. Killable throughout.
func emerge(duration: float) -> void:
	_emerge = duration
	_emerge_total = duration
	scale = Vector3.ONE * (EMERGE_SCALE_FROM * body_scale)


func _process(delta: float) -> void:
	if _dead:
		return

	_update_hit_flash(delta)             # visual only; runs even while emerging

	# While materializing in the portal: scale up, hold still, don't steer.
	if _emerge > 0.0:
		_emerge -= delta
		var p := 1.0 - clampf(_emerge / _emerge_total, 0.0, 1.0)   # 0 -> 1
		scale = Vector3.ONE * (lerpf(EMERGE_SCALE_FROM, 1.0, p) * body_scale)
		if _emerge > 0.0:
			return
		scale = Vector3.ONE * body_scale

	if player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0

	# Steer toward the player, but pushed apart from nearby imps so they spread
	# out instead of overlapping into one clump. A recent hit slows the advance.
	var spd := SPEED
	if _slow > 0.0:
		_slow -= delta
		spd *= HIT_SLOW_FACTOR
	var steer := Vector3.ZERO
	if to_player.length() > STOP_DIST:
		steer += to_player.normalized()
	steer += _separation() * SEP_WEIGHT
	if steer.length() > 0.001:
		global_position += steer.normalized() * spd * delta

	# Knockback shove from the last hit, decaying out.
	if _knock.length() > 0.001:
		global_position += _knock * delta
		_knock = _knock.move_toward(Vector3.ZERO, KNOCKBACK_DAMP * delta)

	_clamp_to_island()                   # both the chase and the knockback stay on solid rock
	if obstacles != null:
		global_position = obstacles.resolve(global_position, BODY_RADIUS, IslandShape.surface_height(global_position.x, global_position.z))   # round columns/lava, climb rocks, follow the hills

	if to_player.length() > 0.05:
		rotation.y = atan2(-to_player.x, -to_player.z)   # always face the player (-Z forward)

	# Attack pose + melee hit in range: the vertex-shader jab, and a hit on cooldown.
	var in_range := to_player.length() <= ATTACK_RANGE
	var want_attack := 1.0 if in_range else 0.0
	_attack = move_toward(_attack, want_attack, delta * ATTACK_SMOOTH)
	for m in _anim_mats:
		m.set_shader_parameter("attack", _attack)   # ponytail: per-imp uniform; becomes INSTANCE_CUSTOM under MultiMesh

	_attack_cd -= delta
	if in_range and _attack_cd <= 0.0:
		_attack_cd = ATTACK_COOLDOWN
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)


## Keep the imp inside the coastline so it can't chase (or get knocked) onto the
## void. Same IslandShape the mesh is built from, in world space (the imp steers via
## global_position) — matches the marine's edge clamp and the visible edge exactly.
func _clamp_to_island() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() < 0.001:
		return
	var max_r: float = IslandShape.radius(atan2(global_position.z, global_position.x)) - EDGE_MARGIN
	if flat.length() > max_r:
		var clamped := flat.normalized() * max_r
		global_position.x = clamped.x
		global_position.z = clamped.y      # flat is Vector2(x, z) — .y holds world Z


## Decay the white hurt-flash and push it to the shader (0 when not flashing).
func _update_hit_flash(delta: float) -> void:
	if _hit_flash <= 0.0:
		return
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	var f := _hit_flash / HIT_FLASH_TIME
	for m in _anim_mats:
		m.set_shader_parameter("hit", f)


## Sum of repulsion from imps inside SEP_RADIUS (stronger the closer they are).
## ponytail: O(n) per imp -> O(n^2)/frame for the swarm; fine at these wave sizes,
## swap to a spatial grid if waves reach the many-hundreds.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(GROUP):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < SEP_RADIUS:
			push += away.normalized() * (1.0 - d / SEP_RADIUS)
	return push


## Instance the imp model, fit it to size/ground, and swap each mesh to the
## walk/attack vertex shader (keeping its base-colour texture).
func _build_model() -> void:
	var model: Node3D = MODEL.instantiate()
	add_child(model)
	_fit_model(model)
	_model = model

	var fdir := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, -MODEL_YAW)   # node-forward, in mesh-local space
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		var tex := _albedo_of(mesh_inst)
		var mat := ShaderMaterial.new()
		mat.shader = ANIM_SHADER
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("tint", Vector3(1.0, 1.0, 1.0) if tex != null
			else Vector3(BODY_COLOR.r, BODY_COLOR.g, BODY_COLOR.b))
		mat.set_shader_parameter("phase", randf() * TAU)
		mat.set_shader_parameter("face_dir", fdir)
		# Mesh-local foot/height so the shader's walk knows where legs vs torso are.
		var a := mesh_inst.get_aabb()
		mat.set_shader_parameter("local_min_y", a.position.y)
		mat.set_shader_parameter("local_height", a.size.y)
		# Eye socket point (mesh-local); shader mirrors it across x=0 for the second eye.
		mat.set_shader_parameter("eye_pos", Vector3(
			EYE_X_FRAC * a.size.x * 0.5,
			a.position.y + EYE_Y_FRAC * a.size.y,
			a.position.z + EYE_Z_FRAC * a.size.z))
		mat.set_shader_parameter("eye_radius", EYE_RADIUS)
		mat.set_shader_parameter("eye_emission", Vector3(EYE_COLOR.r, EYE_COLOR.g, EYE_COLOR.b))
		mat.set_shader_parameter("eye_energy", EYE_ENERGY)
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # imps cast no shadow
		mesh_inst.material_override = mat
		_anim_mats.append(mat)


## Scale the model so its height = IMP_HEIGHT and sit its base on the ground, so any
## generated model (unknown scale) drops in right. Yaw by MODEL_YAW to face the player.
func _fit_model(model: Node3D) -> void:
	model.rotation.y = MODEL_YAW
	var aabb := _merged_aabb(model)
	if aabb.size.y > 0.001:
		var s := IMP_HEIGHT / aabb.size.y
		model.scale = Vector3(s, s, s)
		model.position.y = -aabb.position.y * s   # min.y -> ground (Y-rotation doesn't change Y extent)


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


## The mesh's base-colour texture (so the shader keeps the painted look), or null.
func _albedo_of(mi: MeshInstance3D) -> Texture2D:
	var m := mi.get_active_material(0)
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null
