extends Node3D

# =====================================================================
# SKY FIGHTER: RICOCHET SKIES - MAIN GAME CONTROLLER
# Environment:
# - Multi-tile San Francisco mega-city with visible, dry roads
# - Pine Forest Mountain perimeter (pine_forest_at_sunset.glb) & peaks
# - Boundless ocean wrapping outside the mountain coastlines at y = -22.0
# - Solid building colliders -> triggers BURST explosion on collision
# Gameplay (EASY MODE & HIGH VISIBILITY):
# - Slower enemy missiles (85 m/s) with 5.5s reset countdown
# - BIG Center HUD Alert: "🚨 MISSILE LOCKED ON! PRESS [SPACE] TO PARRY! 🚨"
# - Tactical Circular Radar in top-right with RED DOTS for Su-57s
# - High-visibility Diamond Target Brackets on HUD: [ 🔶 SU-57 420m ]
# - F-15 scaled up with wingtip nav lights for maximum visibility
# - Smooth keyboard flight controls (Mouse flight removed)
# =====================================================================

const ARENA_RADIUS: float = 2400.0
const CEIL_LIMIT: float = 780.0
const FLOOR_LIMIT: float = 0.5

enum GameState { TITLE, PLAYING, PAUSED, GAME_OVER }
var state: GameState = GameState.TITLE

var player: CharacterBody3D
var enemies: Array = []
var missiles: Array = []
var bullets: Array = []
var debris_pieces: Array = []

var score: int = 0
var bounce_streak: int = 1
var wave: int = 1
var is_ace_difficulty: bool = false

# UI References
var ui_layer: CanvasLayer
var title_screen: Control
var pause_menu: Control
var hud_root: Control
var corner_menu_btn: Button
var damage_flash_rect: ColorRect
var tactical_radar: Control

# HUD elements
var score_label: Label
var wave_label: Label
var enemies_label: Label
var streak_label: Label
var prompt_label: Label
var speed_label: Label
var hull_bar: ProgressBar
var boost_bar: ProgressBar
var bounce_bar: ProgressBar
var missile_lock_panel: PanelContainer
var missile_lock_label: Label
var radar_target_brackets: Control


# Audio System
var snd_missile_launch: AudioStream
var snd_explosion: AudioStream
var snd_laser: AudioStream
var snd_parry: AudioStream
var snd_alarm: AudioStream

var audio_pool: Array = []
var max_audio_players: int = 14
var alarm_cooldown: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	player = get_node_or_null("Player")
	if not player:
		var p_scene = load("res://scenes/player.tscn")
		if p_scene:
			player = p_scene.instantiate()
			add_child(player)
	if player:
		player.process_mode = Node.PROCESS_MODE_PAUSABLE
		player.position = Vector3(0, 180, 400)
		player.rotation = Vector3.ZERO
	
	_setup_audio_system()
	_setup_lighting_and_sky()
	_setup_world_environment()
	_build_ui_system()
	
	_show_title_screen()

func _find_path(filename: String) -> String:
	var paths = [
		"res://asserts/" + filename,
		"res://assets/" + filename
	]
	for p in paths:
		if ResourceLoader.exists(p):
			return p
	return ""

# ---------------------------------------------------------------------
# SKY & DAYLIGHT LIGHTING
# ---------------------------------------------------------------------

func _setup_audio_system() -> void:
	snd_missile_launch = load("res://audio/missile_launch.wav")
	snd_explosion = load("res://audio/collision_explosion.wav")
	snd_laser = load("res://audio/laser_shot.wav")
	snd_parry = load("res://audio/parry_bounce.wav")
	snd_alarm = load("res://audio/lockon_alarm.wav")
	
	for i in range(max_audio_players):
		var asp = AudioStreamPlayer.new()
		asp.bus = "Master"
		add_child(asp)
		audio_pool.append(asp)

func play_sound(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not stream:
		return
	for asp in audio_pool:
		if not asp.playing:
			asp.stream = stream
			asp.volume_db = volume_db
			asp.pitch_scale = pitch_scale
			asp.play()
			return

func _setup_lighting_and_sky() -> void:
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.18, 0.46, 0.88)
	sky_mat.sky_horizon_color = Color(0.72, 0.84, 0.98)
	sky_mat.ground_bottom_color = Color(0.08, 0.14, 0.22)
	sky_mat.ground_horizon_color = Color(0.62, 0.76, 0.92)
	sky_mat.sun_angle_max = 35.0
	
	var sky_res = Sky.new()
	sky_res.sky_material = sky_mat
	env.sky = sky_res
	
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_energy = 1.05
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.4
	
	var world_env = $WorldEnvironment
	if world_env:
		world_env.environment = env

	var sun = $DirectionalLight3D
	if sun:
		sun.light_color = Color(1.0, 0.98, 0.93)
		sun.light_energy = 1.7
		sun.shadow_enabled = true

