extends CharacterBody2D

class_name BosMusuh

# --- ENUM STATE ---
enum State {
	PATROL,
	CHASE,
	PREPARE_ATTACK,
	ATTACK_MELEE,
	ATTACK_BLINK,
	ATTACK_RANGED,
	TAUNT,
	HURT,
	DEAD,
	ALIVE
}

# --- EXPORT PARAMETERS ---
@export var proyektil_scene: PackedScene
@export var kecepatan_patroli: float = 120.0
@export var kecepatan_kejar: float = 210.0
@export var kekuatan_lompat: float = -600.0
@export var jeda_lompat: float = 3.0
@export var jeda_antar_serangan: float = 1.
@export var jeda_blink: float = 6.0
@export var jeda_proyektil: float = 3.5
@export var jarak_blink: float = 200.0
@export var kecepatan_proyektil_estimasi: float = 300.0
@export var batas_hp_fase_2: int = 6

# --- PHYSICS ---
var gravitasi: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var akselerasi: float = 900.0

# --- STATE MACHINE ---
var state_saat_ini: State = State.PATROL

# --- TIMERS ---
var waktu_kebal: float = 0.0
var waktu_jeda_serangan: float = 0.0
var waktu_jeda_blink: float = 0.0
var waktu_jeda_proyektil: float = 0.0
var waktu_hitung_lompat: float = 0.0
var waktu_persiapan_serang: float = 0.0
var waktu_taunt: float = 0.0

# --- FLAGS ---
var darah: int = 20
var status_mati: bool = false
var sedang_terluka: bool = false
var sedang_menyerang: bool = false
var sedang_blink: bool = false
var fase_2_aktif: bool = false

# --- MOVEMENT ---
var arah_gerak: float = -1.0

# --- PLAYER TRACKING (untuk prediksi) ---
var posisi_pemain_sebelumnya: Vector2 = Vector2.ZERO
var kecepatan_pemain_estimasi: Vector2 = Vector2.ZERO

# --- ATTACK VARIETY ---
var serangan_terakhir: String = ""
var combo_count: int = 0

# --- NODES ---
@onready var animasi_bos: AnimatedSprite2D = $AnimatedSprite2D
@onready var kotak_benturan: CollisionShape2D = $CollisionShape2D
@onready var area_sentuh: Area2D = $AreaSentuh
@onready var kotak_sentuh: CollisionShape2D = $AreaSentuh/CollisionShape2D
@onready var area_serangan_bos: Area2D = $AreaSeranganBos


# ==============================================================================
# LIFECYCLE
# ==============================================================================

func _ready() -> void:
	animasi_bos.animation_finished.connect(_pada_animasi_selesai)
	waktu_jeda_serangan = 1.0  # Sedikit jeda di awal agar tidak langsung menyerang
	state_saat_ini = State.ALIVE
	animasi_bos.play("alive")

func _physics_process(waktu_delta: float) -> void:
	_kurangi_semua_timer(waktu_delta)

	if not is_on_floor():
		velocity.y += gravitasi * waktu_delta

	_proses_state_machine(waktu_delta)
	move_and_slide()


# ==============================================================================
# STATE MACHINE — INTI
# ==============================================================================

func _proses_state_machine(dt: float) -> void:
	var pemain = get_tree().get_first_node_in_group("player")

	# State DEAD, HURT, dan ALIVE tidak butuh pemain
	if state_saat_ini == State.DEAD or state_saat_ini == State.ALIVE:
		velocity.x = 0
		return

	if state_saat_ini == State.HURT:
		velocity.x = move_toward(velocity.x, 0.0, akselerasi * dt)
		return

	if state_saat_ini == State.TAUNT:
		velocity.x = move_toward(velocity.x, 0.0, akselerasi * dt)
		waktu_taunt -= dt
		if waktu_taunt <= 0.0:
			_ubah_state(State.CHASE)
		return

	# Jika tidak ada pemain, patroli saja
	if not pemain or pemain.status_mati:
		_ubah_state(State.PATROL)
		_proses_patrol(dt)
		return

	# Update estimasi kecepatan pemain untuk prediksi
	_perbarui_estimasi_pemain(pemain, dt)
	cek_sentuhan_badan()

	# Cek fase 2
	if not fase_2_aktif and darah <= batas_hp_fase_2:
		_aktifkan_fase_2()
		return

	var jarak := global_position.distance_to(pemain.global_position)
	var delta_x: float = pemain.global_position.x - global_position.x

	match state_saat_ini:
		State.PATROL:
			_proses_patrol(dt)
			if jarak < 400.0:
				_ubah_state(State.CHASE)

		State.CHASE:
			_proses_kejar(dt, pemain, jarak, delta_x)

		State.PREPARE_ATTACK:
			# Jeda singkat sebelum menyerang — terasa lebih "disengaja"
			velocity.x = move_toward(velocity.x, 0.0, akselerasi * dt)
			waktu_persiapan_serang -= dt
			if waktu_persiapan_serang <= 0.0:
				_pilih_dan_jalankan_serangan(pemain, jarak, delta_x)

		State.ATTACK_MELEE, State.ATTACK_RANGED, State.ATTACK_BLINK:
			velocity.x = 0


