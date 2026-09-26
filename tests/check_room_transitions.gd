extends SceneTree
## Focused Godot 4.3 integration checks. Use an isolated save directory:
## XDG_DATA_HOME=$(mktemp -d) godot --headless --path . --script tests/check_room_transitions.gd
## Uses action events by default, independent of the keyboard fix in PR #1.
## Pass -- --keyboard to exercise synthetic Enter/Escape events in a combined checkout.

const GROUND := "res://scenes/game.tscn"
const LAMP := "res://scenes/lamp_room.tscn"
var checks: int = 0
var failures: int = 0
var _dialogue: Node
var _state: Node
var _keyboard: bool = false


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)


func frames() -> void:
	await process_frame
	await process_frame


func action_event(action: String) -> InputEvent:
	if _keyboard:
		var key := InputEventKey.new()
		key.keycode = KEY_ENTER if action == "ui_accept" else KEY_ESCAPE
		key.pressed = true
		return key
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func press(action: String) -> void:
	var event := action_event(action)
	root.push_input(event)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release)


func stair(room: Node) -> Node:
	for child in room.get_children():
		if child.get_script() == load("res://scripts/door_transition.gd"):
			return child
	return null


func button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := button(child, text)
		if found != null:
			return found
	return null


func count_script(node: Node, path: String) -> int:
	var count := 0
	if node.get_script() != null and node.get_script().resource_path == path:
		count += 1
	for child in node.get_children():
		count += count_script(child, path)
	return count


func check_room(path: String) -> void:
	check(current_scene.scene_file_path == path, "active scene: " + path)
	var player: Player = current_scene._player
	check(player.bounds.has_point(player.position), "spawn inside room bounds")
	check(player.position.distance_to(stair(current_scene).position) > 90, "spawn clear of stair")
	check(player.can_move, "movement enabled after arrival")
	check(root.get_camera_2d() != null, "active camera")
	check(count_script(root, "res://scripts/player.gd") == 1, "one player")
	check(count_script(root, "res://scripts/dialogue_box.gd") == 1, "one dialogue UI")
	check(_dialogue.dialogue_started.get_connections().size() == 2, "two live start listeners")
	check(_dialogue.dialogue_finished.get_connections().size() == 2, "two live finish listeners")


func check_bounds() -> void:
	var player: Player = current_scene._player
	var original := player.position
	for action in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		Input.action_press(action)
		player._physics_process(10)
		Input.action_release(action)
		var expected := player.bounds.position.x if action == "ui_left" else player.bounds.end.x
		if action == "ui_up" or action == "ui_down":
			expected = player.bounds.position.y if action == "ui_up" else player.bounds.end.y
			check(is_equal_approx(player.position.y, expected), "vertical bound: " + action)
		else:
			check(is_equal_approx(player.position.x, expected), "horizontal bound: " + action)
	player.position = original


func check_frozen() -> void:
	var player: Player = current_scene._player
	var original := player.position
	Input.action_press("ui_right")
	player._physics_process(0.1)
	Input.action_release("ui_right")
	check(player.position == original, "movement blocked")


func finish_dialogue() -> void:
	for i in range(30):
		if not _dialogue.is_active:
			break
		var node: Dictionary = _dialogue._graph[_dialogue._current_id]
		if not node.get("choices", []).is_empty():
			_dialogue.choose(0)
		else:
			_dialogue.advance()
	check(not _dialogue.is_active, "dialogue finishes")
	check(current_scene._player.can_move, "dialogue restores movement")
	await frames()


func check_ground_dialogue(label: String, start: String) -> void:
	var room := current_scene
	for child in room.get_children():
		if child.get_script() == load("res://scripts/interactable.gd") and child.label == label:
			room._player.position = child.position
	await frames()
	press("ui_accept")
	check(_dialogue.is_active and _dialogue._current_id == start, label + " starts through room input")
	check_frozen()
	room._player.position = stair(room).position
	await frames()
	check(not room._prompt.visible, "prompt hidden during dialogue")
	room._unhandled_input(action_event("ui_accept"))
	stair(room).interact()
	await frames()
	check(current_scene == room, "dialogue blocks stair")
	await finish_dialogue()