# ---------------------------------------------------------------------
# ENVIRONMENT GENERATOR: DRY ROADS, MOUNTAINS, OCEAN OUTSIDE
# ---------------------------------------------------------------------
func _setup_world_environment() -> void:
	var env_root = $EnvironmentRoot
	if not env_root:
		return

	for c in env_root.get_children():
		c.queue_free()

	# 1. SOLID ISLAND / CITY FOUNDATION (Dark asphalt tarmac at y = -0.4 so roads are dry & visible!)
	var ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(3600.0, 3600.0)
	var ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.20, 0.22, 0.25)
	ground_mat.roughness = 0.85
	var city_ground = MeshInstance3D.new()
	city_ground.mesh = ground_mesh
	city_ground.material_override = ground_mat
	city_ground.position = Vector3(0, -0.4, 0)
	env_root.add_child(city_ground)

	# 2. DENSE MULTI-TILED SAN FRANCISCO MEGA-CITY (Zero colliders -> free flight between skyscrapers!)
	var sf_path = _find_path("SanFrancisco_City.fbx")
	var proc_path = _find_path("procedural_city_7.glb")
	
	var sf_scene = load(sf_path) if sf_path != "" else null
	var proc_scene = load(proc_path) if proc_path != "" else null

	var city_sectors = [
		Vector3(0, 0, 0),
		Vector3(420, 0, 0),
		Vector3(-420, 0, 0),
		Vector3(0, 0, 420),
		Vector3(0, 0, -420),
		Vector3(420, 0, 420),
		Vector3(-420, 0, -420),
		Vector3(-420, 0, 420),
		Vector3(420, 0, -420)
	]

	var rot_angles = [0.0, PI * 0.5, PI, PI * 1.5, 0.0, PI * 0.5, PI, PI * 1.5, 0.0]

	for i in range(city_sectors.size()):
		var pos = city_sectors[i]
		var rot_y = rot_angles[i]

		if sf_scene:
			var sf_inst = sf_scene.instantiate()
			sf_inst.scale = Vector3(0.045, 0.045, 0.045)
			sf_inst.position = pos
			sf_inst.rotation.y = rot_y
			env_root.add_child(sf_inst)

		if proc_scene:
			var proc_inst = proc_scene.instantiate()
			proc_inst.scale = Vector3(1.15, 1.15, 1.15)
			proc_inst.position = pos + Vector3(100, 0, 100)
			proc_inst.rotation.y = rot_y + PI * 0.25
			env_root.add_child(proc_inst)

	# 3. PINE FOREST MOUNTAIN PERIMETER (pine_forest_at_sunset.glb)
	var pine_path = _find_path("pine_forest_at_sunset.glb")
	var pine_scene = load(pine_path) if pine_path != "" else null

	var mountain_ring = [
		{"pos": Vector3(1450, -2, 1450), "scale": 8.0, "yaw": 0.4},
		{"pos": Vector3(-1450, -2, 1450), "scale": 8.2, "yaw": 1.8},
		{"pos": Vector3(1450, -2, -1450), "scale": 8.0, "yaw": 3.4},
		{"pos": Vector3(-1450, -2, -1450), "scale": 8.3, "yaw": 4.9},
		{"pos": Vector3(0, -2, 1650), "scale": 8.5, "yaw": 1.1},
		{"pos": Vector3(0, -2, -1650), "scale": 8.5, "yaw": 4.3},
		{"pos": Vector3(1650, -2, 0), "scale": 8.2, "yaw": 2.6},
		{"pos": Vector3(-1650, -2, 0), "scale": 8.4, "yaw": 5.6},
		{"pos": Vector3(1100, -2, 1100), "scale": 7.8, "yaw": 0.9},
		{"pos": Vector3(-1100, -2, 1100), "scale": 7.8, "yaw": 2.4},
		{"pos": Vector3(1100, -2, -1100), "scale": 7.8, "yaw": 3.8},
		{"pos": Vector3(-1100, -2, -1100), "scale": 7.8, "yaw": 5.1}
	]

	for m_data in mountain_ring:
		if pine_scene:
			var pine = pine_scene.instantiate()
			# pine_forest_at_sunset.glb is upright Y-up (X=260, Y=18.9, Z=260)
			pine.scale = Vector3(m_data["scale"], 16.0, m_data["scale"])
			pine.position = m_data["pos"]
			pine.rotation.y = m_data["yaw"]
			env_root.add_child(pine)
		else:
			# Majestic procedural mountain massif with evergreen pine foothills
			var m_group = Node3D.new()
			m_group.position = m_data["pos"]
			m_group.rotation.y = m_data["yaw"]

			# 1. Primary Rugged Peak (Evergreen forest slope with granite ridge)
			var main_peak = MeshInstance3D.new()
			var p_mesh = CylinderMesh.new()
			p_mesh.top_radius = 12.0
			p_mesh.bottom_radius = 420.0
			p_mesh.height = 360.0
			p_mesh.radial_segments = 9 # Stylized faceted mountain look
			main_peak.mesh = p_mesh

			var m_mat = StandardMaterial3D.new()
			m_mat.albedo_color = Color(0.13, 0.24, 0.15) # Deep coastal pine green
			m_mat.roughness = 0.92
			main_peak.material_override = m_mat
			main_peak.position = Vector3(0, 160, 0)
			m_group.add_child(main_peak)

			# 2. Granite Rocky Cap on Summit
			var cap = MeshInstance3D.new()
			var cap_mesh = CylinderMesh.new()
			cap_mesh.top_radius = 4.0
			cap_mesh.bottom_radius = 95.0
			cap_mesh.height = 110.0
			cap_mesh.radial_segments = 7
			cap.mesh = cap_mesh

			var cap_mat = StandardMaterial3D.new()
			cap_mat.albedo_color = Color(0.38, 0.40, 0.38) # Granite alpine rock
			cap_mat.roughness = 0.85
			cap.material_override = cap_mat
			cap.position = Vector3(0, 310, 0)
			m_group.add_child(cap)

			# 3. Flanking Sub-Peaks for natural mountain range silhouette
			var sub_offsets = [Vector3(-180, 80, -90), Vector3(190, 90, 80)]
			for s_pos in sub_offsets:
				var sub_peak = MeshInstance3D.new()
				var s_mesh = CylinderMesh.new()
				s_mesh.top_radius = 8.0
				s_mesh.bottom_radius = 260.0
				s_mesh.height = 220.0
				s_mesh.radial_segments = 8
				sub_peak.mesh = s_mesh
				sub_peak.material_override = m_mat
				sub_peak.position = s_pos
				m_group.add_child(sub_peak)

			# 4. Evergreen Pine Tree Clusters in Foothills facing the city
			var tree_mat = StandardMaterial3D.new()
			tree_mat.albedo_color = Color(0.08, 0.20, 0.10) # Dark Douglas fir
			tree_mat.roughness = 0.95

			var tree_offsets = [
				Vector3(-90, 15, 120), Vector3(-40, 12, 160), Vector3(20, 14, 140),
				Vector3(80, 16, 110), Vector3(-130, 20, 80), Vector3(120, 18, 60)
			]
			for t_pos in tree_offsets:
				var tree = MeshInstance3D.new()
				var t_mesh = CylinderMesh.new()
				t_mesh.top_radius = 0.5
				t_mesh.bottom_radius = 18.0
				t_mesh.height = 42.0
				t_mesh.radial_segments = 6
				tree.mesh = t_mesh
				tree.material_override = tree_mat
				tree.position = t_pos
				m_group.add_child(tree)

			env_root.add_child(m_group)

	# 4. BOUNDLESS OCEAN PLACED OUTSIDE & BELOW THE CITY (y = -22.0)
	var ocean = MeshInstance3D.new()
	var ocean_mesh = PlaneMesh.new()
	ocean_mesh.size = Vector2(45000.0, 45000.0)
	
	var ocean_mat = StandardMaterial3D.new()
	ocean_mat.albedo_color = Color(0.04, 0.12, 0.22)
	ocean_mat.roughness = 0.18
	ocean_mat.metallic = 0.85
	
	ocean.mesh = ocean_mesh
	ocean.material_override = ocean_mat
	ocean.position = Vector3(0, -22.0, 0)
	env_root.add_child(ocean)