# ==============================================================================
# STATE: PATROL
# ==============================================================================

func _proses_patrol(dt: float) -> void:
	if is_on_wall():
		arah_gerak *= -1.0

	velocity.x = move_toward(velocity.x, arah_gerak * kecepatan_patroli, akselerasi * dt)
	animasi_bos.flip_h = velocity.x < 0

	# Lompat rutin saat patroli
	waktu_hitung_lompat += dt
	if is_on_floor() and waktu_hitung_lompat >= jeda_lompat:
		velocity.y = kekuatan_lompat
		waktu_hitung_lompat = 0.0

	if is_on_floor() and abs(velocity.x) > 10.0:
		animasi_bos.play("run")
	else:
		animasi_bos.play("idle")


# ==============================================================================
# STATE: CHASE
# ==============================================================================

func _proses_kejar(dt: float, pemain: Node, jarak: float, delta_x: float) -> void:
	arah_gerak = 1.0 if delta_x > 0 else -1.0

	# Cek apakah ada serangan yang tersedia
	if waktu_jeda_serangan <= 0:
		var ada_serangan_tersedia := (
			_cek_pemain_di_area_melee(pemain) or
			(jarak > 100.0 and jarak <= 250.0 and waktu_jeda_blink <= 0) or
			(jarak > 250.0 and waktu_jeda_proyektil <= 0)
		)
		if ada_serangan_tersedia:
			_ubah_state(State.PREPARE_ATTACK)
			# Fase 2: waktu persiapan lebih pendek (lebih agresif)
			waktu_persiapan_serang = 0.12 if fase_2_aktif else 0.22
			return

	# Prediksi posisi pemain sedikit ke depan agar pengejaran tidak kaku
	var posisi_prediksi := posisi_pemain_sebelumnya + kecepatan_pemain_estimasi * 0.15
	var arah_prediksi := posisi_prediksi.x - global_position.x

	var kecepatan_saat_ini := kecepatan_kejar if fase_2_aktif else kecepatan_patroli
	var target_vx: float = sign(arah_prediksi) * kecepatan_saat_ini if abs(arah_prediksi) > 15.0 else 0.0
	velocity.x = move_toward(velocity.x, target_vx, akselerasi * dt)

	# Lompat cerdas: lebih sering jika pemain berada di atas
	var selisih_y: float = pemain.global_position.y - global_position.y
	waktu_hitung_lompat += dt
	var jeda_lompat_efektif := jeda_lompat * (0.5 if selisih_y < -80.0 else 1.0)
	if is_on_floor() and waktu_hitung_lompat >= jeda_lompat_efektif:
		velocity.y = kekuatan_lompat
		waktu_hitung_lompat = 0.0

	animasi_bos.flip_h = arah_gerak < 0
	_perbarui_posisi_area_serang()

	if is_on_floor():
		animasi_bos.play("run" if abs(velocity.x) > 10.0 else "idle")


# ==============================================================================
# PEMILIHAN SERANGAN
# ==============================================================================

