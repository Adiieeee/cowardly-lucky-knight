extends CharacterBody2D

class_name KarakterUtama

@export var kecepatan_berjalan: float = 150.0
@export var kecepatan_berlari: float = 250.0
@export var kekuatan_lompat: float = -400.0
@export var maksimal_lompatan: int = 2
@export var proyektil_scene: PackedScene = preload("res://scenes/proyektil_pemain.tscn")

var gravitasi: float = ProjectSettings.get_setting("physics/2d/default_gravity")

var darah: int = 10
var sedang_menyerang: bool = false
var lanjut_serangan: bool = false
var tahap_serangan: int = 1
var sedang_terluka: bool = false
var status_mati: bool = false
var jumlah_lompatan: int = 0
var musuh_terkena_serangan: Array = []
var waktu_kebal: float = 0.0
var waktu_jeda_tembakan: float = 0.0

@onready var animasi_karakter: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_serangan: Area2D = $AreaSerangan

@onready var hitbox1: CollisionShape2D = $AreaSerangan/HitboxAttack1
@onready var hitbox2: CollisionShape2D = $AreaSerangan/HitboxAttack2
@onready var hitbox3: CollisionShape2D = $AreaSerangan/HitboxAttack3

var ui_pemain_scene = preload("res://scenes/UI_Pemain.tscn")
var ui_pemain_instance: CanvasLayer

func _ready() -> void:
	matikan_semua_hitbox()
	animasi_karakter.animation_finished.connect(_pada_animasi_selesai)
	
	ui_pemain_instance = ui_pemain_scene.instantiate()
	add_child(ui_pemain_instance)

func _physics_process(waktu_delta: float) -> void:
	if waktu_kebal > 0:
		waktu_kebal -= waktu_delta
	
	if waktu_jeda_tembakan > 0:
		waktu_jeda_tembakan -= waktu_delta

	if status_mati:
		return

	if not is_on_floor():
		velocity.y += gravitasi * waktu_delta
	else:
		jumlah_lompatan = 0

	if Input.is_action_just_pressed("up"):
		if jumlah_lompatan < maksimal_lompatan:
			velocity.y = kekuatan_lompat
			jumlah_lompatan += 1

	var arah_gerak: float = Input.get_axis("left", "right")
	var batas_kecepatan: float = kecepatan_berlari if Input.is_action_pressed("shift") else kecepatan_berjalan
	
	if arah_gerak:
		velocity.x = arah_gerak * batas_kecepatan
		if arah_gerak < 0:
			animasi_karakter.flip_h = true
			area_serangan.position.x = -abs(area_serangan.position.x)
		else:
			animasi_karakter.flip_h = false
			area_serangan.position.x = abs(area_serangan.position.x)
	else:
		velocity.x = move_toward(velocity.x, 0, batas_kecepatan)

	if Input.is_action_just_pressed("e") and not sedang_terluka and not sedang_menyerang and waktu_jeda_tembakan <= 0.0:
		jalankan_tembakan()

	if Input.is_action_just_pressed("lmb") and not sedang_terluka:
		jalankan_serangan()

	move_and_slide()
	atur_visual(arah_gerak)

	if sedang_menyerang:
		cek_kerusakan_berkelanjutan()

func matikan_semua_hitbox() -> void:
	hitbox1.set_deferred("disabled", true)
	hitbox2.set_deferred("disabled", true)
	hitbox3.set_deferred("disabled", true)

func jalankan_serangan() -> void:
	if sedang_menyerang:
		lanjut_serangan = true
	else:
		sedang_menyerang = true
		tahap_serangan = 1
		musuh_terkena_serangan.clear()
		animasi_karakter.play("attack1")
		
		matikan_semua_hitbox()
		await get_tree().create_timer(0.2).timeout
		
		if sedang_menyerang and tahap_serangan == 1:
			hitbox1.set_deferred("disabled", false)

func jalankan_tembakan() -> void:
	if sedang_menyerang:
		return
	sedang_menyerang = true
	tahap_serangan = 1
	lanjut_serangan = false
	musuh_terkena_serangan.clear()
	waktu_jeda_tembakan = 5.0
	animasi_karakter.play("fire")
	matikan_semua_hitbox()
	
	await get_tree().create_timer(0.2).timeout
	
	if status_mati or sedang_terluka or not sedang_menyerang:
		return
	
	if proyektil_scene:
		var proyektil = proyektil_scene.instantiate()
		var arah = 1.0 if not animasi_karakter.flip_h else -1.0
		proyektil.global_position = global_position + Vector2(arah * 20, 0)
		proyektil.arah_gerak = arah
		proyektil.scale.x = abs(proyektil.scale.x) * (1.0 if arah >= 0 else -1.0)
		get_tree().current_scene.add_child(proyektil)

func atur_visual(arah_gerak: float) -> void:
	if sedang_menyerang or sedang_terluka:
		return

	if not is_on_floor():
		if velocity.y < 0:
			animasi_karakter.play("jump")
		else:
			animasi_karakter.play("falling")
	else:
		if arah_gerak != 0:
			if Input.is_action_pressed("shift"):
				animasi_karakter.play("run")
			else:
				animasi_karakter.play("walk")
		else:
			animasi_karakter.play("idle")

func terima_kerusakan(jumlah: int) -> void:
	if status_mati or waktu_kebal > 0:
		return
	
	darah -= jumlah
	if darah <= 0:
		karakter_mati()
	else:
		waktu_kebal = 1.0
		terima_luka()

func terima_luka() -> void:
	sedang_terluka = true
	sedang_menyerang = false
	lanjut_serangan = false
	tahap_serangan = 1
	matikan_semua_hitbox()
	animasi_karakter.play("hurt")

func karakter_mati() -> void:
	status_mati = true
	animasi_karakter.play("death")

func _pada_animasi_selesai() -> void:
	var nama_aksi: String = animasi_karakter.animation
	
	if nama_aksi.begins_with("attack"):
		if lanjut_serangan and tahap_serangan < 3:
			tahap_serangan += 1
			lanjut_serangan = false
			musuh_terkena_serangan.clear()
			animasi_karakter.play("attack" + str(tahap_serangan))
			
			matikan_semua_hitbox()
			if tahap_serangan == 2:
				hitbox2.set_deferred("disabled", false)
			elif tahap_serangan == 3:
				await get_tree().create_timer(0.2).timeout
				if sedang_menyerang and tahap_serangan == 3:
					hitbox3.set_deferred("disabled", false)
		else:
			sedang_menyerang = false
			lanjut_serangan = false
			tahap_serangan = 1
			matikan_semua_hitbox()
	elif nama_aksi == "hurt":
		sedang_terluka = false
	elif nama_aksi == "fire":
		sedang_menyerang = false
		matikan_semua_hitbox()

func cek_kerusakan_berkelanjutan() -> void:
	var target_terkena = area_serangan.get_overlapping_bodies()
	for target in target_terkena:
		if (target is BosMusuh or target is MinotaurMusuh) and not target in musuh_terkena_serangan:
			target.terima_kerusakan(1)
			musuh_terkena_serangan.append(target)