func _create_glass_button_style(bg_color: Color = Color(0.06, 0.12, 0.20, 0.88), border_color: Color = Color(0.28, 0.88, 1.0, 0.85)) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	return sb

func _style_button(btn: Button, accent_color: Color = Color(0.28, 0.88, 1.0)) -> void:
	var normal_style = _create_glass_button_style(Color(0.06, 0.12, 0.20, 0.88), accent_color)
	var hover_style = _create_glass_button_style(Color(0.10, 0.22, 0.36, 0.95), Color(0.4, 1.0, 1.0))
	var pressed_style = _create_glass_button_style(Color(0.16, 0.34, 0.52, 1.0), Color(0.6, 1.0, 1.0))
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

func _build_ui_system() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var screen_rect = Control.new()
	screen_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(screen_rect)

	damage_flash_rect = ColorRect.new()
	damage_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash_rect.color = Color(1.0, 0.05, 0.05, 0.0)
	damage_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen_rect.add_child(damage_flash_rect)

	_build_in_game_hud(screen_rect)
	_build_title_screen(screen_rect)
	_build_pause_menu(screen_rect)

func _build_in_game_hud(parent: Control) -> void:
	hud_root = Control.new()
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hud_root)

	var reticle = Label.new()
	reticle.text = "[   +   ]"
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.modulate = Color(0.4, 0.95, 1.0, 0.75)
	hud_root.add_child(reticle)

	radar_target_brackets = Control.new()
	radar_target_brackets.set_anchors_preset(Control.PRESET_FULL_RECT)
	radar_target_brackets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(radar_target_brackets)

	# TACTICAL CIRCULAR RADAR IN TOP-RIGHT CORNER (RED DOTS FOR SU-57)
	var radar_script = load("res://scripts/radar.gd")
	if radar_script:
		tactical_radar = Control.new()
		tactical_radar.set_script(radar_script)
		tactical_radar.position = Vector2(get_viewport().get_visible_rect().size.x - 165, 18)
		tactical_radar.set("player_ref", player)
		tactical_radar.set("enemies_ref", enemies)
		tactical_radar.set("missiles_ref", missiles)
		hud_root.add_child(tactical_radar)

	# Top-Left Mission HUD Panel
	var tl_panel = PanelContainer.new()
	tl_panel.position = Vector2(24, 18)
	var tl_style = _create_glass_button_style(Color(0.04, 0.08, 0.15, 0.8), Color(0.2, 0.6, 0.8, 0.5))
	tl_panel.add_theme_stylebox_override("panel", tl_style)
	hud_root.add_child(tl_panel)

	var tl_box = VBoxContainer.new()
	tl_panel.add_child(tl_box)

	score_label = Label.new()
	score_label.text = "SCORE: 0000000"
	score_label.modulate = Color(0.4, 0.95, 1.0)
	tl_box.add_child(score_label)

	wave_label = Label.new()
	wave_label.text = "WAVE: 1"
	wave_label.modulate = Color(1.0, 0.85, 0.4)
	tl_box.add_child(wave_label)

	enemies_label = Label.new()
	enemies_label.text = "SU-57 HOSTILES: 0"
	enemies_label.modulate = Color(1.0, 0.4, 0.4)
	tl_box.add_child(enemies_label)

	streak_label = Label.new()
	streak_label.text = "BOUNCE STREAK: x1"
	streak_label.modulate = Color(1.0, 0.45, 0.8)
	tl_box.add_child(streak_label)

	corner_menu_btn = Button.new()
	corner_menu_btn.text = " ⏸ MENU [ESC] "
	corner_menu_btn.position = Vector2(24, 125)
	_style_button(corner_menu_btn)
	corner_menu_btn.pressed.connect(_on_corner_menu_pressed)
	hud_root.add_child(corner_menu_btn)

	# UNMISSABLE CENTER SCREEN MISSILE LOCK ALERT BANNER!
	missile_lock_panel = PanelContainer.new()
	missile_lock_panel.set_anchors_preset(Control.PRESET_CENTER)
	missile_lock_panel.position -= Vector2(280, 110)
	missile_lock_panel.custom_minimum_size = Vector2(560, 60)
	var warn_style = _create_glass_button_style(Color(0.25, 0.04, 0.04, 0.92), Color(1.0, 0.25, 0.25, 1.0))
	missile_lock_panel.add_theme_stylebox_override("panel", warn_style)
	missile_lock_panel.visible = false
	hud_root.add_child(missile_lock_panel)

	missile_lock_label = Label.new()
	missile_lock_label.text = "🚨 MISSILE LOCKED ON! PRESS [SPACE] TO PARRY! 🚨"
	missile_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	missile_lock_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	missile_lock_label.modulate = Color(1.0, 0.95, 0.3)
	missile_lock_panel.add_child(missile_lock_label)

	# Center Action Prompt
	prompt_label = Label.new()
	prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	prompt_label.position.y += 120
	prompt_label.text = "⚡ PRESS [SPACE] NOW TO BOUNCE BACK! ⚡"
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.modulate = Color(0.25, 1.0, 0.75, 0.0)
	hud_root.add_child(prompt_label)

	# Bottom Panel: Hull, Boost, Bounce, Speed, Altitude
	var bot_y = get_viewport().get_visible_rect().size.y - 72

	var hull_lbl = Label.new()
	hull_lbl.position = Vector2(28, bot_y - 20)
	hull_lbl.text = "HULL INTEGRITY (EASY: 250 HP)"
	hull_lbl.modulate = Color(0.7, 0.88, 1.0)
	hud_root.add_child(hull_lbl)

	hull_bar = ProgressBar.new()
	hull_bar.position = Vector2(28, bot_y)
	hull_bar.size = Vector2(220, 16)
	hull_bar.max_value = 250
	hull_bar.value = 250
	hull_bar.show_percentage = false
	hud_root.add_child(hull_bar)

	var boost_lbl = Label.new()
	boost_lbl.position = Vector2(275, bot_y - 20)
	boost_lbl.text = "AFTERBURNER [SHIFT]"
	boost_lbl.modulate = Color(1.0, 0.8, 0.35)
	hud_root.add_child(boost_lbl)

	boost_bar = ProgressBar.new()
	boost_bar.position = Vector2(275, bot_y)
	boost_bar.size = Vector2(200, 16)
	boost_bar.max_value = 100
	boost_bar.value = 100
	boost_bar.show_percentage = false
	hud_root.add_child(boost_bar)

	var parry_lbl = Label.new()
	parry_lbl.position = Vector2(500, bot_y - 20)
	parry_lbl.text = "BOUNCE PARRY SHIELD [SPACE]"
	parry_lbl.modulate = Color(0.3, 1.0, 0.75)
	hud_root.add_child(parry_lbl)

	bounce_bar = ProgressBar.new()
	bounce_bar.position = Vector2(500, bot_y)
	bounce_bar.size = Vector2(210, 16)
	bounce_bar.max_value = 1.0
	bounce_bar.value = 1.0
	bounce_bar.show_percentage = false
	hud_root.add_child(bounce_bar)

	speed_label = Label.new()
	speed_label.position = Vector2(get_viewport().get_visible_rect().size.x - 240, bot_y - 12)
	speed_label.text = "AIRSPEED: 0 KM/H\nALTITUDE: 0 M"
	speed_label.modulate = Color(0.9, 0.95, 1.0)
	hud_root.add_child(speed_label)

