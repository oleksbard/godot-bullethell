class_name Hud
extends CanvasLayer
## Gameplay HUD — top-left cluster + full-width XP strip:
##   * XP bar    — thin ember-gold strip pinned to the top edge
##   * Portrait  — small animated 3D marine in an ember-framed box (its own
##                 SubViewport, idle sway + bob)
##   * LV badge  — circular level medallion on the portrait's bottom-right corner
##   * LVL UP    — a stack of up-arrow medals under the HP bar (one per level gained this
##                 wave) + a centred "LEVEL UP!" banner on level-up
##   * Wave      — "WAVE N" readout centred at the top
##   * HP bar    — crimson, to the right of the portrait, with "hp / max" text
## Binds to a PlayerStats via signals; set `stats` before adding to the tree.
## Reuses the pause-menu ember palette + the Oswald default font for consistency.
##
## The XP bar is ANIMATED: it slides toward the player's lifetime XP, and the
## level-up flourish (badge punch, medal, banner) + the `level_reached` signal
## (which opens the level-up menu) fire only when the bar actually reaches 100%.

## Emitted when the animated XP bar fills a level (NOT the instant a threshold is
## crossed). Main wires this to the level-up menu so the modal opens on a full bar.
signal level_reached(level: int)

const MarineModel: PackedScene = preload("res://models/marine_01.glb")
const StatusIconScript := preload("res://src/ui/status_icon.gd")
const RELOAD_ICON: Texture2D = preload("res://art/ui/reload.svg")   # game-icons.net reload-gun-barrel
const SOUL_ICON: Texture2D = preload("res://art/ui/soul.svg")       # game-icons.net spectre — the souls glyph

# Palette (matches pause_menu.gd).
const EMBER := Color(1.0, 0.45, 0.2)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const PANEL_BG := Color(0.06, 0.02, 0.02, 0.92)
const TRACK_BG := Color(0.03, 0.01, 0.01, 0.9)
const HP_FILL := Color(0.8, 0.09, 0.06)
const XP_FILL := Color(1.0, 0.62, 0.16)
const SOUL := Color(0.2, 0.85, 1.0)        # cold cyan — matches the collected soul-motes (xp_orb.gd)
const SOUL_RIM := Color(0.7, 0.97, 1.0)

# Layout.
const MARGIN := 12
const XP_HEIGHT := 10
const PORTRAIT := 116
const HP_SIZE := Vector2(360, 40)
const LVLUP_MAX := 10       # cap the level-up medal stack so it can't overflow
const LVLUP_STACK_OFFSET := 10   # px each stacked medal is shifted right of the one below
const STATUS_SIZE := 72    # buff/debuff badge size — much bigger than a 34px level-up medal

# Portrait framing — a face/mug shot aimed at the rig's Head bone. Distances are
# fractions of head height so it stays framed whatever the model's scale.
const FACE_FOV := 30.0
const FACE_DIST_FRAC := 0.34   # camera distance in front, as a fraction of head height
const FACE_RAISE_FRAC := 0.05  # aim a touch above the Head bone (skull base -> face)
const FALLBACK_HEAD := Vector3(0.0, 1.6, 0.0)  # used if the rig has no Head bone
const SWAY := 0.16          # idle head turn (radians)
const BOB := 0.02           # idle vertical bob (metres)
const XP_FILL_PER_SEC := 1.6   # XP-bar fill speed, in bars/sec (a full bar slides in ~0.6 s)

var stats: Node             # PlayerStats; set before add_child
var weapon_ring: Node       # WeaponRing; set by Main — polled for the reload debuff

var _hp: ProgressBar
var _hp_label: Label
var _xp: ProgressBar
var _lv: Label              # the number inside the medallion
var _lv_badge: Panel        # circular level medallion (overlaps the portrait corner)
var _wave_label: Label      # "WAVE N", top-centre
var _lvlup_stack: Control   # per-wave level-up medals, stacked under the HP bar
var _reload_icon: StatusIconScript   # reload debuff badge, in the same row as the medals
var _souls_orb: TextureRect # cyan soul glyph in the top-right counter
var _souls_count: Label     # banked-souls number beside it
var _portrait: Node3D
var _t := 0.0

