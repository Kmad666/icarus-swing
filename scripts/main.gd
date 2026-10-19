extends Node3D
## Icarus Swing — builds the course out of placeholder shapes, the HUD,
## checkpoints, rings, the goal and the run timer.

const PlayerScript := preload("res://scripts/player.gd")

const DEATH_Y := -32.0
const SAVE_PATH := "user://best.save"
const START_POS := Vector3(0, 1.5, 4)

var player: CharacterBody3D
var mats := {}

var respawn_pos := START_POS
var run_time := 0.0
var running := false
var finished := false
var best_time := -1.0
var rings_total := 0
var rings_got := 0

# HUD
var crosshair: Label
var dist_label: Label
var timer_label: Label
var info_label: Label
var toast: Label
var toast_t := 0.0
var overlay: Control
var win_panel: PanelContainer
var win_label: Label


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_level()
	player = PlayerScript.new()
	add_child(player)
	player.reset_to(START_POS, 0.0)
	player.grappled.connect(_on_grappled)
	_build_hud()
	_load_best()


# ---------------------------------------------------------------- input map
func _setup_input() -> void:
	var binds := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE],
		"reel_in": [KEY_SHIFT, KEY_E],
		"reel_out": [KEY_CTRL, KEY_Q],
		"restart": [KEY_R],
	}
	for action in binds:
		if InputMap.has_action(action):
			continue   # already set up (scene was reloaded)
		InputMap.add_action(action)
		for k in binds[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		if action == "reel_in":
			var rmb := InputEventMouseButton.new()
			rmb.button_index = MOUSE_BUTTON_RIGHT
			InputMap.action_add_event(action, rmb)


# ---------------------------------------------------------------- world
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.28, 0.42, 0.75)
	sm.sky_horizon_color = Color(0.95, 0.7, 0.55)
	sm.ground_horizon_color = Color(0.95, 0.5, 0.3)
	sm.ground_bottom_color = Color(0.35, 0.08, 0.05)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.65, 0.5)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.92, 0.82)
	sun.shadow_enabled = false   # keep it light on integrated graphics
	add_child(sun)

	# Lava sea far below (visual only — falling below DEATH_Y respawns you)
	var lava := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2000, 2000)
	lava.mesh = pm
	lava.position = Vector3(0, -40, -200)
	lava.material_override = _mat(Color(1.0, 0.32, 0.08), true)
	add_child(lava)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var key := str(c) + str(glow)
	if mats.has(key):
		return mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats[key] = m
	return m