func _build_title_screen(parent: Control) -> void:
	title_screen = Control.new()
	title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(title_screen)

	var bg_overlay = ColorRect.new()
	bg_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_overlay.color = Color(0.04, 0.07, 0.14, 0.90)
	title_screen.add_child(bg_overlay)

	var center_panel = PanelContainer.new()
	center_panel.set_anchors_preset(Control.PRESET_CENTER)
	var panel_style = _create_glass_button_style(Color(0.05, 0.09, 0.16, 0.92), Color(0.28, 0.88, 1.0, 0.9))
	center_panel.add_theme_stylebox_override("panel", panel_style)
	center_panel.custom_minimum_size = Vector2(620, 480)
	center_panel.position -= Vector2(310, 240)
	title_screen.add_child(center_panel)

	var center_box = VBoxContainer.new()
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_panel.add_child(center_box)

	var top_badge = Label.new()
	top_badge.text = "« TOP SECRET // AIR SUPERIORITY TACTICAL DEFENSE »"
	top_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_badge.modulate = Color(0.7, 0.85, 1.0, 0.7)
	center_box.add_child(top_badge)

	var title = Label.new()
	title.text = "SKY FIGHTER: RICOCHET SKIES"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.4, 0.95, 1.0)
	center_box.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "F-15 EAGLE · SAN FRANCISCO AIRSPACE vs SU-57 FELON"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1.0, 0.55, 0.8)
	center_box.add_child(subtitle)

	var spacer1 = Control.new()
	spacer1.custom_minimum_size.y = 18
	center_box.add_child(spacer1)

	var start_btn = Button.new()
	start_btn.text = "🚀  LAUNCH MISSION / START GAME"
	start_btn.custom_minimum_size = Vector2(360, 52)
	_style_button(start_btn, Color(0.2, 0.95, 0.7))
	start_btn.pressed.connect(_on_start_game_pressed)
	center_box.add_child(start_btn)

	var diff_btn = Button.new()
	diff_btn.text = "MODE: EASY (FORGIVING)"
	diff_btn.custom_minimum_size = Vector2(360, 38)
	_style_button(diff_btn)
	diff_btn.pressed.connect(func():
		is_ace_difficulty = not is_ace_difficulty
		diff_btn.text = "MODE: ACE (HARD)" if is_ace_difficulty else "MODE: EASY (FORGIVING)"
	)
	center_box.add_child(diff_btn)

	var pitch_btn = Button.new()
	pitch_btn.text = "FLIGHT PITCH: NORMAL"
	pitch_btn.custom_minimum_size = Vector2(360, 38)
	_style_button(pitch_btn)
	pitch_btn.pressed.connect(func():
		if player:
			player.invert_pitch = not player.invert_pitch
			pitch_btn.text = "FLIGHT PITCH: INVERTED" if player.invert_pitch else "FLIGHT PITCH: NORMAL"
	)
	center_box.add_child(pitch_btn)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size.y = 15
	center_box.add_child(spacer2)

	var controls_info = Label.new()
	controls_info.text = "FLIGHT CONTROLS & WEAPONS:
• SHOOTING: [Q] KEY (or Left Click / Enter)
• STEERING: LEFT / RIGHT Arrows (or A / D) to Turn & Bank
• PITCH: UP / DOWN Arrows (or W / S) to Dive / Climb
• SHIFT: Boost • CTRL: Air Brake
• F: Guided Sidewinder Missile • SPACE / RMB: ⚡ BOUNCE PARRY
• C / V: Toggle Camera • ESC: In-Game Menu"
	controls_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_info.modulate = Color(0.75, 0.88, 1.0, 0.85)
	center_box.add_child(controls_info)