# Animated XP bar state. The bar shows _xp_disp (lifetime XP), sliding toward
# _xp_target; _xp_level is the level the bar currently sits in.
var _xp_target := 0.0       # authoritative lifetime XP (from PlayerStats.total_xp)
var _xp_disp := 0.0         # lifetime XP the bar currently represents (animated)
var _xp_level := 1          # level the animated bar is currently filling
var _xp_level_start := 0.0  # lifetime XP at the start of _xp_level
var _xp_to_next := 16.0     # XP span of _xp_level (stats.xp_for(_xp_level)); seeded in _init_xp_display


func _ready() -> void:
	_build()
	if stats == null:
		return
	stats.health_changed.connect(_on_health)
	stats.xp_changed.connect(_on_xp)
	stats.souls_changed.connect(_on_souls)
	_on_health(stats.health, stats.max_health)   # pull the current state once
	_init_xp_display()
	_souls_count.text = str(stats.souls)          # initial count (no pop on bind)


func _process(delta: float) -> void:
	_animate_xp(delta)
	_update_reload_debuff()
	if _portrait == null:
		return
	_t += delta
	_portrait.rotation.y = sin(_t * 0.8) * SWAY
	_portrait.position.y = absf(sin(_t * 1.6)) * BOB


## Slide the bar toward the target lifetime XP. When it reaches the end of the
## current level (a full bar), stop exactly on the boundary, advance a level, and
## fire the flourish + level_reached — so the level-up only ever shows at 100%.
## (While the level-up menu is open the tree is paused, so this naturally halts at
## the full bar until the player continues.)
func _animate_xp(delta: float) -> void:
	if _xp_disp >= _xp_target:
		return
	_xp_disp = minf(_xp_disp + _xp_to_next * XP_FILL_PER_SEC * delta, _xp_target)
	if _xp_disp - _xp_level_start >= _xp_to_next:
		_xp_disp = _xp_level_start + _xp_to_next      # land exactly on the boundary (no overshoot)
		_xp.max_value = _xp_to_next
		_xp.value = _xp_to_next                       # show the full bar this frame
		_xp_level += 1
		_xp_level_start += _xp_to_next
		_xp_to_next = stats.xp_for(_xp_level)
		_present_level_up(_xp_level)
	else:
		_update_xp_bar()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_xp(root)
	_build_portrait(root)
	_build_hp(root)
	_build_level_badge(root)
	_build_wave_label(root)
	_build_lvlup_stack(root)
	_build_status_row(root)
	_build_souls(root)


func _build_xp(root: Control) -> void:
	_xp = ProgressBar.new()
	_xp.show_percentage = false
	_xp.anchor_right = 1.0
	_xp.offset_bottom = XP_HEIGHT
	_xp.add_theme_stylebox_override("background", _flat(TRACK_BG, EMBER_DIM, 0, 0))
	_xp.add_theme_stylebox_override("fill", _flat(XP_FILL, XP_FILL, 0, 0))
	root.add_child(_xp)


