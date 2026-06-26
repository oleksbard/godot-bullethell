class_name Hud
extends CanvasLayer
## Gameplay HUD — top-left cluster + full-width XP strip:
##   * XP bar    — thin ember-gold strip pinned to the top edge
##   * Portrait  — small animated 3D marine in an ember-framed box (its own
##                 SubViewport, idle sway + bob)
##   * LV badge  — on the portrait's bottom-right corner
##   * HP bar    — crimson, to the right of the portrait, with "hp / max" text
## Binds to a PlayerStats via signals; set `stats` before adding to the tree.
## Reuses the pause-menu ember palette + the Oswald default font for consistency.

const MarineModel: PackedScene = preload("res://models/marine_01.glb")

# Palette (matches pause_menu.gd).
const EMBER := Color(1.0, 0.45, 0.2)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const PANEL_BG := Color(0.06, 0.02, 0.02, 0.92)
const TRACK_BG := Color(0.03, 0.01, 0.01, 0.9)
const HP_FILL := Color(0.8, 0.09, 0.06)
const XP_FILL := Color(1.0, 0.62, 0.16)

# Layout.
const MARGIN := 12
const XP_HEIGHT := 10
const PORTRAIT := 116
const HP_SIZE := Vector2(360, 40)

# Portrait framing — a face/mug shot aimed at the rig's Head bone. Distances are
# fractions of head height so it stays framed whatever the model's scale.
const FACE_FOV := 30.0
const FACE_DIST_FRAC := 0.34   # camera distance in front, as a fraction of head height
const FACE_RAISE_FRAC := 0.05  # aim a touch above the Head bone (skull base -> face)
const FALLBACK_HEAD := Vector3(0.0, 1.6, 0.0)  # used if the rig has no Head bone
const SWAY := 0.16          # idle head turn (radians)
const BOB := 0.02           # idle vertical bob (metres)

var stats: Node             # PlayerStats; set before add_child

var _hp: ProgressBar
var _hp_label: Label
var _xp: ProgressBar
var _lv: Label
var _portrait: Node3D
var _t := 0.0


func _ready() -> void:
	_build()
	if stats == null:
		return
	stats.health_changed.connect(_on_health)
	stats.xp_changed.connect(_on_xp)
	stats.leveled_up.connect(_on_level)
	_on_health(stats.health, stats.max_health)   # pull the current state once
	_on_xp(stats.xp, stats.xp_to_next)
	_on_level(stats.level)


func _process(delta: float) -> void:
	if _portrait == null:
		return
	_t += delta
	_portrait.rotation.y = sin(_t * 0.8) * SWAY
	_portrait.position.y = absf(sin(_t * 1.6)) * BOB


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_xp(root)
	_build_portrait(root)
	_build_hp(root)


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

	_lv = Label.new()
	_lv.text = "LV 1"
	_lv.add_theme_font_size_override("font_size", 22)
	_lv.add_theme_color_override("font_color", EMBER)
	_lv.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_lv.add_theme_constant_override("shadow_offset_x", 2)
	_lv.add_theme_constant_override("shadow_offset_y", 2)
	_lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lv.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_lv.offset_top = -30
	_lv.offset_bottom = -3
	_lv.offset_right = -8
	_lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_lv)


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
	_hp.position = Vector2(MARGIN + PORTRAIT + MARGIN, XP_HEIGHT + MARGIN + 38)
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


func _on_health(hp: float, max_hp: float) -> void:
	_hp.max_value = max_hp
	_hp.value = hp
	_hp_label.text = "%d / %d" % [roundi(hp), roundi(max_hp)]


func _on_xp(xp: float, to_next: float) -> void:
	_xp.max_value = to_next
	_xp.value = xp


func _on_level(level: int) -> void:
	_lv.text = "LV %d" % level


## A StyleBoxFlat with optional border + corner radius.
func _flat(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	return s