func _build_pause_menu(parent: Control) -> void:
	pause_menu = Control.new()
	pause_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	parent.add_child(pause_menu)

	var dim_rect = ColorRect.new()
	dim_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_rect.color = Color(0.02, 0.05, 0.1, 0.88)
	pause_menu.add_child(dim_rect)

	var p_panel = PanelContainer.new()
	p_panel.set_anchors_preset(Control.PRESET_CENTER)
	var panel_style = _create_glass_button_style(Color(0.05, 0.09, 0.16, 0.95), Color(0.28, 0.88, 1.0, 0.9))
	p_panel.add_theme_stylebox_override("panel", panel_style)
	p_panel.custom_minimum_size = Vector2(380, 360)
	p_panel.position -= Vector2(190, 180)
	pause_menu.add_child(p_panel)

	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	p_panel.add_child(box)

	var title = Label.new()
	title.text = "MISSION PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color(0.4, 0.95, 1.0)
	box.add_child(title)

	var spacer = Control.new()
	spacer.custom_minimum_size.y = 16
	box.add_child(spacer)

	var resume_btn = Button.new()
	resume_btn.text = "▶  RESUME FLIGHT"
	resume_btn.custom_minimum_size.y = 42
	_style_button(resume_btn, Color(0.2, 0.95, 0.7))
	resume_btn.pressed.connect(_resume_game)
	box.add_child(resume_btn)

	var restart_btn = Button.new()
	restart_btn.text = "🔄  RESTART MISSION"
	restart_btn.custom_minimum_size.y = 42
	_style_button(restart_btn)
	restart_btn.pressed.connect(_restart_mission)
	box.add_child(restart_btn)

	var cam_btn = Button.new()
	cam_btn.text = "🎥  TOGGLE CAMERA VIEW"
	cam_btn.custom_minimum_size.y = 42
	_style_button(cam_btn)
	cam_btn.pressed.connect(func():
		if player:
			player.toggle_camera()
	)
	box.add_child(cam_btn)

	var exit_title_btn = Button.new()
	exit_title_btn.text = "🏠  EXIT TO MAIN MENU"
	exit_title_btn.custom_minimum_size.y = 42
	_style_button(exit_title_btn)
	exit_title_btn.pressed.connect(_show_title_screen)
	box.add_child(exit_title_btn)

	var exit_game_btn = Button.new()
	exit_game_btn.text = "❌  EXIT GAME"
	exit_game_btn.custom_minimum_size.y = 42
	_style_button(exit_game_btn, Color(1.0, 0.35, 0.35))
	exit_game_btn.pressed.connect(func():
		get_tree().quit()
	)
	box.add_child(exit_game_btn)

func _on_start_game_pressed() -> void:
	title_screen.visible = false
	pause_menu.visible = false
	hud_root.visible = true
	state = GameState.PLAYING
	get_tree().paused = false
	if player and player.has_method("respawn"):
		player.respawn()
	_start_wave(1)

func _on_corner_menu_pressed() -> void:
	if state == GameState.PLAYING:
		_pause_game()
	elif state == GameState.PAUSED:
		_resume_game()

func _pause_game() -> void:
	state = GameState.PAUSED
	pause_menu.visible = true
	get_tree().paused = true

func _resume_game() -> void:
	state = GameState.PLAYING
	pause_menu.visible = false
	get_tree().paused = false

func _restart_mission() -> void:
	for m in missiles:
		if is_instance_valid(m): m.queue_free()
	missiles.clear()
	for b in bullets:
		if is_instance_valid(b): b.queue_free()
	bullets.clear()
	for e in enemies:
		if is_instance_valid(e): e.queue_free()
	enemies.clear()

	score = 0
	bounce_streak = 1
	wave = 1
	
	if player:
		player.respawn()

	_resume_game()
	_start_wave(1)

func _show_title_screen() -> void:
	state = GameState.TITLE
	title_screen.visible = true
	pause_menu.visible = false
	hud_root.visible = false
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if state == GameState.PLAYING:
			_pause_game()
		elif state == GameState.PAUSED:
			_resume_game()

# ---------------------------------------------------------------------
# SU-57 ENEMY SPAWNING & VISIBLE COMBAT DISTANCE
# ---------------------------------------------------------------------
func _start_wave(w: int) -> void:
	wave = w
	if wave_label:
		wave_label.text = "WAVE: %d" % wave

	var enemy_count = 2 + wave
	if is_ace_difficulty:
		enemy_count += 2

	for i in range(enemy_count):
		_spawn_su57_enemy()

func _spawn_su57_enemy() -> void:
	var enemy = Node3D.new()
	
	var su57_path = _find_path("su-57_felon_aa_1__russian_air_force_warno.glb")
	if su57_path != "":
		var model = load(su57_path).instantiate()
		# 1.35x scale gives impressive 19m wingspan and 27m length for cinematic combat visibility!
		model.scale = Vector3(1.35, 1.35, 1.35)
		# Crucial: Nose points along +X in raw GLTF file. Rotate 90 deg around Y so it faces -Z forward!
		model.rotation_degrees.y = 90.0
		enemy.add_child(model)
	else:
		var box = MeshInstance3D.new()
		box.mesh = BoxMesh.new()
		box.mesh.size = Vector3(8.0, 2.4, 14.0)
		enemy.add_child(box)

	# Glowing cyan engine afterburner plumes at the exhaust nozzles (rotated Z=+8.5)
	var flame_mesh = CylinderMesh.new()
	flame_mesh.top_radius = 0.12
	flame_mesh.bottom_radius = 0.50
	flame_mesh.height = 4.2
	var e_flame_mat = StandardMaterial3D.new()
	e_flame_mat.albedo_color = Color(0.2, 0.9, 1.0, 0.95)
	e_flame_mat.emission_enabled = true
	e_flame_mat.emission = Color(0.25, 0.95, 1.0)
	e_flame_mat.emission_energy_multiplier = 6.0
	
	for offset_x in [-1.8, 1.8]:
		var flame = MeshInstance3D.new()
		flame.mesh = flame_mesh
		flame.material_override = e_flame_mat
		flame.rotation.x = PI / 2.0
		flame.position = Vector3(offset_x, 0.25, 8.5)
		enemy.add_child(flame)

	# Bright omni light illuminating the enemy jet
	var e_light = OmniLight3D.new()
	e_light.light_color = Color(0.3, 0.9, 1.0)
	e_light.light_energy = 3.5
	e_light.omni_range = 35.0
	e_light.position = Vector3(0, 1.5, 4.0)
	enemy.add_child(e_light)

	# Spawn ahead in clear visible dogfight range (320m to 460m) right in front of player windshield
	var spawn_pos = Vector3(0, 190, 100)
	var enemy_idx = enemies.size()
	if player:
		var forward = -player.global_transform.basis.z.normalized()
		var right = player.global_transform.basis.x.normalized()
		var lateral_offset = (enemy_idx - 1) * 85.0
		spawn_pos = player.global_position + forward * (320.0 + enemy_idx * 45.0) + right * lateral_offset + Vector3(0, randf_range(10.0, 35.0), 0)
		spawn_pos.y = clamp(spawn_pos.y, 90.0, 320.0)
	
	enemy.position = spawn_pos
	
	# Easy HP: 40 HP so player can shoot them down easily
	enemy.set_meta("hp", 40.0)
	enemy.set_meta("missile_cd", randf_range(8.0, 14.0))
	enemy.set_meta("speed", randf_range(65.0, 85.0))
	enemy.set_meta("orbit_dir", 1.0 if (enemy_idx % 2 == 0) else -1.0)
	
	add_child(enemy)
	enemies.append(enemy)

