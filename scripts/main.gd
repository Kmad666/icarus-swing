extends Node3D
## Icarus Swing — PS1-style night city test district.
##
## The 3D world renders into a low-resolution SubViewport (240 lines tall),
## which is scaled up with nearest-neighbour filtering and run through a
## 15-bit colour dither pass. The HUD draws on top at full resolution.

const PlayerScript := preload("res://scripts/player.gd")
const LanternScript := preload("res://scripts/lantern.gd")

const RENDER_LINES := 240          # vertical resolution of the 3D image
const DEATH_Y := -20.0
const SETTINGS_PATH := "user://settings.save"
const START_POS := Vector3(0, 1.2, 14)

var world: Node3D                  # everything 3D lives under here (inside the SubViewport)
var player: CharacterBody3D
var lanterns: Array = []

# HUD
var crosshair
var dist_label: Label
var charge_label: Label
var info_label: Label
var toast: Label
var toast_t := 0.0
var overlay: Control
var preset_buttons: Array[Button] = []
var preset_desc: Label


func _ready() -> void:
	_setup_input()
	_build_viewport()
	_build_environment()
	_build_district()
	player = PlayerScript.new()
	world.add_child(player)
	player.reset_to(START_POS, 0.0)
	player.lanterns = lanterns
	var saved := 2   # Bungee is the default
	if FileAccess.file_exists(SETTINGS_PATH):
		var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if f:
			saved = f.get_8()
	player.apply_preset(saved)
	_build_hud()


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


# ---------------------------------------------------------------- PS1 render target
func _build_viewport() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1   # under the HUD
	add_child(layer)
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.stretch_shrink = int(720 / RENDER_LINES)   # HUD canvas is 720 tall -> 240-line render
	svc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var post := ShaderMaterial.new()
	post.shader = preload("res://shaders/ps1_post.gdshader")
	svc.material = post
	layer.add_child(svc)
	var svp := SubViewport.new()
	svp.msaa_3d = Viewport.MSAA_DISABLED
	svp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	svp.audio_listener_enable_3d = true
	svc.add_child(svp)
	world = Node3D.new()
	world.name = "World"
	svp.add_child(world)


# ---------------------------------------------------------------- night
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.02, 0.06)
	sm.sky_horizon_color = Color(0.07, 0.08, 0.16)
	sm.ground_horizon_color = Color(0.07, 0.08, 0.16)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.02)
	sm.sun_angle_max = 0.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.55)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.06, 0.12)
	env.fog_density = 0.022
	env.fog_sky_affect = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-35, 150, 0)
	moon.light_energy = 0.35
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.shadow_enabled = false
	world.add_child(moon)

	# The moon itself: a pale low-poly disc far up the sky
	var disc := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 14
	dm.height = 28
	dm.radial_segments = 10
	dm.rings = 5
	disc.mesh = dm
	disc.material_override = PS1.unlit(Color(0.85, 0.88, 0.95), true)
	disc.position = moon.global_basis.z * 420.0
	world.add_child(disc)


# ---------------------------------------------------------------- building blocks
func _subdiv(n: float) -> int:
	return clampi(int(n / 2.0), 0, 12)   # extra vertices so lantern light shows (vertex lighting)


## Static decoration is batched: every box with the same material in the same
## 24 m cell is merged into one mesh, so a whole street is a few dozen draw calls.
var _batches := {}

