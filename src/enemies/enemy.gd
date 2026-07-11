class_name Enemy
extends Node3D
## Shared chaser-enemy AI (no skeleton): drift toward the player with swarm
## separation, stay on the island, take damage + die into gore, freeze in a spawn
## portal while emerging, and jab in melee range — all animated in imp_anim.gdshader.
## Imp and Zombie subclass this: each sets its tunables in _configure() and supplies a
## model via _model_scene(). Per-enemy BASE_HP / BASE_ATTACK_DAMAGE / BASE_XP /
## ENEMY_NAME stay as consts on the SUBCLASS so the spawner can read them. The base var
## defaults are the imp's tuning (the imp is the "default" enemy); the zombie overrides
## what differs. Joins group "imps" so guns/indicators/spawner/recap find both types.

signal died(world_pos: Vector3, xp_value: float, soul_value: int)   # for the XP-orb field; once on death

enum LeapState { NORMAL, CHARGING, LEAPING }   # the charged-pounce special's phase (see begin_leap)

const Gore := preload("res://src/fx/gore.gd")
const DamageNumberScript := preload("res://src/fx/damage_number.gd")
const IslandShape := preload("res://src/lib/island_shape.gd")
const ObstacleFieldScript := preload("res://src/world/obstacle_field.gd")
const ANIM_SHADER: Shader = preload("res://src/enemies/imp_anim.gdshader")
const LeapTelegraph := preload("res://src/fx/leap_telegraph.gd")
const BuffAura := preload("res://src/fx/buff_aura.gd")

const GROUP := "imps"            # both enemy types join this; everything that targets enemies keys on it

# Knockback diminishing returns: repeated knockbacks inside a rolling KB_WINDOW get
# weaker, so sustained fire can't permanently shove a monster. The Nth knockback in the
# window is scaled by KB_FALLOFF (1st full, 2nd -50%, 3rd+ -100%); a >KB_WINDOW lull resets it.
const KB_WINDOW := 5.0
const KB_FALLOFF: Array[float] = [1.0, 0.5, 0.0]

# Leap special — a charged, telegraphed pounce. The LeapCoordinator grants one at a time
# (a global cooldown) and tells the chosen enemy to begin_leap(target). The target is
# LOCKED when the charge starts, so a moving player dodges into open ground. See
# leap_coordinator.gd + leap_telegraph.gd. (Shared by all enemy types in group GROUP.)
const LEAP_CHARGE_TIME := 1.1     # seconds the telegraph bar fills before the jump
const LEAP_TIME := 0.3            # airborne seconds (ballistic hop to the locked point)
const LEAP_ARC_HEIGHT := 2.5      # peak height of the hop (world units)
const LEAP_HIT_RADIUS := 1.5      # player within this of the landing point takes the hit
const LEAP_DAMAGE_MULT := 2.5     # leap hit = this × the (wave-scaled) melee damage
const LEAP_LAND_SQUASH := 0.15    # seconds of landing-squash after touchdown
const LEAP_STOP := 1.1            # land this far short of the player — beside it, never on top of/inside it

# Buff special (zombie) — stand still and channel, then haste every OTHER enemy nearby.
# The BuffCoordinator grants one at a time (a 25s global cooldown) and tells the chosen
# zombie to begin_channel(). Only zombies channel (can_special_buff); the caster is
# excluded from its own buff. See buff_coordinator.gd + buff_aura.gd.
const BUFF_CHANNEL_TIME := 3.0    # seconds the zombie stands still channelling
const BUFF_RANGE := 6.0           # enemies within this of the caster get hasted
const BUFF_MULT := 1.6            # +60% move speed
const BUFF_DURATION := 12.0       # seconds the speed buff lasts on each recipient

# --- spawner-set combat numbers (the spawner writes these after new(), before _ready) ---
var player: Node3D
var obstacles: ObstacleFieldScript   # island columns/lava/rocks; set by the spawner
var max_hp := 3.0
var hp := 3.0
var attack_damage := 1.0
var xp_value := 1.0
var body_scale := 1.0            # full-grown node scale; spawner bumps it for champions
var soul_value := 1