func _build_portrait(root: Control) -> void:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _flat(PANEL_BG, EMBER, 2, 4))
	panel.position = Vector2(MARGIN, XP_HEIGHT + MARGIN)
	panel.size = Vector2(PORTRAIT, PORTRAIT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.offset_left = 4
	svc.offset_top = 4
	svc.offset_right = -4
	svc.offset_bottom = -4
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(svc)

	var sv := SubViewport.new()
	sv.transparent_bg = true
	sv.own_world_3d = true                       # isolate from the hell scene
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.msaa_3d = Viewport.MSAA_2X
	svc.add_child(sv)

	_portrait = MarineModel.instantiate()        # static T-pose, swayed in _process
	sv.add_child(_portrait)

	var cam := Camera3D.new()
	cam.fov = FACE_FOV
	cam.current = true
	sv.add_child(cam)
	_frame_face(cam)

	var key := DirectionalLight3D.new()          # warm ember key from the front
	key.light_color = Color(1.0, 0.6, 0.35)
	key.light_energy = 2.0
	key.rotation_degrees = Vector3(-25.0, -20.0, 0.0)
	sv.add_child(key)

	var fill := DirectionalLight3D.new()         # dim cool fill from the other side
	fill.light_color = Color(0.4, 0.45, 0.6)
	fill.light_energy = 0.6
	fill.rotation_degrees = Vector3(-15.0, 35.0, 0.0)
	sv.add_child(fill)


## Aim the portrait camera at the rig's Head bone for a face close-up. Reads the
## real bone position (correct at any model scale); falls back to FALLBACK_HEAD if
## the rig has no Head bone.
func _frame_face(cam: Camera3D) -> void:
	var head := FALLBACK_HEAD
	var skels := _portrait.find_children("*", "Skeleton3D", true, false)
	if not skels.is_empty():
		var skel := skels[0] as Skeleton3D
		var hb := skel.find_bone("Head")
		if hb != -1:
			head = skel.global_transform * skel.get_bone_global_rest(hb).origin
	var h := maxf(head.y, 0.1)
	var target := Vector3(0.0, head.y + h * FACE_RAISE_FRAC, head.z)
	cam.position = Vector3(0.0, target.y, head.z + h * FACE_DIST_FRAC)
	cam.look_at(target, Vector3.UP)


func _build_hp(root: Control) -> void:
	_hp = ProgressBar.new()
	_hp.show_percentage = false
	_hp.position = Vector2(MARGIN + PORTRAIT + MARGIN, XP_HEIGHT + MARGIN)
	_hp.size = HP_SIZE
	_hp.custom_minimum_size = HP_SIZE
	_hp.add_theme_stylebox_override("background", _flat(TRACK_BG, EMBER_DIM, 2, 4))
	_hp.add_theme_stylebox_override("fill", _flat(HP_FILL, HP_FILL, 0, 3))
	root.add_child(_hp)

	_hp_label = Label.new()
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_label.add_theme_font_size_override("font_size", 22)
	_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_hp_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp.add_child(_hp_label)


## Level medallion: a circular ember-ringed badge overlapping the portrait's bottom-right
## corner, with the level number, plus the per-wave LVL UP badge column overlaid on the
## portrait's upper area (clear of the HP bar to the portrait's right).
func _build_level_badge(root: Control) -> void:
	var sz := 52
	_lv_badge = Panel.new()
	_lv_badge.size = Vector2(sz, sz)
	_lv_badge.position = Vector2(
		MARGIN + PORTRAIT - sz + 14,
		XP_HEIGHT + MARGIN + PORTRAIT - sz + 14)   # overlap the panel's bottom-right corner
	_lv_badge.pivot_offset = Vector2(sz, sz) * 0.5   # punch scales from the centre
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = EMBER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(sz / 2)                 # full radius -> circle
	_lv_badge.add_theme_stylebox_override("panel", sb)
	_lv_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_lv_badge)

	_lv = Label.new()
	_lv.text = "1"
	_lv.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lv.add_theme_font_size_override("font_size", 30)
	_lv.add_theme_color_override("font_color", EMBER)
	_lv.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_lv.add_theme_constant_override("shadow_offset_x", 2)
	_lv.add_theme_constant_override("shadow_offset_y", 2)
	_lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lv_badge.add_child(_lv)


## "WAVE N" readout, centred along the top edge just under the XP strip.
func _build_wave_label(root: Control) -> void:
	_wave_label = Label.new()
	_wave_label.text = "WAVE 1"
	_wave_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_wave_label.offset_top = XP_HEIGHT + 4
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.add_theme_font_size_override("font_size", 26)
	_wave_label.add_theme_color_override("font_color", EMBER)
	_wave_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_wave_label.add_theme_constant_override("shadow_offset_x", 2)
	_wave_label.add_theme_constant_override("shadow_offset_y", 2)
	_wave_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_wave_label)