func _solid(shape: Shape3D, mesh: Mesh, pos: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	body.add_child(mi)
	add_child(body)
	return body


func box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var s := BoxShape3D.new()
	s.size = size
	var m := BoxMesh.new()
	m.size = size
	return _solid(s, m, pos, color)


func pillar(x: float, z: float, top_y: float, radius: float, color: Color) -> StaticBody3D:
	var h := top_y + 45.0
	var s := CylinderShape3D.new()
	s.radius = radius
	s.height = h
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = h
	m.radial_segments = 12
	return _solid(s, m, Vector3(x, top_y - h * 0.5, z), color)


func ball(pos: Vector3, radius: float, color: Color) -> StaticBody3D:
	var s := SphereShape3D.new()
	s.radius = radius
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2
	m.radial_segments = 16
	m.rings = 8
	return _solid(s, m, pos, color)


func _area(pos: Vector3, size: Vector3, cb: Callable) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = 0
	a.collision_mask = 8   # player layer
	a.monitorable = false
	a.position = pos
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	a.add_child(cs)
	a.body_entered.connect(cb)
	add_child(a)
	return a


func checkpoint(platform_center: Vector3, size: Vector3) -> void:
	box(platform_center, size, Color(0.35, 0.75, 0.55))
	var top := platform_center + Vector3(0, size.y * 0.5, 0)
	var spawn := top + Vector3(0, 1.5, 0)
	var flag := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.15
	fm.bottom_radius = 0.15
	fm.height = 5
	flag.mesh = fm
	flag.material_override = _mat(Color(0.4, 1.0, 0.6), true)
	flag.position = top + Vector3(size.x * 0.4, 2.5, 0)
	add_child(flag)
	_area(top + Vector3(0, 2, 0), Vector3(size.x, 4, size.z), func(b):
		if b == player and respawn_pos != spawn:
			respawn_pos = spawn
			_toast("Checkpoint!"))


func ring(pos: Vector3, facing_x := false) -> void:
	rings_total += 1
	var holder := Node3D.new()
	holder.position = pos
	if not facing_x:
		holder.rotation_degrees.x = 90
	else:
		holder.rotation_degrees.z = 90
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.6
	tm.outer_radius = 3.0
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = _mat(Color(0.3, 0.9, 1.0), true)
	holder.add_child(mi)
	add_child(holder)
	var taken := [false]
	_area(pos, Vector3(5.5, 5.5, 5.5), func(b):
		if b == player and not taken[0]:
			taken[0] = true
			rings_got += 1
			holder.visible = false
			_toast("Ring %d/%d" % [rings_got, rings_total]))


# ---------------------------------------------------------------- the course
# Forward is -Z. Every solid surface is grappleable.
func _build_level() -> void:
	var stone := Color(0.55, 0.52, 0.5)
	var teal := Color(0.3, 0.6, 0.7)
	var violet := Color(0.55, 0.45, 0.75)
	var gold := Color(0.9, 0.75, 0.35)

	# Start platform
	box(Vector3(0, -0.5, 0), Vector3(14, 1, 14), Color(0.7, 0.68, 0.62))
	pillar(0, 0, -1, 5, stone)

	# Section 1 — Pillar Slalom: alternating T-columns whose arms hang over the path.
	# (Grab the arms, not the column faces — a rope on a wall just swings you into it.)
	for i in 6:
		var side := 1.0 if i % 2 == 0 else -1.0
		var z := -28.0 - i * 20.0
		var top := 22.0 + i
		pillar(side * 13, z, top, 2.2, teal)
		box(Vector3(side * 6, top - 0.75, z), Vector3(16, 1.5, 2.5), teal)
	ring(Vector3(0, 8, -58))
	ring(Vector3(0, 15, -98))

	# Checkpoint 1
	checkpoint(Vector3(0, -0.5, -152), Vector3(12, 1, 12))
	pillar(0, -152, -1, 4, stone)

	# Section 2 — Beam Run: overhead bars to swing from, cubes as backups
	var beam_z := [-178, -203, -228, -253]
	for i in beam_z.size():
		var y := 24.0 if i % 2 == 0 else 28.0
		box(Vector3(0, y, beam_z[i]), Vector3(30, 1.5, 1.5), violet)
		box(Vector3(18 if i % 2 == 0 else -18, 16, beam_z[i] + 6), Vector3(4, 4, 4), violet)
	ring(Vector3(0, -2, -191))
	ring(Vector3(0, 4, -241))

	# Checkpoint 2 (raised)
	checkpoint(Vector3(0, 4.5, -282), Vector3(12, 1, 12))
	pillar(0, -282, 4, 4, stone)

	# Section 3 — Moons: big floating spheres
	ball(Vector3(-6, 28, -312), 4.0, gold)
	ball(Vector3(7, 30, -342), 4.0, gold)
	ball(Vector3(-4, 32, -372), 4.0, gold)
	ring(Vector3(0, -12, -327))
	ring(Vector3(-1, 3, -357))

	# Summit tower + halo block to reel yourself up with
	var tower_top := 20.0
	box(Vector3(0, tower_top - 30, -410), Vector3(14, 60, 14), stone)
	box(Vector3(0, 44, -410), Vector3(4, 2, 4), gold)

	# Goal beacon
	var beacon := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.8
	bm.bottom_radius = 1.6
	bm.height = 14
	beacon.mesh = bm
	beacon.material_override = _mat(Color(1.0, 0.85, 0.3), true)
	beacon.position = Vector3(0, tower_top + 7, -410)
	add_child(beacon)
	_area(Vector3(0, tower_top + 3, -410), Vector3(14, 6, 14), _on_goal)

	# Scenery for scale (far off, also grappleable but out of the way)
	for i in 10:
		var side := -1.0 if i % 2 == 0 else 1.0
		pillar(side * (70 + (i * 13) % 40), -40 - i * 45, 10 + (i * 17) % 40, 6 + i % 3 * 2, Color(0.4, 0.38, 0.42))


# ---------------------------------------------------------------- HUD
func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	return l


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	crosshair = _label("+", 34)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.size = Vector2(60, 60)
	crosshair.position = -crosshair.size * 0.5
	root.add_child(crosshair)

	dist_label = _label("", 14)
	dist_label.set_anchors_preset(Control.PRESET_CENTER)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.size = Vector2(120, 20)
	dist_label.position = Vector2(-60, 24)
	root.add_child(dist_label)

	timer_label = _label("0:00.00", 30)
	timer_label.position = Vector2(20, 14)
	root.add_child(timer_label)

	info_label = _label("", 16)
	info_label.position = Vector2(20, 56)
	root.add_child(info_label)

	toast = _label("", 36)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.size = Vector2(600, 50)
	toast.position = Vector2(-300, 90)
	root.add_child(toast)

	# Click-to-play overlay
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.03, 0.04, 0.08, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_overlay_input)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	var title := _label("ICARUS SWING", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	col.add_child(title)
	var help := _label(
		"Reach the golden beacon. Don't touch the lava.\n\n" +
		"Mouse — look        Hold LEFT CLICK — grapple & swing\n" +
		"Release — let go      Space — jump / hop off rope\n" +
		"WASD — walk, air-steer, pump your swing\n" +
		"Right click / Shift / E / wheel up — reel in\n" +
		"Q / Ctrl / wheel down — reel out\n" +
		"R — restart run      Esc — pause\n\n" +
		"CLICK TO PLAY", 20)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)

	# Win panel
	win_panel = PanelContainer.new()
	win_panel.set_anchors_preset(Control.PRESET_CENTER)
	win_panel.visible = false
	win_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(win_panel)
	win_label = _label("", 30)
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_panel.add_child(win_label)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		restart_run()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _toast(t: String) -> void:
	toast.text = t
	toast_t = 1.8


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]