func deco(size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> void:
	var m := BoxMesh.new()
	m.size = size
	m.subdivide_width = _subdiv(size.x)
	m.subdivide_height = _subdiv(size.y)
	m.subdivide_depth = _subdiv(size.z)
	_batch(m, Transform3D(Basis.from_euler(rot), pos), mat)


func _batch(mesh: Mesh, xform: Transform3D, mat: Material) -> void:
	var cell := Vector2i(floori(xform.origin.x / 24.0), floori(xform.origin.z / 24.0))
	var key := "%d_%s" % [mat.get_instance_id(), cell]
	if not _batches.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = [st, mat]
	_batches[key][0].append_from(mesh, 0, xform)


func _flush_batches() -> void:
	for key in _batches:
		var mi := MeshInstance3D.new()
		mi.mesh = _batches[key][0].commit()
		mi.material_override = _batches[key][1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)
	_batches.clear()


func solid(size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	world.add_child(body)
	deco(size, pos, mat)
	return body


## Thin bar from a to b (wires, braces).
func rod(a: Vector3, b: Vector3, thick: float, mat: Material) -> void:
	var m := BoxMesh.new()
	m.size = Vector3(thick, 1, thick)
	var d := b - a
	var y := d.normalized()
	var helper := Vector3.UP if abs(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := y.cross(helper).normalized()
	var z := x.cross(y)
	_batch(m, Transform3D(Basis(x, y * d.length(), z), (a + b) * 0.5), mat)


func lantern(hook_pos: Vector3, chain := 0.6) -> Node3D:
	var l := LanternScript.new(chain)
	l.position = hook_pos
	world.add_child(l)
	lanterns.append(l)
	return l


## Half-timbered house. `face` = +1 if the street side is +X, -1 if -X.
func house(cx: float, cz: float, w: float, d: float, h: float, face: int, rng: RandomNumberGenerator) -> void:
	var plaster := PS1.lit(Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.25)), "plaster", 3.0)
	var stone := PS1.lit(Color(1, 1, 1), "stone", 2.0)
	var timber := PS1.lit(Color(0.75, 0.75, 0.75), "wood", 2.0)
	var roof := PS1.lit(Color(1, 1, 1).darkened(rng.randf_range(0.0, 0.3)), "roof", 2.0)

	solid(Vector3(w, h, d), Vector3(cx, h * 0.5, cz), plaster)
	deco(Vector3(w + 0.1, 1.4, d + 0.1), Vector3(cx, 0.7, cz), stone)             # stone footing
	# Timber frame: corner posts, floor bands, cross braces on the street face
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			deco(Vector3(0.3, h, 0.3), Vector3(cx + sx * w * 0.5, h * 0.5, cz + sz * d * 0.5), timber)
	var floors := int(h / 3.5)
	for f in range(1, floors + 1):
		deco(Vector3(w + 0.12, 0.25, d + 0.12), Vector3(cx, f * 3.5 - 0.6, cz), timber)
	var fx := cx + face * (w * 0.5 + 0.06)
	for zz in [cz - d * 0.25, cz + d * 0.25]:
		deco(Vector3(0.12, 3.2, 0.22), Vector3(fx, 4.3, zz), timber, Vector3(0.55 if zz < cz else -0.55, 0, 0))

	# Door and a few windows on the street face; some windows glow
	deco(Vector3(0.1, 2.2, 1.3), Vector3(fx, 1.1, cz), PS1.lit(Color(0.5, 0.5, 0.5), "wood", 1.0))
	for f in range(1, floors + 1):
		for zz in [cz - d * 0.3, cz + d * 0.3]:
			var lit_window := rng.randf() < 0.45
			var wm: Material = PS1.unlit(Color(0.85, 0.55, 0.2)) if lit_window else PS1.lit(Color(0.05, 0.05, 0.07))
			deco(Vector3(0.1, 1.2, 0.9), Vector3(fx, f * 3.5 + 1.0, zz), wm)
			deco(Vector3(0.14, 0.12, 1.1), Vector3(fx, f * 3.5 + 0.35, zz), timber)   # sill

	# Gable roof, ridge running along Z
	var rh := w * 0.45
	var rb := StaticBody3D.new()
	rb.collision_layer = 1
	rb.collision_mask = 0
	rb.position = Vector3(cx, h + rh * 0.5, cz)
	world.add_child(rb)
	var pm := PrismMesh.new()
	pm.size = Vector3(w + 1.0, rh, d + 1.0)
	pm.subdivide_width = 4
	pm.subdivide_height = 2
	pm.subdivide_depth = _subdiv(d)
	_batch(pm, Transform3D(Basis(), rb.position), roof)
	var rcs := CollisionShape3D.new()
	rcs.shape = pm.create_convex_shape()
	rb.add_child(rcs)
	# Chimney
	if rng.randf() < 0.6:
		solid(Vector3(0.9, 2.2, 0.9), Vector3(cx - face * w * 0.2, h + rh * 0.6, cz + d * 0.25), stone)

	# Wall lantern on an iron bracket, out over the street
	if rng.randf() < 0.7:
		var iron := PS1.lit(Color(0.13, 0.12, 0.13), "metal", 0.5)
		var ly := h - 1.2
		var root := Vector3(fx, ly, cz + rng.randf_range(-d * 0.2, d * 0.2))
		var tip := root + Vector3(face * 1.6, 0, 0)
		rod(root, tip, 0.1, iron)
		rod(root + Vector3(0, -0.9, 0), tip - Vector3(face * 0.3, 0, 0), 0.07, iron)   # brace
		lantern(tip - Vector3(0, 0.05, 0), 0.5)


## Iron street lamp post with a lantern on its arm.
func lamp_post(x: float, z: float, height: float, toward: float) -> void:
	var iron := PS1.lit(Color(0.13, 0.12, 0.13), "metal", 0.5)
	solid(Vector3(0.22, height, 0.22), Vector3(x, height * 0.5, z), iron)
	deco(Vector3(0.45, 0.4, 0.45), Vector3(x, 0.2, z), iron)
	var tip := Vector3(x + toward * 1.4, height - 0.1, z)
	rod(Vector3(x, height - 0.1, z), tip, 0.1, iron)
	rod(Vector3(x, height - 0.8, z), tip - Vector3(toward * 0.3, 0, 0), 0.06, iron)
	lantern(tip - Vector3(0, 0.05, 0), 0.4)


# ---------------------------------------------------------------- the test district
# A cobbled street running toward -Z, lined with houses, lanterns on posts,
# on wall brackets, and strung across the street between rooftops.
func _build_district() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Cobblestone ground in chunks (each chunk gets its own nearby lights)
	var cobble := PS1.lit(Color(1, 1, 1), "cobble", 2.5)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var gcs := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(400, 1, 400)
	gcs.shape = gbox
	gcs.position = Vector3(0, -0.5, -50)
	ground.add_child(gcs)
	world.add_child(ground)
	for gx in range(-5, 5):
		for gz in range(-10, 4):
			var pm := PlaneMesh.new()
			pm.size = Vector2(16, 16)
			pm.subdivide_width = 7
			pm.subdivide_depth = 7
			_batch(pm, Transform3D(Basis(), Vector3(gx * 16 + 8, 0, gz * 16 + 8)), cobble)

	# Two rows of houses along the street (x = ±14), with alleys between them
	var heights := {}
	for side in [-1, 1]:
		var z := 22.0
		while z > -112.0:
			var d := rng.randf_range(9.0, 13.0)
			var w := rng.randf_range(10.0, 13.0)
			var h := rng.randf_range(7.0, 15.0)
			var cz := z - d * 0.5
			if abs(cz + 44.0) > 9.0:   # leave a cross street around z = -44
				house(side * (8.0 + w * 0.5), cz, w, d, h, -side, rng)
				heights[Vector2i(side, int(cz))] = Vector3(side * 8.0, h, cz)
			z -= d + rng.randf_range(2.5, 5.0)
		# A second, taller row behind for skyline and back-alley routes
		z = 10.0
		while z > -110.0:
			var d2 := rng.randf_range(10.0, 14.0)
			var w2 := rng.randf_range(10.0, 12.0)
			house(side * (26.0 + w2 * 0.5), z - d2 * 0.5, w2, d2, rng.randf_range(12.0, 20.0), -side, rng)
			z -= d2 + rng.randf_range(3.0, 6.0)

	# Close off the near end of the street behind the spawn
	house(0.0, 34.0, 16.0, 10.0, 11.0, 1, rng)
	house(-16.0, 32.0, 12.0, 12.0, 14.0, 1, rng)
	house(16.0, 32.0, 12.0, 12.0, 13.0, -1, rng)

	# Lanterns strung across the street between facing rooftops
	var rope := PS1.lit(Color(0.3, 0.25, 0.2))
	var left: Array = heights.keys().filter(func(k): return k.x == -1)
	var right: Array = heights.keys().filter(func(k): return k.x == 1)
	for lk in left:
		var a: Vector3 = heights[lk]
		var best = null
		for rk in right:
			if best == null or abs(heights[rk].z - a.z) < abs(heights[best].z - a.z):
				best = rk
		var b: Vector3 = heights[best]
		if abs(b.z - a.z) > 6.0:
			continue
		var p1 := Vector3(a.x, a.y - 0.4, a.z)
		var p2 := Vector3(b.x, b.y - 0.4, b.z)
		var mid := (p1 + p2) * 0.5 + Vector3(0, -1.0, 0)   # sag
		rod(p1, mid, 0.05, rope)
		rod(mid, p2, 0.05, rope)
		lantern(mid, 0.8)

	# Street lamps, alternating sides
	var zz := 16.0
	var s := 1
	while zz > -108.0:
		lamp_post(s * 5.8, zz, rng.randf_range(4.5, 6.0), -s)
		zz -= 13.0
		s = -s

	# Bell tower closing off the far end of the street, lanterns on its arms
	var stone := PS1.lit(Color(0.9, 0.9, 0.95), "stone", 2.0)
	solid(Vector3(11, 30, 11), Vector3(0, 15, -124), stone)
	var spire := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 7.5
	cm.height = 12
	cm.radial_segments = 4
	cm.rings = 2
	spire.mesh = cm
	spire.material_override = PS1.lit(Color(0.8, 0.8, 0.85), "roof", 2.0)
	spire.position = Vector3(0, 36, -124)
	spire.rotation.y = PI * 0.25
	world.add_child(spire)
	var iron := PS1.lit(Color(0.13, 0.12, 0.13), "metal", 0.5)
	for ty in [14.0, 24.0]:
		for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1)]:
			var root: Vector3 = Vector3(0, ty, -124) + dir * 5.5
			var tip: Vector3 = root + dir * 2.2
			rod(root, tip, 0.14, iron)
			lantern(tip - Vector3(0, 0.05, 0), 0.7)

	_flush_batches()


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

	info_label = _label("", 16)
	info_label.position = Vector2(20, 16)
	root.add_child(info_label)

	toast = _label("", 36)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.size = Vector2(600, 50)
	toast.position = Vector2(-300, 90)
	root.add_child(toast)

	# Click-to-play / pause overlay
	overlay = ColorRect.new()
	(overlay as ColorRect).color = Color(0.02, 0.02, 0.05, 0.75)
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
		"Swing from the hanging lanterns. Only lanterns can be hooked.\n\n" +
		"Mouse — look        Hold LEFT CLICK — grapple (3 in the air, refill on landing)\n" +
		"Release LEFT CLICK — let go      Space — jump\n" +
		"WASD — walk, air-steer, push while hooked\n" +
		"Space / Right click / E / wheel up — reel in      Shift — dash\n" +
		"Q / Ctrl / wheel down — reel out\n" +
		"1 / 2 / 3 — physics preset      R — restart      Esc — pause", 20)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(help)

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
	if event is InputEventMouse:
		player.handle_mouse(event)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_3:
		set_preset(event.physical_keycode - KEY_1)
	elif event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _toast(t: String) -> void:
	toast.text = t
	toast_t = 1.8


func _process(dt: float) -> void:
	overlay.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED

	var spd := player.velocity.length()
	info_label.text = "Physics: %s   Speed %d" % [player.PRESETS[player.preset_index].name, roundi(spd * 3.6)]

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
		player.reset_to(START_POS, player.rotation.y)
