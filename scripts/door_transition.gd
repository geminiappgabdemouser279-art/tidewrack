extends Interactable
class_name DoorTransition
## An interactable stair that changes scenes without starting dialogue.

@export_file("*.tscn") var target_scene: String = ""

var _transition_pending: bool = false


func can_interact() -> bool:
	return not _transition_pending and not target_scene.is_empty() and not DialogueManager.is_active


func interact() -> void:
	if not can_interact():
		return
	_transition_pending = true
	interacted.emit(self)
	# Finish the current input dispatch before removing the room from the tree.
	_change_scene.call_deferred()


func _change_scene() -> void:
	var error := get_tree().change_scene_to_file(target_scene)
	if error != OK:
		_transition_pending = false
		push_error("DoorTransition: could not open '%s' (error %s)." % [target_scene, error])
		return
	GameState.current_scene = target_scene