func _process(dt: float) -> void:
	overlay.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not finished

	if running and not finished:
		run_time += dt
	timer_label.text = _fmt(run_time)
	var spd := player.velocity.length()
	info_label.text = "Speed %d   Rings %d/%d%s" % [
		roundi(spd * 3.6), rings_got, rings_total,
		("   Best " + _fmt(best_time)) if best_time > 0 else ""]

	if player.attached:
		crosshair.modulate = Color(1.0, 0.65, 0.2)
		dist_label.text = "rope %dm" % roundi(player.rope_len)
	elif player.aim_valid:
		crosshair.modulate = Color(0.4, 1.0, 0.5)
		dist_label.text = "%dm" % roundi(player.aim_distance)
	else:
		crosshair.modulate = Color(1, 1, 1, 0.45)
		dist_label.text = ""

	if toast_t > 0.0:
		toast_t -= dt
		toast.modulate.a = clamp(toast_t, 0.0, 1.0)

	if player.global_position.y < DEATH_Y:
		player.reset_to(respawn_pos, player.rotation.y)
		_toast("Splash! Back to checkpoint")


func _on_grappled() -> void:
	if not running and not finished:
		running = true


func _on_goal(b: Node) -> void:
	if b != player or finished:
		return
	finished = true
	running = false
	var record := best_time < 0.0 or run_time < best_time
	if record:
		best_time = run_time
		_save_best()
	player.release()
	player.controls_enabled = false
	player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	win_label.text = "  SUMMIT REACHED!  \n\nTime %s%s\nRings %d/%d\n\nPress R to run again" % [
		_fmt(run_time), "  — NEW BEST!" if record else "   (best %s)" % _fmt(best_time),
		rings_got, rings_total]
	win_panel.visible = true
	win_panel.position = -win_panel.size * 0.5


func restart_run() -> void:
	get_tree().reload_current_scene()


func _load_best() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f:
			best_time = f.get_float()


func _save_best() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_float(best_time)
