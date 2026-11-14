extends CharacterBody3D

# =====================================================================
# F-15 EAGLE FIGHTER JET - PLAYER CONTROLLER
# Features:
# - Intuitive Left & Right Arrow (and A/D) turn controls with smooth wing banking
# - Up & Down Arrow (and W/S) pitch controls
# - Coordinated banking: wings tilt gracefully into turns, auto-level on release
# - Zero collision mask: freely weave through skyscrapers without accidental bursts
# - Easy Mode: 300 HP with auto self-repair
# - Twin blasters, Guided Sidewinders, and Bounce-Back Parry
# - Dynamic combat audio effects
# =====================================================================

@export var base_speed: float = 95.0
@export var boost_speed: float = 200.0
@export var brake_speed: float = 45.0
@export var acceleration: float = 70.0

@export var turn_speed: float = 1.85   # Left / Right turn rate in rad/s
@export var pitch_speed: float = 1.65  # Up / Down pitch rate
@export var max_bank_angle: float = 48.0 # Max wing tilt angle in degrees
@export var invert_pitch: bool = false

# Stats - Easy & Forgiving
var current_speed: float = 95.0
var hull: float = 300.0
var max_hull: float = 300.0
var boost_energy: float = 100.0
var max_boost: float = 100.0
var is_boosting: bool = false
var is_crashing: bool = false
var crash_respawn_timer: float = 0.0
var time_since_last_hit: float = 0.0

# Visual Banking
var current_bank: float = 0.0
var current_pitch: float = 0.0

# Bounce-Back (Parry) ability
var bounce_ready: bool = true
var bounce_cooldown: float = 0.8
var bounce_timer: float = 0.0
var bounce_active_timer: float = 0.0
var bounce_active_duration: float = 1.0
var bounce_streak: int = 1

# Weapons
var fire_cooldown: float = 0.09
var fire_timer: float = 0.0
var gun_toggle: int = 0
var player_missile_cooldown: float = 3.0
var player_missile_timer: float = 0.0

# Camera
var is_cockpit_view: bool = false
var chase_cam_pos: Vector3 = Vector3(0, 4.2, 12.0)
var cockpit_cam_pos: Vector3 = Vector3(0, 1.4, -1.2)
var cam_shake_intensity: float = 0.0

# Nodes
var model_root: Node3D
var camera_mount: Node3D
var camera: Camera3D
var parry_sphere: MeshInstance3D
var left_afterburner: MeshInstance3D
var right_afterburner: MeshInstance3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0 # Zero collision mask: Never snag on buildings or terrain!
	
	model_root = $ModelRoot
	camera_mount = $CameraMount
	camera = $CameraMount/Camera3D
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	_load_f15_model()
	_setup_navigation_lights()
	_setup_afterburners()
	_setup_parry_visual()

func _find_f15_path() -> String:
	var candidates = [
		"res://asserts/mcdonnell_douglas_f-15_eagle_fighter_jet.glb",
		"res://assets/mcdonnell_douglas_f-15_eagle_fighter_jet.glb"
	]
	for p in candidates:
		if ResourceLoader.exists(p):
			return p
	return ""

func _load_f15_model() -> void:
	var path = _find_f15_path()
	if path != "":
		var packed = load(path)
		if packed:
			var jet = packed.instantiate()
			# Prominent 0.75x scale so the F-15 is clearly visible & imposing
			jet.scale = Vector3(0.75, 0.75, 0.75)
			model_root.add_child(jet)
			return

	var fallback = CylinderMesh.new()
	fallback.top_radius = 0.2
	fallback.bottom_radius = 1.2
	fallback.height = 9.0
	var inst = MeshInstance3D.new()
	inst.mesh = fallback
	inst.rotation.x = -PI / 2.0
	model_root.add_child(inst)

func _setup_navigation_lights() -> void:
	var tip_mesh = SphereMesh.new()
	tip_mesh.radius = 0.42
	tip_mesh.height = 0.84

	# Left wingtip: Vivid Red Beacon
	var left_light = MeshInstance3D.new()
	left_light.mesh = tip_mesh
	var mat_l = StandardMaterial3D.new()
	mat_l.albedo_color = Color(1.0, 0.1, 0.1)
	mat_l.emission_enabled = true
	mat_l.emission = Color(1.0, 0.15, 0.15)
	mat_l.emission_energy_multiplier = 7.0
	left_light.material_override = mat_l
	left_light.position = Vector3(-5.4, 0.2, 1.6)
	add_child(left_light)

	# Right wingtip: Vivid Green Beacon
	var right_light = MeshInstance3D.new()
	right_light.mesh = tip_mesh
	var mat_r = StandardMaterial3D.new()
	mat_r.albedo_color = Color(0.1, 1.0, 0.25)
	mat_r.emission_enabled = true
	mat_r.emission = Color(0.15, 1.0, 0.25)
	mat_r.emission_energy_multiplier = 7.0
	right_light.material_override = mat_r
	right_light.position = Vector3(5.4, 0.2, 1.6)
	add_child(right_light)

