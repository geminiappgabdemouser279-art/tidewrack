extends Node2D
class_name LampRoom
## Playable lamp room with its own bounds and a stair back to the ground floor.
## The great lamp remains a visual placeholder; relighting is a later content pass.

const ROOM := Rect2(300, 150, 680, 420)
const INTERACT_RADIUS := 90.0

var _player: Player
var _stair: DoorTransition
var _prompt: Label
var _paused: bool = false
var _pause_layer: CanvasLayer


func _ready() -> void:
	_build_room()
	_build_player()
	_build_stair()
	_build_hud()
	add_child(preload("res://scenes/ui/dialogue_box.tscn").instantiate())
	DialogueManager.dialogue_started.connect(_on_dialogue_started)
	DialogueManager.dialogue_finished.connect(_on_dialogue_finished)


func _build_room() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1216")
	bg.size = Vector2(1280, 720)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var floor_rect := ColorRect.new()
	floor_rect.color = Color("#18272e")
	floor_rect.position = ROOM.position
	floor_rect.size = ROOM.size
	floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(floor_rect)

	var title := Label.new()
	title.text = "Cape Marrow Light — lamp room"
	title.position = ROOM.position - Vector2(0, 34)
	title.modulate = Color(1, 1, 1, 0.5)
	add_child(title)

	var lamp := ColorRect.new()
	lamp.color = Color("#2a2f33")
	lamp.size = Vector2(120, 120)
	lamp.position = Vector2(580, 220)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lamp)


func _build_player() -> void:
	_player = Player.new()
	_player.bounds = ROOM.grow(-30)
	_player.position = Vector2(640, 500)
	add_child(_player)

	var camera := Camera2D.new()
	camera.position_smoothing_enabled = true
	_player.add_child(camera)
	camera.make_current()


func _build_stair() -> void:
	_stair = DoorTransition.new()
	_stair.label = "Ground-floor stair"
	_stair.prompt_text = "Return to the ground floor"
	_stair.target_scene = "res://scenes/game.tscn"
	_stair.position = Vector2(380, 470)
	_stair.color = Color("#3a4a54")
	add_child(_stair)
	_stair.setup()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_prompt = Label.new()
	_prompt.position = Vector2(340, 650)
	_prompt.size = Vector2(600, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.modulate = Color("#ffd466")
	_prompt.text = "[ Enter ] %s" % _stair.prompt_text
	_prompt.hide()
	layer.add_child(_prompt)


func _can_use_stair() -> bool:
	return not _paused and not DialogueManager.is_active and _stair.can_interact() \
		and _player.position.distance_to(_stair.position) <= INTERACT_RADIUS


func _process(_delta: float) -> void:
	_prompt.visible = _can_use_stair()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not DialogueManager.is_active:
			if _paused:
				_resume()
			else:
				_show_pause_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept") and _can_use_stair():
		_stair.interact()
		get_viewport().set_input_as_handled()


func _on_dialogue_started() -> void:
	_player.can_move = false


func _on_dialogue_finished() -> void:
	_player.can_move = not _paused


func _resume() -> void:
	if is_instance_valid(_pause_layer):
		_pause_layer.queue_free()
		_pause_layer = null
	_paused = false
	_player.can_move = not DialogueManager.is_active


func _show_pause_menu() -> void:
	_paused = true
	_player.can_move = false
	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.layer = 20
	add_child(_pause_layer)

	var overlay := Control.new()
	_pause_layer.add_child(overlay)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	overlay.add_child(dim)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	overlay.add_child(center)
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var resume := _menu_button("Resume")
	resume.pressed.connect(_resume)
	vbox.add_child(resume)

	var save := _menu_button("Save")
	save.pressed.connect(func():
		GameState.current_scene = scene_file_path
		var ok := GameState.save_game()
		save.text = "Saved ✓" if ok else "Save failed")
	vbox.add_child(save)

	var settings := _menu_button("Settings")
	settings.pressed.connect(func():
		overlay.add_child(preload("res://scenes/ui/settings.tscn").instantiate()))
	vbox.add_child(settings)

	var menu := _menu_button("Main Menu")
	menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vbox.add_child(menu)
	resume.grab_focus()


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(200, 40)
	button.add_theme_font_size_override("font_size", 20)
	return button


func is_lamp_lit() -> bool:
	return bool(GameState.get_flag("lamp_relit", false))
