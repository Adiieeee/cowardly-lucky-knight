extends CharacterBody2D

class_name MinotaurMusuh

enum State {
	PATROL,
	CHASE,
	PREPARE_ATTACK,
	ATTACK,
	HURT,
	DEAD
}

signal musuh_mati

@export var kecepatan_patroli: float = 60.0
@export var kecepatan_kejar: float = 100.0
@export var jeda_antar_serangan: float = 1.2
@export var jarak_deteksi: float = 350.0
@export var jarak_serang: float = 60.0

var gravitasi: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var akselerasi: float = 800.0

var darah: int = 10
var status_mati: bool = false
var sedang_terluka: bool = false
var sedang_menyerang: bool = false
var waktu_kebal: float = 0.0
var waktu_jeda_serangan: float = 0.0

var state_saat_ini: State = State.PATROL
var arah_gerak: float = -1.0

@onready var animasi_minotaur: AnimatedSprite2D = $AnimatedSprite2D
@onready var area_serangan: Area2D = $AreaSerangan

func _ready() -> void:
	# Pastikan layer fisika Minotaur berada di layer 3 (musuh) agar terbaca oleh tebasan pedang
	collision_layer = 4
	collision_mask = 1 | 2 # Bisa menabrak dinding dan player
	
	# Perkecil ukuran lebar ShapeMinotaur saja agar hitbox tidak terlalu besar tapi tingginya tetap (agar tidak tenggelam)
	var shape_node = get_node_or_null("ShapeMinotaur")
	if shape_node:
		shape_node.scale = Vector2(0.5, 1.0)
	
	animasi_minotaur.animation_finished.connect(_pada_animasi_selesai)

func _physics_process(waktu_delta: float) -> void:
	if waktu_kebal > 0:
		waktu_kebal -= waktu_delta
	if waktu_jeda_serangan > 0:
		waktu_jeda_serangan -= waktu_delta

	if not is_on_floor():
		velocity.y += gravitasi * waktu_delta

	_proses_state_machine(waktu_delta)
	move_and_slide()
	cek_sentuhan_badan()

func _proses_state_machine(dt: float) -> void:
	var pemain = get_tree().get_first_node_in_group("player")

	if state_saat_ini == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, akselerasi * dt)
		return

	if state_saat_ini == State.HURT:
		velocity.x = move_toward(velocity.x, 0.0, akselerasi * dt)
		return

	if state_saat_ini == State.ATTACK or state_saat_ini == State.PREPARE_ATTACK:
		velocity.x = move_toward(velocity.x, 0.0, akselerasi * dt)
		return

	if not pemain or pemain.status_mati:
		_ubah_state(State.PATROL)
		_proses_patrol(dt)
		return

	var jarak := global_position.distance_to(pemain.global_position)
	var delta_x: float = pemain.global_position.x - global_position.x

	if state_saat_ini == State.PATROL:
		_proses_patrol(dt)
		if jarak < jarak_deteksi:
			_ubah_state(State.CHASE)

	elif state_saat_ini == State.CHASE:
		arah_gerak = 1.0 if delta_x > 0 else -1.0
		
		# Cek apakah pemain masuk ke jarak serang
		var bisa_serang = jarak <= jarak_serang
				
		if bisa_serang and waktu_jeda_serangan <= 0:
			_jalankan_serangan()
		else:
			# Lari mengejar pemain
			velocity.x = move_toward(velocity.x, arah_gerak * kecepatan_kejar, akselerasi * dt)
			animasi_minotaur.flip_h = arah_gerak < 0
			
			if area_serangan:
				area_serangan.position.x = abs(area_serangan.position.x) * (1.0 if arah_gerak > 0 else -1.0)
			
			if is_on_floor():
				animasi_minotaur.play("run" if abs(velocity.x) > 10.0 else "idle")

func _proses_patrol(dt: float) -> void:
	if is_on_wall():
		arah_gerak *= -1.0

	velocity.x = move_toward(velocity.x, arah_gerak * kecepatan_patroli, akselerasi * dt)
	animasi_minotaur.flip_h = velocity.x < 0
	
	if area_serangan:
		area_serangan.position.x = abs(area_serangan.position.x) * (1.0 if arah_gerak > 0 else -1.0)

	if is_on_floor() and abs(velocity.x) > 10.0:
		animasi_minotaur.play("run")
	else:
		animasi_minotaur.play("idle")

func _jalankan_serangan() -> void:
	_ubah_state(State.PREPARE_ATTACK)
	sedang_menyerang = true
	velocity.x = 0
	animasi_minotaur.play("angry")

func terima_kerusakan(jumlah: int) -> void:
	if status_mati or waktu_kebal > 0:
		return

	darah -= jumlah

	if darah <= 0:
		status_mati = true
		_ubah_state(State.DEAD)
		animasi_minotaur.play("death")
		
		# Matikan collision box agar tidak menghalangi
		if $CollisionShape2D:
			$CollisionShape2D.set_deferred("disabled", true)
	else:
		waktu_kebal = 1.0
		sedang_terluka = true
		sedang_menyerang = false
		_ubah_state(State.HURT)
		
		# Memberikan efek knockback ke belakang
		var pemain = get_tree().get_first_node_in_group("player")
		var mundur = -1.0 if (pemain and pemain.global_position.x > global_position.x) else 1.0
		velocity.x = mundur * 150.0
		velocity.y = -150.0
		
		animasi_minotaur.play("hurt")

func cek_sentuhan_badan() -> void:
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider is KarakterUtama and not collider.status_mati:
			collider.terima_kerusakan(1)

func _ubah_state(state_baru: State) -> void:
	state_saat_ini = state_baru

func _pada_animasi_selesai() -> void:
	if status_mati:
		if animasi_minotaur.animation == "death":
			emit_signal("musuh_mati")
			z_index = -1 # Pindahkan mayat ke layer belakang agar tidak menutupi pemain
			
			# Matikan semua benturan fisik agar mayat tidak bisa didorong atau melukai pemain
			collision_layer = 0
			collision_mask = 0
			set_physics_process(false)
			
			if has_node("CollisionShape2D"):
				$CollisionShape2D.disabled = true
			if has_node("ShapeMinotaur"):
				$ShapeMinotaur.disabled = true
			if has_node("AreaSerangan"):
				$AreaSerangan.monitoring = false
				$AreaSerangan.monitorable = false
		return

	var nama_animasi = animasi_minotaur.animation

	if nama_animasi == "hurt":
		if not status_mati:
			sedang_terluka = false
			_ubah_state(State.CHASE)

	elif nama_animasi == "angry":
		_ubah_state(State.ATTACK)
		waktu_jeda_serangan = jeda_antar_serangan
		
		var attack_id = (randi() % 3) + 1
		animasi_minotaur.play("attack" + str(attack_id))
		
		await get_tree().create_timer(0.3).timeout 
		if status_mati or sedang_terluka or state_saat_ini != State.ATTACK:
			return
			
		var pemain = get_tree().get_first_node_in_group("player")
		if pemain and not pemain.status_mati:
			var jarak = global_position.distance_to(pemain.global_position)
			if jarak <= jarak_serang + 20.0: 
				pemain.terima_kerusakan(1)

	elif nama_animasi.begins_with("attack"):
		sedang_menyerang = false
		_ubah_state(State.CHASE)