func _setup_afterburners() -> void:
	var flame_mesh = CylinderMesh.new()
	flame_mesh.top_radius = 0.10
	flame_mesh.bottom_radius = 0.46
	flame_mesh.height = 3.6
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.1, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.65, 0.18)
	mat.emission_energy_multiplier = 6.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	left_afterburner = MeshInstance3D.new()
	left_afterburner.mesh = flame_mesh
	left_afterburner.material_override = mat
	left_afterburner.rotation.x = PI / 2.0
	left_afterburner.position = Vector3(-1.2, 0.3, 5.2)
	left_afterburner.visible = false
	add_child(left_afterburner)

	right_afterburner = MeshInstance3D.new()
	right_afterburner.mesh = flame_mesh
	right_afterburner.material_override = mat
	right_afterburner.rotation.x = PI / 2.0
	right_afterburner.position = Vector3(1.2, 0.3, 5.2)
	right_afterburner.visible = false
	add_child(right_afterburner)

func _setup_parry_visual() -> void:
	parry_sphere = MeshInstance3D.new()
	var s_mesh = SphereMesh.new()
	s_mesh.radius = 9.0
	s_mesh.height = 18.0
	parry_sphere.mesh = s_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.95, 1.0, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	parry_sphere.material_override = mat
	parry_sphere.visible = false
	add_child(parry_sphere)

func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return

	if is_crashing:
		crash_respawn_timer -= delta
		if crash_respawn_timer <= 0:
			respawn()
		return

	_handle_timers(delta)
	_handle_camera_toggle()
	_handle_flight_controls(delta)
	_handle_shooting(delta)
	_handle_bounce_back_input(delta)

func _handle_timers(delta: float) -> void:
	time_since_last_hit += delta
	# Forgiving Auto-Repair: heal 6 HP/s after 4s without taking hits
	if time_since_last_hit > 4.0 and hull < max_hull:
		hull = min(max_hull, hull + delta * 6.0)

	if bounce_timer > 0:
		bounce_timer -= delta
		if bounce_timer <= 0:
			bounce_ready = true

	if bounce_active_timer > 0:
		bounce_active_timer -= delta
		if bounce_active_timer <= 0 and parry_sphere:
			parry_sphere.visible = false

	if fire_timer > 0:
		fire_timer -= delta

	if player_missile_timer > 0:
		player_missile_timer -= delta

	if cam_shake_intensity > 0:
		cam_shake_intensity = max(0.0, cam_shake_intensity - delta * 4.0)
		if camera:
			camera.h_offset = randf_range(-cam_shake_intensity, cam_shake_intensity) * 0.35
			camera.v_offset = randf_range(-cam_shake_intensity, cam_shake_intensity) * 0.35

func _handle_camera_toggle() -> void:
	if Input.is_action_just_pressed("toggle_cam") or Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_V):
		if not has_meta("cam_debounced"):
			set_meta("cam_debounced", true)
			toggle_camera()
	else:
		remove_meta("cam_debounced")

func toggle_camera() -> void:
	is_cockpit_view = not is_cockpit_view
	if camera_mount:
		if is_cockpit_view:
			camera_mount.position = cockpit_cam_pos
			if model_root:
				model_root.visible = false
		else:
			camera_mount.position = chase_cam_pos
			if model_root:
				model_root.visible = true

# ---------------------------------------------------------------------
# RESPONSIVE ARCADE FLIGHT: TURN WITH LEFT & RIGHT ARROWS / A & D
# ---------------------------------------------------------------------
func _handle_flight_controls(delta: float) -> void:
	# 1. Turn Left & Right (Left Arrow, Right Arrow, A, D)
	var turn_input = 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		turn_input += 1.0  # Turn Left
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		turn_input -= 1.0  # Turn Right

	# 2. Pitch Up & Down (Up Arrow, Down Arrow, W, S)
	var pitch_input = 0.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		pitch_input += 1.0  # Dive Down
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		pitch_input -= 1.0  # Climb Up

	if invert_pitch:
		pitch_input = -pitch_input

	# 3. Apply Horizontal Turn (World Yaw) so the jet & camera turn smoothly
	rotate_y(turn_input * turn_speed * delta)

	# 4. Apply Pitch (Local X axis)
	rotate_object_local(Vector3.RIGHT, pitch_input * pitch_speed * delta)

	# 5. Coordinated Wing Banking:
	# Turn left -> Bank wings left (negative roll)
	# Turn right -> Bank wings right (positive roll)
	# Release keys -> Smoothly auto-level wings back to 0!
	var target_bank = -turn_input * deg_to_rad(max_bank_angle)
	current_bank = lerp(current_bank, target_bank, delta * 6.5)
	
	if model_root:
		model_root.rotation.z = current_bank

	# 6. Speed & Afterburner Boost
	var target_speed = base_speed
	is_boosting = (Input.is_key_pressed(KEY_SHIFT) or Input.is_action_pressed("move_up")) and boost_energy > 5.0
	
	if is_boosting:
		target_speed = boost_speed
		boost_energy = max(0.0, boost_energy - delta * 25.0)
		left_afterburner.visible = true
		right_afterburner.visible = true
		if camera:
			camera.fov = lerp(camera.fov, 86.0, delta * 5.0)
	else:
		left_afterburner.visible = false
		right_afterburner.visible = false
		boost_energy = min(max_boost, boost_energy + delta * 24.0)
		if camera:
			camera.fov = lerp(camera.fov, 74.0, delta * 4.0)

	if Input.is_key_pressed(KEY_CTRL):
		target_speed = brake_speed

	current_speed = lerp(current_speed, target_speed, acceleration * delta * 0.1)

	var forward_dir = -global_transform.basis.z.normalized()
	velocity = forward_dir * current_speed
	move_and_slide()

	# Altitude safety ground cushion: keep jet above roads & streets
	if global_position.y < 8.0:
		global_position.y = 8.0

	if camera_mount and not is_cockpit_view:
		camera_mount.position = camera_mount.position.lerp(chase_cam_pos, delta * 7.0)