func _physics_process(delta: float) -> void:
	if state != GameState.PLAYING or get_tree().paused:
		return

	_update_player_world_boundary(delta)
	_update_su57_enemies(delta)
	_update_homing_missiles(delta)
	_update_bullets(delta)
	_update_debris(delta)
	_update_hud(delta)

func _update_player_world_boundary(delta: float) -> void:
	if not player:
		return

	var horiz_dist = Vector2(player.global_position.x, player.global_position.z).length()

	if horiz_dist > ARENA_RADIUS:
		var dir2d = Vector2(player.global_position.x, player.global_position.z).normalized()
		player.global_position.x = dir2d.x * ARENA_RADIUS
		player.global_position.z = dir2d.y * ARENA_RADIUS

		var inward_yaw = atan2(-dir2d.x, -dir2d.y)
		player.rotation.y = inward_yaw
		player.current_speed = player.boost_speed
		
		bounce_streak += 1
		score += 500 * bounce_streak
		spawn_shockwave(player.global_position, Color(0.2, 0.85, 1.0))

	if player.global_position.y > CEIL_LIMIT:
		player.global_position.y = CEIL_LIMIT

# ---------------------------------------------------------------------
# SU-57 DOGFIGHT AI: TACTICAL STANDOFF, NO RAMMING
# ---------------------------------------------------------------------
func _update_su57_enemies(delta: float) -> void:
	if not player:
		return

	for i in range(enemies.size() - 1, -1, -1):
		var e = enemies[i]
		if not is_instance_valid(e):
			enemies.remove_at(i)
			continue

		var pos = e.global_position
		var to_player = (player.global_position - pos)
		var dist = to_player.length()

		var separation = Vector3.ZERO
		for other in enemies:
			if other != e and is_instance_valid(other):
				var d_other = pos.distance_to(other.global_position)
				if d_other < 90.0 and d_other > 0.01:
					separation += (pos - other.global_position).normalized() * (90.0 - d_other) * 2.5

		var desired_dir = Vector3.ZERO
		var spd = e.get_meta("speed")
		var orbit_sign = e.get_meta("orbit_dir")

		if dist < 180.0:
			desired_dir = (-to_player.normalized() * 0.4 + Vector3.UP * 0.8 + separation * 0.04).normalized()
			spd = 120.0
		elif dist > 500.0:
			desired_dir = (to_player.normalized() + separation * 0.03).normalized()
		else:
			var flank_dir = to_player.cross(Vector3.UP).normalized() * orbit_sign
			desired_dir = (flank_dir * 0.75 + to_player.normalized() * 0.25 + separation * 0.03).normalized()

		if pos.y < 70.0:
			desired_dir.y += 0.9
		elif pos.y > 320.0:
			desired_dir.y -= 0.6
		desired_dir = desired_dir.normalized()

		var look_target = pos + desired_dir * 40.0
		e.look_at(look_target, Vector3.UP)
		e.global_position += desired_dir * spd * delta

		if pos.y <= 4.0:
			_destroy_su57(e, true)
			continue

		var m_cd = e.get_meta("missile_cd") - delta
		if m_cd <= 0 and dist < 550.0 and dist > 140.0:
			m_cd = randf_range(11.0, 19.0) if not is_ace_difficulty else randf_range(5.0, 9.0)
			_launch_su57_missile(e.global_position, player)
		e.set_meta("missile_cd", m_cd)

	if enemies.size() == 0 and state == GameState.PLAYING:
		wave += 1
		score += 3000 * wave
		_start_wave(wave)

func _launch_su57_missile(pos: Vector3, target_node: Node3D) -> void:
	var m = Node3D.new()
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.28
	cyl.height = 2.6
	mesh_inst.mesh = cyl
	mesh_inst.rotation.x = PI / 2.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.1)
	mat.emission_energy_multiplier = 3.5
	mesh_inst.material_override = mat
	m.add_child(mesh_inst)

	m.global_position = pos
	m.set_meta("target", target_node)
	# Slower speed for easy, comfortable reaction time!
	m.set_meta("speed", 75.0 if not is_ace_difficulty else 110.0)
	m.set_meta("parried", false)
	m.set_meta("lifetime", 5.0)

	add_child(m)
	missiles.append(m)
	play_sound(snd_missile_launch, 1.0, 0.85)

