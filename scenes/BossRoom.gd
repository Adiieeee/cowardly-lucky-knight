extends Node2D

var minotaur_scene = preload("res://scenes/minotaur.tscn")
var boss_scene = preload("res://scenes/Boss.tscn")
var ui_arena_scene = preload("res://scenes/UI_Arena.tscn")

var ui_arena: CanvasLayer = null

func _ready() -> void:
	# Tambahkan UI
	ui_arena = ui_arena_scene.instantiate()
	add_child(ui_arena)
	
	# Hapus boss bawaan scene agar tidak langsung muncul
	var boss_awal = get_node_or_null("Boss")
	if boss_awal:
		boss_awal.queue_free()
	
	# Munculkan minotaur terlebih dahulu
	_spawn_minotaur()

func _spawn_minotaur() -> void:
	var minotaur = minotaur_scene.instantiate()
	minotaur.position = Vector2(341, -2)
	minotaur.scale = Vector2(1.2, 1.2)
	# Hubungkan signal mati dari minotaur ke fungsi pemunculan boss
	minotaur.connect("musuh_mati", Callable(self, "_pada_minotaur_mati"))
	
	# Tambahkan sebagai child secara deferred agar aman
	call_deferred("add_child", minotaur)
	
	if ui_arena:
		ui_arena.atur_target(minotaur, "MINOTAUR", 10)

func _pada_minotaur_mati() -> void:
	if ui_arena:
		ui_arena.hilangkan()
		
	# Tunggu 5 detik sebelum memunculkan boss
	await get_tree().create_timer(5.0).timeout
	
	# Munculkan boss
	var boss = boss_scene.instantiate()
	boss.position = Vector2(341, -2)
	boss.scale = Vector2(1.7, 1.7)
	call_deferred("add_child", boss)
	
	if ui_arena:
		ui_arena.atur_target(boss, "BOSS", 20)