# ---------------------------------------------------------------------
# BOUNCE-BACK PARRY (SPACE / RMB)
# ---------------------------------------------------------------------
func _handle_bounce_back_input(delta: float) -> void:
	var press_parry = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	
	if press_parry and bounce_ready:
		trigger_bounce_back()

func trigger_bounce_back() -> void:
	bounce_ready = false
	bounce_timer = bounce_cooldown
	bounce_active_timer = bounce_active_duration
	
	if parry_sphere:
		parry_sphere.visible = true
		parry_sphere.scale = Vector3.ONE * 0.2
		var tw = create_tween()
		tw.tween_property(parry_sphere, "scale", Vector3.ONE * 1.6, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(parry_sphere, "scale", Vector3.ONE * 1.0, 0.40)

	var main_node = get_parent()
	if main_node and main_node.has_method("execute_player_parry"):
		main_node.execute_player_parry(global_position, 75.0) # 75m generous parry radius!

# ---------------------------------------------------------------------
# BURST EXPLOSION (ONLY ON ZERO HULL / DEATH)
# ---------------------------------------------------------------------
func trigger_crash_burst(hit_pos: Vector3) -> void:
	if is_crashing:
		return
	is_crashing = true
	crash_respawn_timer = 1.6
	
	velocity = Vector3.ZERO
	current_speed = 0.0
	if model_root:
		model_root.visible = false
	if parry_sphere:
		parry_sphere.visible = false
	left_afterburner.visible = false
	right_afterburner.visible = false
	
	var main_node = get_parent()
	if main_node and main_node.has_method("spawn_player_burst_animation"):
		main_node.spawn_player_burst_animation(hit_pos)

func _handle_shooting(delta: float) -> void:
	# Twin Blasters: Q key, Left Click, or Enter
	var fire_btn = Input.is_key_pressed(KEY_Q) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_key_pressed(KEY_ENTER)
	if fire_btn and fire_timer <= 0:
		fire_timer = fire_cooldown
		_shoot_twin_blasters()

	# Guided Sidewinder Missiles: F key
	if Input.is_key_pressed(KEY_F) and player_missile_timer <= 0:
		player_missile_timer = player_missile_cooldown
		_shoot_player_missile()

func _shoot_twin_blasters() -> void:
	var main_node = get_parent()
	if not main_node or not main_node.has_method("spawn_player_bullet"):
		return
		
	gun_toggle = 1 - gun_toggle
	var offset_x = -3.8 if gun_toggle == 0 else 3.8
	var muzzle_pos = global_position + global_transform.basis.x * offset_x - global_transform.basis.z * 5.0
	var shoot_dir = -global_transform.basis.z.normalized()
	
	main_node.spawn_player_bullet(muzzle_pos, shoot_dir)

func _shoot_player_missile() -> void:
	var main_node = get_parent()
	if not main_node or not main_node.has_method("spawn_player_missile"):
		return
		
	var muzzle_pos = global_position - global_transform.basis.y * 1.0 - global_transform.basis.z * 3.5
	main_node.spawn_player_missile(muzzle_pos, -global_transform.basis.z.normalized())

func take_damage(amount: float) -> void:
	if is_crashing:
		return
	
	time_since_last_hit = 0.0
	hull = max(0.0, hull - amount * 0.5) # Forgiving damage reduction
	cam_shake_intensity = 0.7
	
	var main_node = get_parent()
	if main_node and main_node.has_method("on_player_hit_feedback"):
		main_node.on_player_hit_feedback(hull)

	if hull <= 0:
		trigger_crash_burst(global_position)

func respawn() -> void:
	is_crashing = false
	hull = max_hull
	boost_energy = max_boost
	time_since_last_hit = 0.0
	current_bank = 0.0
	global_position = Vector3(0, 180, 400)
	rotation = Vector3.ZERO
	if model_root:
		model_root.rotation = Vector3.ZERO
		model_root.visible = true
	velocity = Vector3.ZERO
	current_speed = base_speed
	if parry_sphere:
		parry_sphere.visible = false
	if camera:
		camera.fov = 75.0