# --- per-enemy tunables (subclass overrides in _configure(); defaults = imp) ---
var speed := 2.3
var edge_margin := 0.6
var body_radius := 0.4
var stop_dist := 0.8
var sep_radius := 1.2
var sep_weight := 1.6
var body_color := Color(0.45, 0.08, 0.08)   # gib/blood tint + albedo fallback when the model has no texture
var body_tint := Color(1.0, 1.0, 1.0)       # multiplies the textured model albedo (white = untinted); subclass shifts it
var tint_mix := 0.0                          # 0 = keep the texture; 1 = flat body_tint (lerps past a dark texture)
var emerge_scale_from := 0.2
var model_height := 1.3          # model auto-scaled so its height = this
var model_yaw := PI              # turns model-forward to face the player (-Z)
var attack_range := 1.4
var attack_smooth := 6.0
var attack_cooldown := 0.8
var death_time := 0.4
var dmg_number_color := Color(1.0, 0.95, 0.7)
var eye_x_frac := 0.20
var eye_y_frac := 0.82
var eye_z_frac := 0.82
var eye_radius := 0.10
var eye_color := Color(1.0, 0.6, 0.15)
var eye_energy := 3.0
var hit_flash_time := 0.12
var death_flash := 0.22
var knockback := 6.5
var knockback_damp := 14.0
var hit_slow_time := 0.45
var hit_slow_factor := 0.45
# shader gait knobs — defaults == the shader's defaults == the imp's gait
var walk_freq := 8.0
var stride := 0.18
var twist := 0.22
var lean_run := 0.16
var bob := 0.08
var squash := 0.10
var lunge_rate := 1.8
var lunge_reach := 0.45
var can_special_leap := true     # this enemy type may be picked for the charged pounce (imp = yes; zombie opts out)
var can_special_buff := false    # this enemy type may be picked for the AoE haste channel (zombie = yes)

# --- internal state ---
var _attack_cd := 0.0
var _dead := false
var _emerge := 0.0
var _emerge_total := 0.0
var _model: Node3D
var _anim_mats: Array[ShaderMaterial] = []
var _attack := 0.0
var _hit_flash := 0.0
var _knock := Vector3.ZERO
var _slow := 0.0
var _kb_recent := 0               # knockbacks landed inside the current KB_WINDOW
var _kb_window := 0.0             # seconds left in the rolling knockback window (each hit refreshes it)
var _dmg_number: DamageNumberScript = null

# Leap special — driven entirely by the LeapCoordinator calling begin_leap()/is_leaping();
# the enemy needs no back-reference to it. No coordinator in the tree -> these stay idle.
var _leap_state: LeapState = LeapState.NORMAL
var _leap_t := 0.0               # countdown within the current leap phase
var _leap_from := Vector3.ZERO   # leap start position (set when airborne)
var _leap_to := Vector3.ZERO     # LOCKED landing point = a spot just short of the player at charge start
var _leap_peak := LEAP_ARC_HEIGHT   # this hop's arc height (scaled to its distance in _start_airborne)
var _leap_squash := 0.0          # seconds left of the landing squash
var _telegraph: Node3D = null    # the ground telegraph FX while charging

# Buff special — the zombie's channel + the haste any enemy can receive from it.
var _channeling := false         # this (zombie) is standing still, casting the AoE buff
var _channel_t := 0.0            # seconds left in the channel
var _buff_t := 0.0               # seconds left of a received speed buff
var _buff_mult := 1.0            # current speed multiplier while _buff_t > 0
var _aura: Node3D = null         # the cast-aura FX while channelling


func _ready() -> void:
	_configure()
	add_to_group(GROUP)
	_build_model()


## Subclass hook: set this enemy's tunables (default = imp). Runs in _ready, AFTER the
## spawner has set max_hp/hp/attack_damage/xp_value — so NEVER touch those here.
func _configure() -> void:
	pass


## Subclass hook: the model scene to instance (null = no model).
func _model_scene() -> PackedScene:
	return null


## Subclass hook: the recap's kills-by-type label.
func enemy_type() -> String:
	return "Enemy"