func _pilih_dan_jalankan_serangan(pemain: Node, jarak: float, delta_x: float) -> void:
	arah_gerak = 1.0 if delta_x > 0 else -1.0

	var bisa_melee   := _cek_pemain_di_area_melee(pemain)
	var bisa_blink   := jarak > 100.0 and jarak <= 250.0 and waktu_jeda_blink <= 0
	var bisa_ranged  := jarak > 250.0 and waktu_jeda_proyektil <= 0

	# Bangun daftar opsi dengan pembobotan (semakin banyak entri = semakin tinggi peluang)
	var opsi: Array[String] = []
	if bisa_melee:
		opsi.append_array(["melee", "melee"])  # Bobot x2 karena paling efektif
		if fase_2_aktif:
			opsi.append("melee")  # Bobot lebih tinggi di fase 2
	if bisa_blink:
		opsi.append("blink")
		if jarak > 180.0:
			opsi.append("blink")  # Blink lebih disukai jika jarak menengah-jauh
	if bisa_ranged:
		opsi.append("ranged")

	if opsi.is_empty():
		_ubah_state(State.CHASE)
		return

	# Hindari mengulang serangan yang sama terus menerus
	var opsi_bervariasi := opsi.filter(func(s): return s != serangan_terakhir)
	if not opsi_bervariasi.is_empty():
		opsi = opsi_bervariasi

	var pilihan: String = opsi[randi() % opsi.size()]
	serangan_terakhir = pilihan

	match pilihan:
		"melee":   _jalankan_serangan_melee(pemain)
		"blink":   _jalankan_blink()
		"ranged":  _jalankan_serangan_jauh()


# ==============================================================================
# SERANGAN: MELEE
# ==============================================================================

func _jalankan_serangan_melee(pemain: Node) -> void:
	_ubah_state(State.ATTACK_MELEE)
	sedang_menyerang = true
	waktu_jeda_serangan = jeda_antar_serangan
	animasi_bos.flip_h = arah_gerak < 0
	_perbarui_posisi_area_serang()
	animasi_bos.play("attack")

	await get_tree().create_timer(0.2).timeout

	if status_mati or sedang_terluka or state_saat_ini != State.ATTACK_MELEE:
		return

	# Cek hit
	var terkena := false
	for target in area_serangan_bos.get_overlapping_bodies():
		if target is KarakterUtama and not target.status_mati:
			target.terima_kerusakan(1)
			terkena = true
			break

	# Fase 2: jika mengenai, bisa menyerang lagi (combo)
	if terkena and fase_2_aktif and combo_count < 2:
		combo_count += 1
		await get_tree().create_timer(0.25).timeout
		if not status_mati and not sedang_terluka:
			animasi_bos.play("attack")
			await get_tree().create_timer(0.2).timeout
			if not status_mati and not sedang_terluka:
				for target in area_serangan_bos.get_overlapping_bodies():
					if target is KarakterUtama and not target.status_mati:
						target.terima_kerusakan(1)
						break
	else:
		combo_count = 0


# ==============================================================================
# SERANGAN: RANGED (dengan prediksi posisi pemain)
# ==============================================================================

func _jalankan_serangan_jauh() -> void:
	_ubah_state(State.ATTACK_RANGED)
	sedang_menyerang = true
	waktu_jeda_proyektil = jeda_proyektil
	animasi_bos.flip_h = arah_gerak < 0
	_perbarui_posisi_area_serang()
	animasi_bos.play("longattack")

	await get_tree().create_timer(0.3).timeout

	if status_mati or sedang_terluka or state_saat_ini != State.ATTACK_RANGED:
		return

	if not proyektil_scene:
		return

	# Hitung arah proyektil dengan prediksi posisi pemain
	var arah_tembak := arah_gerak
	var pemain = get_tree().get_first_node_in_group("player")
	if pemain and not pemain.status_mati:
		var posisi_prediksi := _hitung_posisi_intersep(
			pemain.global_position, kecepatan_pemain_estimasi, kecepatan_proyektil_estimasi
		)
		arah_tembak = sign(posisi_prediksi.x - global_position.x)

	_tembak_proyektil(arah_tembak, Vector2(arah_tembak * 30, 0))

	# Fase 2: tembak proyektil kedua dengan sedikit jeda
	if fase_2_aktif:
		await get_tree().create_timer(0.35).timeout
		if not status_mati and not sedang_terluka:
			_tembak_proyektil(arah_tembak, Vector2(arah_tembak * 30, -18))

func _tembak_proyektil(arah: float, offset: Vector2) -> void:
	var proyektil := proyektil_scene.instantiate()
	proyektil.global_position = global_position + offset
	proyektil.arah_gerak = arah
	proyektil.scale.x = abs(proyektil.scale.x) * (1.0 if arah >= 0 else -1.0)
	get_tree().current_scene.add_child(proyektil)