func check_pause() -> void:
	var room := current_scene
	room._player.position = stair(room).position
	await frames()
	press("ui_cancel")
	await frames()
	check(room._paused, "pause opens")
	check_frozen()
	check(not room._prompt.visible, "prompt hidden while paused")
	for label in ["Resume", "Save", "Settings", "Main Menu"]:
		check(button(room, label) != null, "pause button: " + label)
	# Call the room handler directly: GUI normally consumes accept on Resume.
	room._unhandled_input(action_event("ui_accept"))
	await frames()
	check(current_scene == room, "paused room blocks stair input")
	button(room, "Resume").pressed.emit()
	await frames()
	check(not room._paused and room._player.can_move, "Resume restores movement")
	check(room.get_node_or_null("PauseLayer") == null, "Resume removes pause overlay")


func travel(expected: String) -> void:
	var room := current_scene
	var door := stair(room)
	room._player.position = door.position
	await frames()
	check(room._prompt.visible, "stair prompt in range")
	var activations := [0]
	door.interacted.connect(func(_source): activations[0] += 1)
	press("ui_accept")
	press("ui_accept")
	await frames()
	check(activations[0] == 1, "one transition for duplicate input")
	check(not is_instance_valid(room), "departed room freed")
	check(_state.current_scene == expected, "GameState tracks destination")
	check_room(expected)
	check(_state.get_flag("radioed_tom", false), "story flag survives transition")


func _run() -> void:
	_keyboard = "--keyboard" in OS.get_cmdline_user_args()
	_dialogue = root.get_node("DialogueManager")
	_state = root.get_node("GameState")
	_state.new_game()
	check(change_scene_to_file(GROUND) == OK, "ground scene opens")
	await frames()
	check_room(GROUND)
	check_bounds()
	await check_ground_dialogue("Logbook", "logbook")
	await check_ground_dialogue("Radio set", "radio")
	check(_state.get_flag("trusted_edith", false), "logbook choice flag set")
	check(_state.get_flag("radioed_tom", false), "radio choice flag set")
	await check_pause()
	await travel(LAMP)
	check(current_scene._player.bounds == Rect2(330, 180, 620, 360), "lamp has its own bounds")
	check_bounds()
	var room := current_scene
	press("ui_accept")
	await frames()
	check(current_scene == room and not room._prompt.visible, "out-of-range accept stays in lamp room")
	await check_pause()
	press("ui_cancel")
	await frames()
	button(room, "Settings").pressed.emit()
	await frames()
	check(button(room, "Back") != null, "lamp pause Settings opens")
	button(room, "Back").pressed.emit()
	await frames()
	button(room, "Save").pressed.emit()
	check(button(room, "Saved ✓") != null, "lamp pause Save succeeds")
	check(_state.load_game() and _state.current_scene == LAMP, "saved scene is lamp room")
	press("ui_cancel")
	await frames()
	check(not room._paused and room.get_node_or_null("PauseLayer") == null, "lamp Escape closes pause")
	_dialogue.start("res://data/dialogue/lamp_room.json")
	check_frozen()
	room._unhandled_input(action_event("ui_accept"))
	await frames()
	check(current_scene == room, "lamp dialogue blocks return stair")
	await finish_dialogue()
	await travel(GROUND)
	await check_ground_dialogue("Logbook", "logbook")
	await check_ground_dialogue("Radio set", "radio")
	await check_pause()
	await travel(LAMP)
	await travel(GROUND)
	print("Room transition checks (%s): %d checks, %d failures" % ["keyboard" if _keyboard else "actions", checks, failures])
	quit(1 if failures else 0)