## Souls counter, pinned to the top-right: a cyan soul-mote glyph + running count.
## Souls are banked from collected motes; future upgrades will spend them.
func _build_souls(root: Control) -> void:
	var strip := HBoxContainer.new()
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.alignment = BoxContainer.ALIGNMENT_END        # pack to the right edge
	strip.offset_top = XP_HEIGHT + MARGIN
	strip.offset_left = MARGIN
	strip.offset_right = -MARGIN
	strip.add_theme_constant_override("separation", 8)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)

	var sz := 30
	_souls_orb = TextureRect.new()
	_souls_orb.texture = SOUL_ICON
	_souls_orb.modulate = SOUL                          # cyan soul tint
	_souls_orb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_souls_orb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_souls_orb.custom_minimum_size = Vector2(sz, sz)
	_souls_orb.pivot_offset = Vector2(sz, sz) * 0.5     # punch scales from the centre
	_souls_orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_souls_orb)

	_souls_count = Label.new()
	_souls_count.text = "0"
	_souls_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_souls_count.add_theme_font_size_override("font_size", 26)
	_souls_count.add_theme_color_override("font_color", SOUL)
	_souls_count.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_souls_count.add_theme_constant_override("shadow_offset_x", 2)
	_souls_count.add_theme_constant_override("shadow_offset_y", 2)
	_souls_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(_souls_count)


## A stack of medals under the HP bar — one per level gained this wave (cleared at wave start).
func _build_lvlup_stack(root: Control) -> void:
	_lvlup_stack = Control.new()
	_lvlup_stack.position = Vector2(
		MARGIN + PORTRAIT + MARGIN,                          # align with the HP bar's left edge
		XP_HEIGHT + MARGIN + int(HP_SIZE.y) + 8)             # just under the HP bar
	_lvlup_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_lvlup_stack)


## Buff/debuff badges, in the same row as the level-up medals (just under the HP bar).
## For now only the reload debuff; it's hidden until a gun reloads.
func _build_status_row(root: Control) -> void:
	_reload_icon = StatusIconScript.new()
	_reload_icon.icon = RELOAD_ICON
	_reload_icon.custom_minimum_size = Vector2(STATUS_SIZE, STATUS_SIZE)
	_reload_icon.size = Vector2(STATUS_SIZE, STATUS_SIZE)
	_reload_icon.position = Vector2(MARGIN + PORTRAIT + MARGIN, XP_HEIGHT + MARGIN + int(HP_SIZE.y) + 8)
	_reload_icon.visible = false
	root.add_child(_reload_icon)


## Poll the weapon ring each frame: show the reload debuff while any gun reloads,
## stacked by how many, with the cooldown sweep draining as they finish.
func _update_reload_debuff() -> void:
	if _reload_icon == null or weapon_ring == null or not weapon_ring.has_method("reload_state"):
		return
	var st: Dictionary = weapon_ring.reload_state()
	var count: int = st["count"]
	if count <= 0:
		_reload_icon.visible = false
		return
	_reload_icon.visible = true
	_reload_icon.set_state(count, st["frac"], st["seconds"])