func _hitung_posisi_intersep(pos_target: Vector2, vel_target: Vector2, kecepatan_proyektil: float) -> Vector2:
	# Estimasi waktu terbang berdasarkan jarak saat ini, lalu prediksi posisi
	var jarak := global_position.distance_to(pos_target)
	var waktu_terbang: float = clamp(jarak / max(kecepatan_proyektil, 1.0), 0.0, 0.6)
	return pos_target + vel_target * waktu_terbang


# ==============================================================================
# SERANGAN: BLINK / DASH
# ==============================================================================

func _jalankan_blink() -> void:
	_ubah_state(State.ATTACK_BLINK)
	sedang_blink = true
	waktu_jeda_blink = jeda_blink
	animasi_bos.flip_h = arah_gerak < 0
	_perbarui_posisi_area_serang()
	animasi_bos.play("blink")

	await get_tree().create_timer(0.4).timeout

	if status_mati or sedang_terluka:
		sedang_blink = false
		_ubah_state(State.CHASE)
		return

	# Raycast untuk mencegah blink menembus dinding
	var posisi_awal := global_position
	var posisi_target := global_position + Vector2(arah_gerak * jarak_blink, 0)
	var kueri := PhysicsRayQueryParameters2D.create(posisi_awal, posisi_target)
	kueri.exclude = [self]
	kueri.collision_mask = 1
	var hasil := get_world_2d().direct_space_state.intersect_ray(kueri)

	if hasil:
		global_position.x = hasil.position.x - (arah_gerak * 20)
	else:
		global_position.x = posisi_target.x


# ==============================================================================
# SISTEM DAMAGE & FASE
# ==============================================================================

func cek_sentuhan_badan() -> void:
	for target in area_sentuh.get_overlapping_bodies():
		if target is KarakterUtama and not target.status_mati:
			target.terima_kerusakan(1)

func terima_kerusakan(jumlah: int) -> void:
	if status_mati or waktu_kebal > 0:
		return

	darah -= jumlah

	if darah <= 0:
		status_mati = true
		_ubah_state(State.DEAD)
		animasi_bos.play("death")
		kotak_sentuh.set_deferred("disabled", true)
	else:
		waktu_kebal = 1.5
		sedang_terluka = true
		sedang_menyerang = false
		sedang_blink = false
		combo_count = 0
		_ubah_state(State.HURT)
		animasi_bos.play("hurt")

func _aktifkan_fase_2() -> void:
	fase_2_aktif = true
	# Boss "taunt" sebentar sebelum menjadi lebih agresif
	_ubah_state(State.TAUNT)
	waktu_taunt = 1.2
	animasi_bos.play("idle")  # Ganti ke animasi taunt jika ada


# ==============================================================================
# HELPERS
# ==============================================================================

func _ubah_state(state_baru: State) -> void:
	state_saat_ini = state_baru

func _perbarui_estimasi_pemain(pemain: Node, dt: float) -> void:
	if dt > 0:
		kecepatan_pemain_estimasi = (pemain.global_position - posisi_pemain_sebelumnya) / dt
	posisi_pemain_sebelumnya = pemain.global_position

func _perbarui_posisi_area_serang() -> void:
	area_serangan_bos.position.x = abs(area_serangan_bos.position.x) * (1.0 if arah_gerak > 0 else -1.0)

func _cek_pemain_di_area_melee(pemain: Node) -> bool:
	for tubuh in area_serangan_bos.get_overlapping_bodies():
		if tubuh == pemain:
			return true
	return false

func _kurangi_semua_timer(dt: float) -> void:
	waktu_kebal          = max(waktu_kebal - dt, 0.0)
	waktu_jeda_serangan  = max(waktu_jeda_serangan - dt, 0.0)
	waktu_jeda_blink     = max(waktu_jeda_blink - dt, 0.0)
	waktu_jeda_proyektil = max(waktu_jeda_proyektil - dt, 0.0)


# ==============================================================================
# ANIMATION CALLBACKS
# ==============================================================================

func _pada_animasi_selesai() -> void:
	if status_mati:
		return

	match animasi_bos.animation:
		"alive":
			_ubah_state(State.PATROL)
		"hurt":
			sedang_terluka = false
			_ubah_state(State.CHASE)
		"attack":
			sedang_menyerang = false
			_ubah_state(State.CHASE)
		"longattack":
			sedang_menyerang = false
			_ubah_state(State.CHASE)
		"blink":
			sedang_blink = false
			_ubah_state(State.CHASE)
