extends Node3D
## Icarus Swing — builds the course out of placeholder shapes, the HUD,
## checkpoints, rings, the goal and the run timer.

const PlayerScript := preload("res://scripts/player.gd")

const DEATH_Y := -32.0
const SAVE_PATH := "user://best.save"
const SETTINGS_PATH := "user://settings.save"
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
var crosshair
var dist_label: Label
var charge_label: Label
var timer_label: Label
var info_label: Label
var toast: Label
var toast_t := 0.0
var overlay: Control
var win_panel: PanelContainer
var win_label: Label
var preset_buttons: Array[Button] = []
var preset_desc: Label


func _ready() -> void:
	_setup_input()
	_build_environment()
	_build_test_area()   # swap for _build_level() to get the lava course back
	player = PlayerScript.new()
	add_child(player)
	player.reset_to(START_POS, 0.0)
	var saved := 2   # Bungee is the default
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			saved = f.get_8()
	player.apply_preset(saved)
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
		"reel_in": [KEY_E],
		"dash": [KEY_SHIFT],
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
	body.collision_layer = 1 | 2   # layer 1 = solid, layer 2 = grappleable
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


# ---------------------------------------------------------------- test area
# Flat ground with grapple targets scattered in the air, for tuning the feel.
func _build_test_area() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337   # same layout every time
	var ground := box(Vector3(0, -0.5, 0), Vector3(500, 1, 500), Color(0.45, 0.55, 0.42))
	ground.collision_layer = 1   # solid but not grappleable, so the reticle never snaps to the floor
	# faint grid stripes so you can judge speed
	for i in range(-12, 13):
		box(Vector3(i * 20, 0.01, 0), Vector3(0.3, 0.02, 500), Color(0.38, 0.47, 0.36)).collision_layer = 1
		box(Vector3(0, 0.01, i * 20), Vector3(500, 0.02, 0.3), Color(0.38, 0.47, 0.36)).collision_layer = 1
	var colors := [Color(0.3, 0.6, 0.7), Color(0.55, 0.45, 0.75), Color(0.9, 0.75, 0.35), Color(0.85, 0.4, 0.4)]
	for i in 70:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(12, 200)
		var pos := Vector3(cos(ang) * dist, rng.randf_range(8, 32), sin(ang) * dist)
		var c: Color = colors[i % colors.size()]
		match i % 3:
			0: box(pos, Vector3.ONE * rng.randf_range(2, 5), c)
			1: ball(pos, rng.randf_range(1.5, 3.5), c)
			2:
				var b := box(pos, Vector3(rng.randf_range(10, 24), 1.2, 1.2), c)
				b.rotation.y = rng.randf() * PI


# ---------------------------------------------------------------- the course (lava run, currently off)
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

	crosshair = preload("res://scripts/reticle.gd").new()
	root.add_child(crosshair)

	dist_label = _label("", 14)
	dist_label.set_anchors_preset(Control.PRESET_CENTER)
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.size = Vector2(120, 20)
	dist_label.position = Vector2(-60, 54)
	root.add_child(dist_label)

	charge_label = _label("", 22)
	charge_label.set_anchors_preset(Control.PRESET_CENTER)
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_label.size = Vector2(240, 30)
	charge_label.position = Vector2(-120, 74)
	root.add_child(charge_label)

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
		"Mouse — look        Hold LEFT CLICK — grapple (3 in the air, refill on landing)\n" +
		"Release LEFT CLICK — let go      Space — jump\n" +
		"WASD — walk, air-steer, push while hooked\n" +
		"Space / Right click / E / wheel up — reel in      Shift — dash\n" +
		"Q / Ctrl / wheel down — reel out\n" +
		"1 / 2 / 3 — physics preset      R — restart      Esc — pause", 20)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)

	# Options: physics presets
	var opt_title := _label("\nPHYSICS PRESET", 22)
	opt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opt_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	col.add_child(opt_title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	for i in player.PRESETS.size():
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, player.PRESETS[i].name]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 44)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(set_preset.bind(i))
		row.add_child(b)
		preset_buttons.append(b)
	preset_desc = _label("", 18)
	preset_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(preset_desc)
	var go := _label("\nCLICK ANYWHERE TO PLAY", 22)
	go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(go)
	_refresh_preset_ui()

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


func set_preset(i: int) -> void:
	player.apply_preset(i)
	_refresh_preset_ui()
	_toast("Physics: %d. %s" % [i + 1, player.PRESETS[i].name])
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_8(i)


func _refresh_preset_ui() -> void:
	for i in preset_buttons.size():
		preset_buttons[i].set_pressed_no_signal(i == player.preset_index)
	preset_desc.text = player.PRESETS[player.preset_index].desc


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
		set_preset(event.physical_keycode - KEY_1)
	elif event.is_action_pressed("restart"):
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
	info_label.text = "Physics: %s   Speed %d%s%s" % [
		player.PRESETS[player.preset_index].name, roundi(spd * 3.6), ("   Rings %d/%d" % [rings_got, rings_total]) if rings_total > 0 else "",
		("   Best " + _fmt(best_time)) if best_time > 0 else ""]

	var pips := ""
	for i in player.AIR_GRAPPLES:
		pips += ("● " if i < player.air_grapples else "○ ")
	charge_label.text = pips + ("  DASH" if player.dash_cd == 0.0 else "")
	charge_label.modulate = Color(1, 1, 1, 0.85) if player.air_grapples > 0 else Color(1, 0.4, 0.3, 0.85)

	var out_of_grapples: bool = player.air_grapples <= 0 and not player.is_on_floor()
	if player.attached:
		crosshair.set_color(Color(1.0, 0.65, 0.2, 0.5))
		dist_label.text = "rope %dm" % roundi(player.rope_len)
	elif player.aim_valid and not out_of_grapples:
		crosshair.set_color(Color(0.4, 1.0, 0.5, 0.5))
		dist_label.text = "%dm" % roundi(player.aim_distance)
	else:
		crosshair.set_color(Color(1, 1, 1, 0.5))
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