func _update_homing_missiles(delta: float) -> void:
	var closest_missile_dist = 99999.0
	var has_hostile_missile = false

	for i in range(missiles.size() - 1, -1, -1):
		var m = missiles[i]
		if not is_instance_valid(m):
			missiles.remove_at(i)
			continue

		var lt = m.get_meta("lifetime") - delta
		if lt <= 0:
			spawn_shockwave(m.global_position, Color(1.0, 0.5, 0.2), 10.0)
			m.queue_free()
			missiles.remove_at(i)
			continue
		m.set_meta("lifetime", lt)

		var parried = m.get_meta("parried")
		var spd = m.get_meta("speed")

		if not parried:
			has_hostile_missile = true
			if player:
				var dist = m.global_position.distance_to(player.global_position)
				if dist < closest_missile_dist:
					closest_missile_dist = dist

				var aim_pt = m.global_position.lerp(player.global_position, delta * 3.2)
				m.look_at(aim_pt, Vector3.UP)

				if dist < 6.5:
					player.take_damage(25.0)
					spawn_burst_effect(m.global_position, 14.0, Color(1.0, 0.35, 0.1))
					m.queue_free()
					missiles.remove_at(i)
					continue
		else:
			var nearest_e = _get_closest_enemy(m.global_position)
			if nearest_e:
				m.look_at(nearest_e.global_position, Vector3.UP)
				if m.global_position.distance_to(nearest_e.global_position) < 8.5:
					_destroy_su57(nearest_e, false)
					spawn_burst_effect(m.global_position, 22.0, Color(0.2, 1.0, 0.8))
					m.queue_free()
					missiles.remove_at(i)
					continue

		m.global_position += -m.global_transform.basis.z * spd * delta

	# UNMISSABLE CENTER WARNING BANNER WHEN MISSILE IS LOCKED ON!
	if missile_lock_panel:
		if has_hostile_missile:
			missile_lock_panel.visible = true
			alarm_cooldown -= delta
			if alarm_cooldown <= 0:
				alarm_cooldown = 0.55
				play_sound(snd_alarm, 1.0)
			if closest_missile_dist < 160.0:
				missile_lock_label.text = "🚨 INCOMING! PRESS [SPACE] NOW TO PARRY! 🚨"
				missile_lock_label.modulate = Color(1.0, 0.2, 0.2)
			else:
				missile_lock_label.text = "⚠ MISSILE LOCKED ON! GET READY TO PRESS [SPACE] ⚠"
				missile_lock_label.modulate = Color(1.0, 0.9, 0.2)
		else:
			missile_lock_panel.visible = false

	if prompt_label:
		if closest_missile_dist < 140.0 and player.bounce_ready:
			prompt_label.modulate.a = lerp(prompt_label.modulate.a, 1.0, delta * 15.0)
		else:
			prompt_label.modulate.a = lerp(prompt_label.modulate.a, 0.0, delta * 8.0)

# ---------------------------------------------------------------------
# PLAYER GUIDED SIDEWINDER MISSILE (F KEY)
# ---------------------------------------------------------------------
func spawn_player_missile(pos: Vector3, dir: Vector3 = Vector3.ZERO) -> void:
	var target = _get_closest_enemy(pos)
	play_sound(snd_missile_launch, 3.0, 1.15)

	var m = Node3D.new()
	var mesh_inst = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.22
	cyl.height = 2.4
	mesh_inst.mesh = cyl
	mesh_inst.rotation.x = PI / 2.0
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.95, 1.0)
	mat.emission_energy_multiplier = 4.0
	mesh_inst.material_override = mat
	m.add_child(mesh_inst)

	m.global_position = pos
	if dir != Vector3.ZERO:
		m.look_at(pos + dir * 20.0, Vector3.UP)
	elif player:
		m.look_at(pos - player.global_transform.basis.z * 20.0, Vector3.UP)
	m.set_meta("target", target)
	m.set_meta("speed", 250.0)
	m.set_meta("parried", true)
	m.set_meta("lifetime", 5.0)

	add_child(m)
	missiles.append(m)

# ---------------------------------------------------------------------
# BOUNCE-BACK MISSILE PARRY
# ---------------------------------------------------------------------

func execute_player_parry(center_pos: Vector3, radius: float = 75.0) -> void:
	on_player_bounce_back(center_pos, radius)
	play_sound(snd_parry, 3.5, 1.0)

func spawn_player_bullet(muzzle_pos: Vector3, shoot_dir: Vector3) -> void:
	spawn_bullet(muzzle_pos, shoot_dir * 450.0, true)
	play_sound(snd_laser, -4.0, randf_range(0.95, 1.05))

func on_player_bounce_back(center: Vector3, radius: float) -> void:
	var deflected = 0
	
	for m in missiles:
		if not is_instance_valid(m):
			continue
		if m.get_meta("parried"):
			continue

		if m.global_position.distance_to(center) <= radius:
			m.set_meta("parried", true)
			m.set_meta("speed", m.get_meta("speed") * 2.6)
			m.set_meta("lifetime", 7.0)

			var mesh_inst = m.get_child(0) as MeshInstance3D
			if mesh_inst and mesh_inst.material_override:
				mesh_inst.material_override.albedo_color = Color(0.2, 1.0, 0.8)
				mesh_inst.material_override.emission = Color(0.3, 1.0, 0.85)
				mesh_inst.material_override.emission_energy_multiplier = 6.0

			deflected += 1
			spawn_shockwave(m.global_position, Color(0.2, 1.0, 0.75), 18.0)

	if deflected > 0:
		bounce_streak += deflected
		score += 2000 * bounce_streak * deflected

func _get_closest_enemy(pos: Vector3) -> Node3D:
	var best_e: Node3D = null
	var min_d = 999999.0
	for e in enemies:
		if is_instance_valid(e):
			var d = pos.distance_to(e.global_position)
			if d < min_d:
				min_d = d
				best_e = e
	return best_e

func _destroy_su57(e: Node3D, from_crash: bool = false) -> void:
	spawn_burst_effect(e.global_position, 28.0, Color(1.0, 0.55, 0.1))
	if not from_crash:
		score += 1500 * bounce_streak
	enemies.erase(e)
	e.queue_free()

# ---------------------------------------------------------------------
# BURST ANIMATION & EXPLOSION EFFECTS
# ---------------------------------------------------------------------
func spawn_player_burst_animation(pos: Vector3) -> void:
	spawn_burst_effect(pos, 38.0, Color(1.0, 0.45, 0.08))
	flash_damage_screen(1.0)

