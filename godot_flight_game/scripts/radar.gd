extends Control

# =====================================================================
# CIRCULAR TACTICAL RADAR HUD
# Features:
# - Concentric military range rings & crosshair
# - Continuous rotating 360° radar sweep scanner
# - Center player aircraft chevron
# - GLOWING RED DOTS representing Su-57 hostile fighter jets
# - ORANGE/YELLOW pulsing dots for homing missiles
# - Clear range readout (1.6 KM)
# =====================================================================

var player_ref: CharacterBody3D
var enemies_ref: Array = []
var missiles_ref: Array = []

var radar_radius: float = 72.0
var max_range: float = 1600.0
var sweep_angle: float = 0.0

func _ready() -> void:
	custom_minimum_size = Vector2(radar_radius * 2 + 20, radar_radius * 2 + 20)
	size = custom_minimum_size

func _process(delta: float) -> void:
	sweep_angle = fmod(sweep_angle + delta * 3.5, TAU)
	queue_redraw()

func _draw() -> void:
	var center = size * 0.5

	# 1. Dark semi-transparent radar glass circle
	draw_circle(center, radar_radius, Color(0.04, 0.08, 0.16, 0.78))

	# 2. Outer border ring with subtle cyan glow
	draw_arc(center, radar_radius, 0, TAU, 64, Color(0.25, 0.85, 1.0, 0.90), 2.5)
	draw_arc(center, radar_radius + 2.0, 0, TAU, 48, Color(0.15, 0.50, 0.8, 0.35), 1.0)

	# 3. Inner concentric distance rings (500m and 1000m)
	draw_arc(center, radar_radius * 0.33, 0, TAU, 32, Color(0.2, 0.65, 0.85, 0.35), 1.0)
	draw_arc(center, radar_radius * 0.66, 0, TAU, 48, Color(0.2, 0.65, 0.85, 0.40), 1.0)

	# 4. Subtle Crosshairs
	draw_line(center - Vector2(radar_radius, 0), center + Vector2(radar_radius, 0), Color(0.2, 0.65, 0.85, 0.3), 1.0)
	draw_line(center - Vector2(0, radar_radius), center + Vector2(0, radar_radius), Color(0.2, 0.65, 0.85, 0.3), 1.0)

	# 5. Rotating Radar Scanner Sweep Beam
	var sweep_vec = Vector2(cos(sweep_angle), sin(sweep_angle)) * radar_radius
	draw_line(center, center + sweep_vec, Color(0.3, 0.95, 1.0, 0.75), 2.0)

	# 6. Center Player Icon (White Jet Silhouette pointing UP)
	var p_points = PackedVector2Array([
		center + Vector2(0, -7),
		center + Vector2(-5, 5),
		center + Vector2(0, 2),
		center + Vector2(5, 5)
	])
	draw_colored_polygon(p_points, Color(1.0, 1.0, 1.0, 0.95))

	if not is_instance_valid(player_ref):
		return

	var p_pos = player_ref.global_position
	var p_yaw = player_ref.rotation.y

	# 7. GLOWING RED DOTS for Su-57 Enemy Fighters
	for e in enemies_ref:
		if is_instance_valid(e):
			var rel = e.global_position - p_pos
			# Rotate offset by negative player yaw so forward is UP
			var rx = rel.x * cos(-p_yaw) - rel.z * sin(-p_yaw)
			var rz = rel.x * sin(-p_yaw) + rel.z * cos(-p_yaw)
			
			var dist = sqrt(rx * rx + rz * rz)
			if dist < 0.01:
				continue
				
			var norm_dist = min(dist / max_range, 1.0) * (radar_radius - 8.0)
			var blip_pos = center + Vector2(rx, rz).normalized() * norm_dist
			
			# Outer pulsing red halo
			draw_circle(blip_pos, 7.0, Color(1.0, 0.1, 0.1, 0.35))
			# Bright solid red dot
			draw_circle(blip_pos, 4.2, Color(1.0, 0.15, 0.15, 1.0))
			# White core glint
			draw_circle(blip_pos, 1.8, Color(1.0, 0.85, 0.85, 0.9))

	# 8. ORANGE / YELLOW Dots for Inbound Missiles
	for m in missiles_ref:
		if is_instance_valid(m):
			var rel_m = m.global_position - p_pos
			var mx = rel_m.x * cos(-p_yaw) - rel_m.z * sin(-p_yaw)
			var mz = rel_m.x * sin(-p_yaw) + rel_m.z * cos(-p_yaw)
			
			var m_dist = sqrt(mx * mx + mz * mz)
			if m_dist < 0.01:
				continue
				
			var m_norm = min(m_dist / max_range, 1.0) * (radar_radius - 8.0)
			var m_blip = center + Vector2(mx, mz).normalized() * m_norm
			
			var parried = m.has_meta("parried") and m.get_meta("parried")
			var m_col = Color(0.2, 1.0, 0.8) if parried else Color(1.0, 0.6, 0.1)
			draw_circle(m_blip, 5.5, Color(m_col.r, m_col.g, m_col.b, 0.4))
			draw_circle(m_blip, 3.5, m_col)
