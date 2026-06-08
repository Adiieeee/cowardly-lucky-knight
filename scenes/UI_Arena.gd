extends CanvasLayer

@onready var health_bar: ProgressBar = $ProgressBar
@onready var icon_frame: TextureRect = $ProgressBar/Icon

var target_musuh: Node2D = null

var tex_minotaur = preload("res://assets/FrameMinotaur.png")
var tex_boss = preload("res://assets/SATYR_sprite_sheet/SPRITE_PORTRAIT.png")

func _ready() -> void:
	visible = false

func atur_target(musuh: Node2D, nama_musuh: String, max_hp: int) -> void:
	target_musuh = musuh
	health_bar.max_value = max_hp
	health_bar.value = max_hp
	
	if nama_musuh == "MINOTAUR":
		icon_frame.texture = tex_minotaur
		icon_frame.visible = true
	elif nama_musuh == "BOSS":
		icon_frame.texture = tex_boss
		icon_frame.visible = true
	else:
		icon_frame.visible = false
		
	visible = true

func hilangkan() -> void:
	target_musuh = null
	visible = false

func _process(delta: float) -> void:
	if is_instance_valid(target_musuh):
		# Akses properti 'darah' yang ada di Minotaur.gd dan Boss.gd
		if "darah" in target_musuh:
			health_bar.value = target_musuh.darah
	else:
		hilangkan()