func spawn_burst_effect(pos: Vector3, max_size: float = 24.0, main_col: Color = Color(1.0, 0.5, 0.1)) -> void:
	play_sound(snd_explosion, 4.0, randf_range(0.85, 1.15))
	var core = MeshInstance3D.new()
	var core_mesh = SphereMesh.new()
	core_mesh.radius = 2.0
	core_mesh.height = 4.0
	core.mesh = core_mesh
	
	var core_mat = StandardMaterial3D.new()
	core_mat.albedo_color = main_col
	core_mat.emission_enabled = true
	core_mat.emission = main_col
	core_mat.emission_energy_multiplier = 7.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	core.material_override = core_mat
	core.global_position = pos
	add_child(core)

	var t1 = create_tween()
	t1.tween_property(core, "scale", Vector3(max_size, max_size, max_size), 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t1.parallel().tween_property(core_mat, "albedo_color:a", 0.0, 0.55)
	t1.tween_callback(core.queue_free)

	spawn_shockwave(pos, main_col, max_size * 1.3)

	for i in range(8):
		var debris = MeshInstance3D.new()
		var d_box = BoxMesh.new()
		d_box.size = Vector3(randf_range(0.8, 1.8), randf_range(0.8, 1.8), randf_range(0.8, 1.8))
		debris.mesh = d_box
		
		var d_mat = StandardMaterial3D.new()
		d_mat.albedo_color = Color(1.0, 0.35, 0.1)
		d_mat.emission_enabled = true
		d_mat.emission = Color(1.0, 0.4, 0.1)
		d_mat.emission_energy_multiplier = 4.0
		debris.material_override = d_mat
		
		debris.global_position = pos
		var spread_vel = Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.4), randf_range(-1.0, 1.0)).normalized() * randf_range(40.0, 95.0)
		debris.set_meta("vel", spread_vel)
		debris.set_meta("life", randf_range(1.0, 1.8))
		add_child(debris)
		debris_pieces.append(debris)

func spawn_shockwave(pos: Vector3, color: Color, size: float = 16.0) -> void:
	var ring = MeshInstance3D.new()
	var s_mesh = SphereMesh.new()
	s_mesh.radius = 1.0
	s_mesh.height = 2.0
	ring.mesh = s_mesh

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.global_position = pos
	add_child(ring)

	var tween = create_tween()
	tween.tween_property(ring, "scale", Vector3(size, size, size), 0.4)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.tween_callback(ring.queue_free)

func _update_debris(delta: float) -> void:
	for i in range(debris_pieces.size() - 1, -1, -1):
		var d = debris_pieces[i]
		if not is_instance_valid(d):
			debris_pieces.remove_at(i)
			continue
		
		var life = d.get_meta("life") - delta
		if life <= 0:
			d.queue_free()
			debris_pieces.remove_at(i)
			continue
		d.set_meta("life", life)

		var vel = d.get_meta("vel") as Vector3
		vel.y -= 35.0 * delta
		d.set_meta("vel", vel)
		d.global_position += vel * delta
		d.rotate_x(delta * 4.0)
		d.rotate_y(delta * 5.0)

# ---------------------------------------------------------------------
# DAMAGE FEEDBACK
# ---------------------------------------------------------------------
func on_player_hit_feedback(current_hull: float) -> void:
	flash_damage_screen(0.5)

func flash_damage_screen(alpha: float) -> void:
	if damage_flash_rect:
		damage_flash_rect.color.a = alpha
		var t = create_tween()
		t.tween_property(damage_flash_rect, "color:a", 0.0, 0.45)

# ---------------------------------------------------------------------
# BULLETS & WEAPONS
# ---------------------------------------------------------------------
func spawn_bullet(pos: Vector3, vel: Vector3, is_player: bool) -> void:
	var b = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.16
	cyl.bottom_radius = 0.16
	cyl.height = 4.2
	b.mesh = cyl
	b.rotation.x = PI / 2.0

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.98, 1.0)
	mat.emission_energy_multiplier = 4.5
	b.material_override = mat

	b.global_position = pos
	b.set_meta("velocity", vel)
	b.set_meta("lifetime", 3.2)
	add_child(b)
	bullets.append(b)

func _update_bullets(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b = bullets[i]
		if not is_instance_valid(b):
			bullets.remove_at(i)
			continue

		var lt = b.get_meta("lifetime") - delta
		if lt <= 0:
			b.queue_free()
			bullets.remove_at(i)
			continue
		b.set_meta("lifetime", lt)

		var vel = b.get_meta("velocity") as Vector3
		b.global_position += vel * delta

		for e in enemies:
			if is_instance_valid(e) and b.global_position.distance_to(e.global_position) < 8.0:
				var hp = e.get_meta("hp") - 30.0
				e.set_meta("hp", hp)
				if hp <= 0:
					_destroy_su57(e, false)
				b.queue_free()
				bullets.remove_at(i)
				break

# ---------------------------------------------------------------------
# HUD UPDATE & HIGH-VISIBILITY TARGET BRACKETS
# ---------------------------------------------------------------------
func _update_hud(delta: float) -> void:
	if not player or not hud_root.visible:
		return

	score_label.text = "SCORE: %07d" % score
	streak_label.text = "BOUNCE STREAK: x%d" % bounce_streak
	enemies_label.text = "SU-57 HOSTILES: %d" % enemies.size()

	var kmh = int(player.current_speed * 3.6)
	var alt = int(player.global_position.y)
	speed_label.text = "AIRSPEED: %d KM/H\nALTITUDE: %d M" % [kmh, alt]

	hull_bar.value = player.hull
	boost_bar.value = player.boost_energy

	if player.bounce_ready:
		bounce_bar.value = 1.0
	else:
		bounce_bar.value = 1.0 - (player.bounce_timer / player.bounce_cooldown)

	_update_target_brackets()

func _update_target_brackets() -> void:
	var cam = get_viewport().get_camera_3d()
	if not cam:
		return

	while radar_target_brackets.get_child_count() < enemies.size():
		var lbl = Label.new()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.modulate = Color(1.0, 0.85, 0.2, 0.95)
		radar_target_brackets.add_child(lbl)

	for i in range(radar_target_brackets.get_child_count()):
		var lbl = radar_target_brackets.get_child(i) as Label
		if i < enemies.size() and is_instance_valid(enemies[i]):
			var e = enemies[i]
			var dist = int(player.global_position.distance_to(e.global_position))
			
			if not cam.is_position_behind(e.global_position):
				var screen_pos = cam.unproject_position(e.global_position)
				lbl.visible = true
				lbl.position = screen_pos - Vector2(60, 24)
				lbl.text = "◤  🔶  ◥\nSU-57 [%dm]\n◣      ◢" % dist
				if dist < 350:
					lbl.modulate = Color(1.0, 0.25, 0.25, 1.0)
				else:
					lbl.modulate = Color(1.0, 0.85, 0.2, 0.95)
			else:
				lbl.visible = false
		else:
			lbl.visible = false
