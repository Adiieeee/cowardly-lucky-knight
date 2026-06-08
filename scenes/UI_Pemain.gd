extends CanvasLayer

var tex_full = preload("res://assets/Full.png")
var tex_half = preload("res://assets/Half.png")
var tex_empty = preload("res://assets/Zero.png")

@onready var hati_array: Array = [
	$HBoxContainer/Hearth1,
	$HBoxContainer/Hearth2,
	$HBoxContainer/Hearth3,
	$HBoxContainer/Hearth4,
	$HBoxContainer/Hearth5
]

func _process(delta: float) -> void:
	var pemain = get_tree().get_first_node_in_group("player")
	if is_instance_valid(pemain):
		if "darah" in pemain:
			_perbarui_darah(pemain.darah)

func _perbarui_darah(hp: int) -> void:
	for i in range(5):
		var base_hp = i * 2
		if hp >= base_hp + 2:
			hati_array[i].texture = tex_full
		elif hp == base_hp + 1:
			hati_array[i].texture = tex_half
		else:
			hati_array[i].texture = tex_empty