## Subclass hook: the death gore. Default = a single-tint chunk burst (the imp's).
func _spawn_gore(gore_amount: int, hit_dir: Vector3) -> void:
	Gore.spawn_death(get_parent(), global_position, body_color, gore_amount, hit_dir)


## Killed by a projectile: leave gore, drop out of the target group, vanish.
func die(gore_amount: int = 3, hit_dir: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return                          # guard: two bolts can land the same frame
	_dead = true
	if is_instance_valid(_telegraph):   # killed mid-charge -> drop the telegraph (coordinator re-arms)
		_telegraph.queue_free()
		_telegraph = null
	if is_instance_valid(_aura):        # killed mid-channel -> drop the aura (coordinator re-arms)
		_aura.queue_free()
		_aura = null
	remove_from_group(GROUP)
	died.emit(global_position, xp_value, soul_value)
	_spawn_gore(gore_amount, hit_dir)
	_spawn_corpse()
	queue_free()


## Detach the model as an independent corpse that crumples (shader `death`) and sinks,
## then frees itself — so the enemy node can die instantly while the body animates out.
func _spawn_corpse() -> void:
	var parent := get_parent()
	if _model == null or parent == null:
		return
	var corpse := _model
	var mats := _anim_mats
	corpse.reparent(parent)
	var set_death := func(v: float) -> void:
		for m in mats:
			m.set_shader_parameter("death", v)
	var set_hit := func(v: float) -> void:
		for m in mats:
			m.set_shader_parameter("hit", v)
	var tw := corpse.create_tween().set_parallel(true)
	tw.tween_method(set_death, 0.0, 1.0, death_time)
	tw.tween_method(set_hit, 1.0, 0.0, death_flash)
	tw.tween_property(corpse, "position:y", corpse.position.y - model_height, death_time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(corpse.queue_free)


## Take `amount` damage; dies (with gore) at <= 0 HP, else survives. Returns true if lethal.
func take_damage(amount: float, gore_amount: int = 3, hit_dir: Vector3 = Vector3.ZERO) -> bool:
	if _dead:
		return false
	if is_instance_valid(_dmg_number):
		_dmg_number.add(amount)
	else:
		_dmg_number = DamageNumberScript.spawn(get_parent(), global_position + Vector3(0.0, model_height * 0.9, 0.0), amount, dmg_number_color)
	hp -= amount
	if hp <= 0.0:
		die(gore_amount, hit_dir)
		return true
	Gore.spawn_hit(get_parent(), global_position, body_color, hit_dir)
	_react_to_hit(hit_dir)
	return false


## Survived a hit: flash white, get shoved back along the bolt, slow briefly. Repeated
## knockbacks inside KB_WINDOW are scaled down by KB_FALLOFF (2nd -50%, 3rd+ -100%).
func _react_to_hit(hit_dir: Vector3) -> void:
	_hit_flash = hit_flash_time
	_slow = hit_slow_time
	var d := Vector3(hit_dir.x, 0.0, hit_dir.z)
	if d.length() > 0.001:
		if _kb_window <= 0.0:
			_kb_recent = 0                    # window lapsed -> this knockback is fresh
		_kb_recent += 1
		_kb_window = KB_WINDOW                 # each knockback refreshes the rolling window
		var factor: float = KB_FALLOFF[mini(_kb_recent - 1, KB_FALLOFF.size() - 1)]
		_knock = d.normalized() * knockback * factor


## Spawn frozen in a portal for `duration` seconds, scaling up as it materializes.
func emerge(duration: float) -> void:
	_emerge = duration
	_emerge_total = duration
	scale = Vector3.ONE * (emerge_scale_from * body_scale)


# --- Leap special (charged pounce) — the LeapCoordinator's handle on this enemy ----------

## Eligible to be told to leap: alive, fully emerged, and not already leaping.
func can_leap() -> bool:
	return not _dead and _emerge <= 0.0 and _leap_state == LeapState.NORMAL


## True while charging or airborne — the coordinator holds its single token until this clears.
func is_leaping() -> bool:
	return _leap_state != LeapState.NORMAL


## Start the charge: lock the target (player pos NOW) and raise the ground telegraph. A
## moving player walks out of the locked landing zone before the jump lands.
func begin_leap(target: Vector3) -> void:
	_leap_state = LeapState.CHARGING
	_leap_t = LEAP_CHARGE_TIME
	# Land just SHORT of the player, not on top of it: pull the landing point back along
	# the imp->player line by LEAP_STOP so the imp ends up beside the marine.
	var dir := target - global_position
	dir.y = 0.0
	var dist := dir.length()
	if dist > 0.001:
		_leap_to = global_position + (dir / dist) * maxf(dist - LEAP_STOP, 0.0)
	else:
		_leap_to = target
	_attack = 0.0                              # drop any half-played melee jab while coiling
	_set_anim("attack", 0.0)
	var parent := get_parent()
	if parent != null:
		_telegraph = LeapTelegraph.new()
		parent.add_child(_telegraph)
		_telegraph.setup(global_position, _leap_to)


## Step charge -> airborne -> land; rooted then ballistic, no normal steering/melee.
func _process_leap(delta: float) -> void:
	_leap_t -= delta
	if _leap_state == LeapState.CHARGING:
		var p := 1.0 - clampf(_leap_t / LEAP_CHARGE_TIME, 0.0, 1.0)   # 0 -> 1 as the bar fills
		_set_anim("charge", p)
		var d := _leap_to - global_position
		d.y = 0.0
		if d.length() > 0.05:
			rotation.y = atan2(-d.x, -d.z)     # face the locked target while coiling
		if is_instance_valid(_telegraph):
			_telegraph.set_progress(p)
		if _leap_t <= 0.0:
			_start_airborne()
	else:                                       # LEAPING
		var p := 1.0 - clampf(_leap_t / LEAP_TIME, 0.0, 1.0)
		_set_anim("leap", p)
		var flat := _leap_from.lerp(_leap_to, p)
		var arc := _leap_peak * 4.0 * p * (1.0 - p)                  # parabola, peak mid-hop
		global_position = Vector3(flat.x, IslandShape.surface_height(flat.x, flat.z) + arc, flat.z)
		if _leap_t <= 0.0:
			_land()


## Charge filled — launch toward the locked point and flash off the telegraph.
func _start_airborne() -> void:
	_set_anim("charge", 0.0)
	_leap_state = LeapState.LEAPING
	_leap_t = LEAP_TIME
	_leap_from = global_position
	var jump := Vector2(_leap_to.x - _leap_from.x, _leap_to.z - _leap_from.z).length()
	_leap_peak = clampf(jump * 0.35, 0.5, LEAP_ARC_HEIGHT)          # short hop = low arc, long = higher
	if is_instance_valid(_telegraph):
		_telegraph.fire()
		_telegraph = null


## Touchdown: settle on the ground, hit the player if they're still in the landing zone,
## kick off the squash, and go back to NORMAL so the coordinator releases its token.
func _land() -> void:
	_set_anim("leap", 0.0)
	_leap_state = LeapState.NORMAL
	global_position.y = IslandShape.surface_height(global_position.x, global_position.z)
	if obstacles != null:
		global_position = obstacles.resolve(global_position, body_radius, IslandShape.surface_height(global_position.x, global_position.z))
	_leap_squash = LEAP_LAND_SQUASH
	if player != null and player.has_method("take_damage"):
		var d := player.global_position - global_position
		d.y = 0.0
		if d.length() <= LEAP_HIT_RADIUS:
			player.take_damage(attack_damage * LEAP_DAMAGE_MULT)
			_attack_cd = attack_cooldown        # don't also melee on the landing frame


## Decay the brief landing squash, reusing the `charge` crouch as a touchdown compress.
func _update_landing_squash(delta: float) -> void:
	if _leap_squash <= 0.0:
		return
	_leap_squash = maxf(_leap_squash - delta, 0.0)
	_set_anim("charge", (_leap_squash / LEAP_LAND_SQUASH) * 0.6)


## Push a shader uniform to every mesh material (the leap charge/leap poses).
func _set_anim(param: String, value: float) -> void:
	for m in _anim_mats:
		m.set_shader_parameter(param, value)


# --- Buff special (zombie AoE haste channel) — the BuffCoordinator's handle -------------

## Eligible to be told to channel: alive, fully emerged, not leaping, not already channelling.
func can_channel() -> bool:
	return not _dead and _emerge <= 0.0 and _leap_state == LeapState.NORMAL and not _channeling


## True while channelling — the coordinator holds its single token until this clears.
func is_channeling() -> bool:
	return _channeling


## Start the stand-still channel and raise the cast aura. _process_channel() finishes it.
func begin_channel() -> void:
	_channeling = true
	_channel_t = BUFF_CHANNEL_TIME
	_attack = 0.0
	_set_anim("attack", 0.0)
	var parent := get_parent()
	if parent != null:
		_aura = BuffAura.new()
		parent.add_child(_aura)
		_aura.global_position = global_position


## Rooted channel; at the end, haste every OTHER enemy within BUFF_RANGE and burst the aura.
func _process_channel(delta: float) -> void:
	_channel_t -= delta
	var p := 1.0 - clampf(_channel_t / BUFF_CHANNEL_TIME, 0.0, 1.0)   # 0 -> 1
	_set_anim("cast", p)
	if is_instance_valid(_aura):
		_aura.set_progress(p)
	if _channel_t <= 0.0:
		_finish_channel()


func _finish_channel() -> void:
	_channeling = false
	_set_anim("cast", 0.0)
	for other in get_tree().get_nodes_in_group(GROUP):
		if other == self or not is_instance_valid(other):
			continue
		if (other.global_position - global_position).length() <= BUFF_RANGE:
			other.apply_speed_buff(BUFF_MULT, BUFF_DURATION)   # the caster excludes itself (other == self)
	if is_instance_valid(_aura):
		_aura.burst(BUFF_RANGE)
		_aura = null


## Receive a speed buff from a channelling zombie. Re-applying refreshes to the longer timer.
func apply_speed_buff(mult: float, duration: float) -> void:
	_buff_mult = mult
	_buff_t = maxf(_buff_t, duration)


func _process(delta: float) -> void:
	if _dead:
		return
	_update_hit_flash(delta)
	if _kb_window > 0.0:
		_kb_window -= delta                  # rolling knockback window decays even while emerging
	if _emerge > 0.0:
		_emerge -= delta
		var p := 1.0 - clampf(_emerge / _emerge_total, 0.0, 1.0)
		scale = Vector3.ONE * (lerpf(emerge_scale_from, 1.0, p) * body_scale)
		if _emerge > 0.0:
			return
		scale = Vector3.ONE * body_scale

	if _channeling:                           # zombie casting the AoE buff -> rooted
		_process_channel(delta)
		return
	_update_landing_squash(delta)
	if _leap_state != LeapState.NORMAL:       # charging or airborne -> the leap owns movement
		_process_leap(delta)
		return

	if player == null:
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var spd := speed
	if _buff_t > 0.0:                         # hasted by a zombie's channel
		_buff_t -= delta
		spd *= _buff_mult
	_set_anim("buffed", clampf(_buff_t / BUFF_DURATION, 0.0, 1.0))   # cyan marker glow (gait unchanged)
	if _slow > 0.0:
		_slow -= delta
		spd *= hit_slow_factor
	var steer := Vector3.ZERO
	if to_player.length() > stop_dist:
		steer += to_player.normalized()
	steer += _separation() * sep_weight
	if steer.length() > 0.001:
		global_position += steer.normalized() * spd * delta
	if _knock.length() > 0.001:
		global_position += _knock * delta
		_knock = _knock.move_toward(Vector3.ZERO, knockback_damp * delta)
	_clamp_to_island()
	if obstacles != null:
		global_position = obstacles.resolve(global_position, body_radius, IslandShape.surface_height(global_position.x, global_position.z))
	if to_player.length() > 0.05:
		rotation.y = atan2(-to_player.x, -to_player.z)   # face the player (-Z forward)
	var in_range := to_player.length() <= attack_range
	var want_attack := 1.0 if in_range else 0.0
	_attack = move_toward(_attack, want_attack, delta * attack_smooth)
	for m in _anim_mats:
		m.set_shader_parameter("attack", _attack)
	_attack_cd -= delta
	if in_range and _attack_cd <= 0.0:
		_attack_cd = attack_cooldown
		if player.has_method("take_damage"):
			player.take_damage(attack_damage)


## Keep the enemy inside the coastline so it can't chase (or get knocked) onto the void.
func _clamp_to_island() -> void:
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() < 0.001:
		return
	var max_r: float = IslandShape.radius(atan2(global_position.z, global_position.x)) - edge_margin
	if flat.length() > max_r:
		var clamped := flat.normalized() * max_r
		global_position.x = clamped.x
		global_position.z = clamped.y      # flat is Vector2(x, z) — .y holds world Z


## Decay the white hurt-flash and push it to the shader (0 when not flashing).
func _update_hit_flash(delta: float) -> void:
	if _hit_flash <= 0.0:
		return
	_hit_flash = maxf(_hit_flash - delta, 0.0)
	var f := _hit_flash / hit_flash_time
	for m in _anim_mats:
		m.set_shader_parameter("hit", f)


## Sum of repulsion from enemies inside sep_radius (stronger the closer they are).
## ponytail: O(n) per enemy -> O(n^2)/frame; fine at these wave sizes.
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for other in get_tree().get_nodes_in_group(GROUP):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector3 = global_position - (other as Node3D).global_position
		away.y = 0.0
		var d := away.length()
		if d > 0.001 and d < sep_radius:
			push += away.normalized() * (1.0 - d / sep_radius)
	return push


## Instance the model, fit it to size/ground, and swap each mesh to the walk/attack
## vertex shader (keeping its base-colour texture). Sets the gait uniforms from this
## enemy's vars (imp = shader defaults; zombie overrides).
func _build_model() -> void:
	var scene := _model_scene()
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	add_child(model)
	_fit_model(model)
	_model = model
	var fdir := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, -model_yaw)   # node-forward in mesh-local space
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		var tex := _albedo_of(mesh_inst)
		var mat := ShaderMaterial.new()
		mat.shader = ANIM_SHADER
		mat.set_shader_parameter("albedo_tex", tex)
		mat.set_shader_parameter("tint", Vector3(body_tint.r, body_tint.g, body_tint.b) if tex != null
			else Vector3(body_color.r, body_color.g, body_color.b))
		mat.set_shader_parameter("tint_mix", tint_mix)
		mat.set_shader_parameter("phase", randf() * TAU)
		mat.set_shader_parameter("face_dir", fdir)
		mat.set_shader_parameter("walk_freq", walk_freq)
		mat.set_shader_parameter("stride", stride)
		mat.set_shader_parameter("twist", twist)
		mat.set_shader_parameter("lean_run", lean_run)
		mat.set_shader_parameter("bob", bob)
		mat.set_shader_parameter("squash", squash)
		mat.set_shader_parameter("lunge_rate", lunge_rate)
		mat.set_shader_parameter("lunge_reach", lunge_reach)
		var a := mesh_inst.get_aabb()
		mat.set_shader_parameter("local_min_y", a.position.y)
		mat.set_shader_parameter("local_height", a.size.y)
		mat.set_shader_parameter("eye_pos", Vector3(
			eye_x_frac * a.size.x * 0.5,
			a.position.y + eye_y_frac * a.size.y,
			a.position.z + eye_z_frac * a.size.z))
		mat.set_shader_parameter("eye_radius", eye_radius)
		mat.set_shader_parameter("eye_emission", Vector3(eye_color.r, eye_color.g, eye_color.b))
		mat.set_shader_parameter("eye_energy", eye_energy)
		mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_inst.material_override = mat
		_anim_mats.append(mat)


## Scale the model so its height = model_height and sit its base on the ground.
func _fit_model(model: Node3D) -> void:
	model.rotation.y = model_yaw
	var aabb := _merged_aabb(model)
	if aabb.size.y > 0.001:
		var s := model_height / aabb.size.y
		model.scale = Vector3(s, s, s)
		model.position.y = -aabb.position.y * s   # min.y -> ground


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
