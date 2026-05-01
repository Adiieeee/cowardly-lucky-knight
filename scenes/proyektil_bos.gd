extends Area2D

class_name ProyektilBos

@export var kecepatan_gerak: float = 800.0
var arah_gerak: float = 1.0
var kerusakan: int = 1

func _ready() -> void:
	body_entered.connect(_pada_tubuh_masuk)
	await get_tree().create_timer(3.0).timeout
	queue_free()

func _process(waktu_delta: float) -> void:
	position.x += kecepatan_gerak * arah_gerak * waktu_delta

func _pada_tubuh_masuk(tubuh: Node2D) -> void:
	if tubuh is KarakterUtama and not tubuh.status_mati:
		tubuh.terima_kerusakan(kerusakan)
		queue_free()
