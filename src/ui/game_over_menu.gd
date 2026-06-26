class_name GameOverMenu
extends CanvasLayer
## Shown when the player dies: a dim scrim, a blood-red "YOU DIED", and New Game /
## Exit. Hidden until show_menu() is called (by Main on the marine's `died` signal).
## Pauses the tree while up and runs regardless (PROCESS_MODE_ALWAYS). Mirrors the
## pause-menu styling.

const DIM := Color(0.04, 0.0, 0.0, 0.8)
const BLOOD := Color(0.85, 0.12, 0.08)
const EMBER := Color(1.0, 0.45, 0.2)
const EMBER_DIM := Color(0.62, 0.22, 0.1)
const BTN_BG := Color(0.06, 0.02, 0.02, 0.92)

var _new_game_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # works while the tree is paused
	layer = 11                                   # above the pause menu + HUD
	visible = false
	_build()


## Reveal the menu and freeze the game behind it.
func show_menu() -> void:
	visible = true
	get_tree().paused = true
	_new_game_btn.grab_focus()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 26)
	center.add_child(box)

	var title := Label.new()
	title.text = "YOU DIED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", BLOOD)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)

	_new_game_btn = _make_button("NEW GAME", _on_new_game)
	box.add_child(_new_game_btn)
	box.add_child(_make_button("EXIT", _on_exit))


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(400, 80)
	b.add_theme_font_size_override("font_size", 36)
	b.add_theme_color_override("font_color", EMBER)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _btn_box(EMBER_DIM))
	b.add_theme_stylebox_override("hover", _btn_box(EMBER))
	b.add_theme_stylebox_override("pressed", _btn_box(EMBER))
	b.add_theme_stylebox_override("focus", _btn_box(EMBER))
	b.pressed.connect(handler)
	return b


func _btn_box(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BTN_BG
	s.border_color = border
	s.set_border_width_all(3)
	s.set_corner_radius_all(5)
	s.content_margin_left = 30
	s.content_margin_right = 30
	s.content_margin_top = 18
	s.content_margin_bottom = 18
	return s


func _on_new_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_exit() -> void:
	get_tree().quit()