## Pop an up-arrow medal onto the stack under the HP bar (newest on top, shifted right).
func _add_lvlup_medal() -> void:
	var i := _lvlup_stack.get_child_count()
	if i >= LVLUP_MAX:
		return
	var sz := 34
	var medal := Panel.new()
	medal.size = Vector2(sz, sz)
	medal.position = Vector2(i * LVLUP_STACK_OFFSET, 0.0)   # overlapping pile, fanned right
	medal.pivot_offset = Vector2(sz, sz) * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = XP_FILL
	sb.border_color = EMBER
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(sz / 2)
	medal.add_theme_stylebox_override("panel", sb)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvlup_stack.add_child(medal)

	var arrow := Polygon2D.new()                           # an up-arrow stamped on the medal
	arrow.color = Color(0.15, 0.04, 0.0)
	arrow.position = Vector2(sz, sz) * 0.5
	arrow.polygon = PackedVector2Array([
		Vector2(0.0, -8.0), Vector2(8.0, 4.0), Vector2(3.0, 4.0),
		Vector2(3.0, 9.0), Vector2(-3.0, 9.0), Vector2(-3.0, 4.0), Vector2(-8.0, 4.0)])
	medal.add_child(arrow)

	medal.scale = Vector2(0.2, 0.2)
	medal.modulate.a = 0.0
	var tw := medal.create_tween().set_parallel(true)
	tw.tween_property(medal, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(medal, "modulate:a", 1.0, 0.2)


## Splashy centred "LEVEL UP!" banner that pops, holds, and fades — the main flourish.
func _play_levelup_effect() -> void:
	var b := Label.new()
	b.text = "LEVEL UP!"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_theme_font_size_override("font_size", 56)
	b.add_theme_color_override("font_color", XP_FILL)
	b.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.95))
	b.add_theme_constant_override("outline_size", 8)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := get_viewport().get_visible_rect().size
	b.size = Vector2(vp.x, 80.0)                  # full-width band -> centred text is screen-centred
	b.position = Vector2(0.0, vp.y * 0.30)
	b.pivot_offset = Vector2(vp.x * 0.5, 40.0)
	get_child(0).add_child(b)                     # the full-rect root Control
	b.scale = Vector2(0.6, 0.6)
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(1.15, 1.15), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.25)
	tw.tween_property(b, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(b.queue_free)


## Scale-punch the medallion on a level-up.
func _punch_badge() -> void:
	_lv_badge.scale = Vector2(1.4, 1.4)
	var tw := _lv_badge.create_tween()
	tw.tween_property(_lv_badge, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Clear the level-up medal stack — called when the level-up menu is closed, so the
## medal disappears once the player has acknowledged the level-up.
func clear_levelup_medals() -> void:
	if _lvlup_stack != null:
		for m in _lvlup_stack.get_children():
			m.queue_free()


## A new wave began — update the WAVE readout and reset the per-wave LVL UP counter.
## Wired to WaveSpawner.wave_started.
func on_wave_started(wave: int) -> void:
	if _wave_label != null:
		_wave_label.text = "WAVE %d" % wave
	clear_levelup_medals()


func _on_health(hp: float, max_hp: float) -> void:
	_hp.max_value = max_hp
	_hp.value = hp
	_hp_label.text = "%d / %d" % [roundi(hp), roundi(max_hp)]


## New lifetime-XP target from PlayerStats; the bar animates toward it in _process.
func _on_xp(total_xp: float) -> void:
	_xp_target = total_xp


## Banked soul count changed — update the counter and pop the mote a touch.
func _on_souls(souls: int) -> void:
	if _souls_count == null:
		return
	_souls_count.text = str(souls)
	_souls_orb.scale = Vector2(1.5, 1.5)
	var tw := _souls_orb.create_tween()
	tw.tween_property(_souls_orb, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Seed the animated bar from the current stats (level + lifetime XP), no animation.
func _init_xp_display() -> void:
	_xp_level = stats.level
	_xp_to_next = stats.xp_for(_xp_level)
	_xp_level_start = 0.0
	for lvl in range(1, _xp_level):
		_xp_level_start += stats.xp_for(lvl)
	_xp_target = stats.total_xp
	_xp_disp = stats.total_xp
	_lv.text = str(_xp_level)
	_update_xp_bar()


func _update_xp_bar() -> void:
	_xp.max_value = _xp_to_next
	_xp.value = clampf(_xp_disp - _xp_level_start, 0.0, _xp_to_next)


## The bar just filled to 100% of a level — show the level number, the flourish, and
## tell Main (which opens the level-up menu). Fires once per level, at the full bar.
func _present_level_up(level: int) -> void:
	_lv.text = str(level)
	_punch_badge()
	_add_lvlup_medal()
	_play_levelup_effect()
	level_reached.emit(level)


## A StyleBoxFlat with optional border + corner radius.
func _flat(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	return s
