extends CharacterBody3D
## Third-person player with a Verlet-style grapple hook.
##
## Hold LEFT MOUSE on any surface to fire the hook and swing. Let go to fly.
## The rope is a distance constraint: each tick we predict where gravity and
## momentum would carry us, and if that point is farther from the anchor than
## the rope allows, we project it back onto the rope's sphere (classic Verlet
## constraint) and derive the velocity from the corrected position.

signal grappled

const GRAVITY := 13.0
const WALK_SPEED := 6.0
const GROUND_ACCEL := 25.0
const GROUND_FRICTION := 8.0
const JUMP_VELOCITY := 6.0
const AIR_ACCEL := 22.0
const AIR_SPEED := 9.0          # air strafe cap (quake-style)
const SWING_ACCEL := 7.0       # WASD "pump" force while hanging
const MAX_RANGE := 70.0         # how far the hook can reach
const MIN_ROPE := 2.5
const REEL_SPEED := 7.0
const ATTACH_PULL := 0.03       # rope shortens by this fraction on attach (the "tug")
const MAX_CORRECTION := 25.0    # caps rope-yank velocity so it never explodes
const MAX_SPEED := 20.8         # = 75 on the HUD speedometer (km/h)
const RELEASE_HOP := 3.5
const CAM_DISTANCE := 5.5
const CAM_SHOULDER := 0.8
const RETICLE_RADIUS := 48.0     # keep in sync with reticle.gd
const AIR_GRAPPLES := 3          # grapples you can fire before touching the ground
const DASH_SPEED := 15.0         # dash redirects you along the camera at least this fast
const DASH_COOLDOWN := 1.2
const RELEASE_BOOST := 0.15      # +15% speed when you let go while moving fast
const BOOST_MIN_SPEED := 10.0
const OVERSPEED_ALLOW := 1.3     # dash/release boost may briefly exceed the cap by 30%...
const OVERSPEED_BLEED := 2.5     # ...then bleed back down to it this fast (per second)
const CAM_PULLBACK := 3.0        # camera eases back this far at top speed
const TRAIL_POINTS := 40

var mouse_sensitivity := 0.0025

# ---- Physics presets (switch in-game with 1/2/3 or the pause menu) ----
const PRESETS := [
	{"name": "Float", "desc": "No gravity on the rope. Drift on your momentum.",
		"rope_gravity": 0.0, "elastic": 0.0, "pump": 7.0},
	{"name": "Light Arc", "desc": "25% gravity on the rope. Gentle, slow pendulum swings.",
		"rope_gravity": 0.25, "elastic": 0.0, "pump": 7.0},
	{"name": "Bungee", "desc": "Rope pulls you toward the hook like a stretchy band, 60% gravity. Fast and slingy.",
		"rope_gravity": 0.6, "elastic": 1.4, "pump": 16.0},
]
var preset_index := 0
var rope_gravity := 0.0   # fraction of GRAVITY applied while hooked
var elastic := 0.0        # 0 = rigid rope; >0 = pull strength toward the hook
var pump := SWING_ACCEL


func apply_preset(i: int) -> void:
	preset_index = clamp(i, 0, PRESETS.size() - 1)
	var p: Dictionary = PRESETS[preset_index]
	rope_gravity = p.rope_gravity
	elastic = p.elastic
	pump = p.pump

var head: Node3D
var cam: Camera3D
var body: MeshInstance3D
var arm: SpringArm3D
var rope: MeshInstance3D
var hook: MeshInstance3D

var attached := false
var anchor := Vector3.ZERO
var rope_len := 0.0
var pull_left := 0.0

# What the crosshair is pointing at (read by the HUD)
var air_grapples := AIR_GRAPPLES
var dash_cd := 0.0
var trail: MeshInstance3D
var trail_mesh: ImmediateMesh
var trail_pts: Array[Vector3] = []
var aim_valid := false
var aim_point := Vector3.ZERO
var target_marker: MeshInstance3D
var _reticle_offsets: Array[Vector2] = []
var aim_distance := 0.0
var controls_enabled := true


func _ready() -> void:
	collision_layer = 8   # player layer (areas watch this)
	collision_mask = 1    # collide with world
	floor_max_angle = deg_to_rad(50)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	add_child(col)

	# Placeholder body: a capsule with a visor so you can tell which way it faces
	body = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.4
	bm.height = 1.8
	body.mesh = bm
	body.material_override = _mat(Color(0.95, 0.55, 0.2))
	add_child(body)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.5, 0.18, 0.2)
	visor.mesh = vm
	visor.material_override = _mat(Color(0.15, 0.2, 0.3))
	visor.position = Vector3(0, 0.45, -0.32)
	body.add_child(visor)

	# Third-person rig: yaw on the body, pitch on the head pivot, camera on a
	# spring arm so it pulls in instead of clipping through walls.
	head = Node3D.new()
	head.position.y = 0.9
	add_child(head)

	arm = SpringArm3D.new()
	arm.spring_length = CAM_DISTANCE
	arm.margin = 0.3
	arm.collision_mask = 1
	arm.add_excluded_object(get_rid())
	arm.position = Vector3(CAM_SHOULDER, 0, 0)   # over-the-shoulder so the crosshair stays clear
	head.add_child(arm)

	cam = Camera3D.new()
	cam.fov = 75
	cam.far = 1500
	cam.near = 0.05
	arm.add_child(cam)

	rope = MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.03
	rm.bottom_radius = 0.03
	rm.height = 1.0
	rm.radial_segments = 6
	rm.rings = 1
	rope.mesh = rm
	rope.material_override = _mat(Color(1.0, 0.6, 0.15), true)
	rope.top_level = true
	rope.visible = false
	add_child(rope)

	_reticle_offsets.append(Vector2.ZERO)
	for ring in [[0.5, 6], [1.0, 12]]:
		for k in ring[1]:
			var a: float = TAU * k / ring[1]
			_reticle_offsets.append(Vector2(cos(a), sin(a)) * RETICLE_RADIUS * ring[0])

	target_marker = MeshInstance3D.new()
	var tmm := SphereMesh.new()
	tmm.radius = 0.35
	tmm.height = 0.7
	target_marker.mesh = tmm
	target_marker.material_override = _mat(Color(0.4, 1.0, 0.5), true)
	target_marker.top_level = true
	target_marker.visible = false
	add_child(target_marker)

	trail_mesh = ImmediateMesh.new()
	trail = MeshInstance3D.new()
	trail.mesh = trail_mesh
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	tmat.vertex_color_use_as_albedo = true
	trail.material_override = tmat
	trail.top_level = true
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trail)

	hook = MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.25
	hm.height = 0.5
	hook.mesh = hm
	hook.material_override = _mat(Color(1.0, 0.75, 0.2), true)
	hook.top_level = true
	hook.visible = false
	add_child(hook)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not controls_enabled:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		head.rotate_x(-event.relative.y * mouse_sensitivity)
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-80), deg_to_rad(70))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				try_grapple()
			else:
				release()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and attached:
			rope_len = max(MIN_ROPE, rope_len - 0.75)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and attached:
			rope_len = min(MAX_RANGE, rope_len + 0.75)


func aim_ray() -> Dictionary:
	# Fan of rays across the reticle circle; keep the hit nearest the player.
	var vp := get_viewport()
	var center := vp.get_visible_rect().size * 0.5
	var space := get_world_3d().direct_space_state
	var reach := MAX_RANGE + arm.get_hit_length()
	var best := {}
	var best_d := INF
	for off in _reticle_offsets:
		var sp: Vector2 = center + off
		var from := cam.project_ray_origin(sp)
		var to := from + cam.project_ray_normal(sp) * reach
		var q := PhysicsRayQueryParameters3D.create(from, to, 2, [get_rid()])   # grappleable layer only
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		# Range counts from the player, not the camera behind them
		var d := global_position.distance_to(hit.position)
		if d <= MAX_RANGE and d < best_d:
			best_d = d
			best = hit
	return best


func try_grapple() -> void:
	var hit := aim_ray()
	if hit.is_empty():
		return
	var grounded := is_on_floor()
	if not grounded:
		if air_grapples <= 0:
			return
		air_grapples -= 1
	attached = true
	anchor = hit.position
	rope_len = global_position.distance_to(anchor)
	pull_left = rope_len * ATTACH_PULL
	grappled.emit()


func release(hop := false) -> void:
	if not attached:
		return
	attached = false
	# Release boost: letting go at speed flings you a little harder
	var spd := velocity.length()
	if spd > BOOST_MIN_SPEED:
		velocity *= 1.0 + RELEASE_BOOST
	if hop:
		velocity.y = max(velocity.y, 0.0) + RELEASE_HOP


func reset_to(pos: Vector3, yaw: float) -> void:
	release()
	global_position = pos
	velocity = Vector3.ZERO
	air_grapples = AIR_GRAPPLES
	trail_pts.clear()
	rotation.y = yaw
	head.rotation.x = 0.0


func _physics_process(dt: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := global_basis * Vector3(input.x, 0, input.y)
	wish.y = 0
	wish = wish.normalized()

	velocity.y -= GRAVITY * (rope_gravity if attached else 1.0) * dt

	if attached:
		if is_on_floor():
			_walk(wish, dt)   # rope is slack on the ground: walk normally, no ice-skating
		var look_wish := (cam.global_basis * Vector3(input.x, 0, input.y)).normalized()
		_swing(look_wish, dt)
	elif is_on_floor():
		_walk(wish, dt)
		if controls_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		# Air strafe: can steer, but can't accelerate past AIR_SPEED in the wish direction
		var cur := Vector3(velocity.x, 0, velocity.z).dot(wish)
		if wish != Vector3.ZERO and cur < AIR_SPEED:
			velocity += wish * min(AIR_ACCEL * dt, AIR_SPEED - cur)

	# Dash: snap your momentum toward where the camera looks
	dash_cd = max(dash_cd - dt, 0.0)
	if controls_enabled and dash_cd == 0.0 and Input.is_action_just_pressed("dash"):
		var dir := -cam.global_basis.z
		velocity = dir * max(velocity.length(), DASH_SPEED) * (1.0 + RELEASE_BOOST)
		dash_cd = DASH_COOLDOWN

	# Speed cap: normal movement tops out at MAX_SPEED; boosts may poke above
	# it briefly and bleed back down.
	var spd := velocity.length()
	if spd > MAX_SPEED * OVERSPEED_ALLOW:
		velocity = velocity / spd * MAX_SPEED * OVERSPEED_ALLOW
	elif spd > MAX_SPEED:
		velocity = velocity / spd * max(MAX_SPEED, spd - MAX_SPEED * OVERSPEED_BLEED * dt)

	floor_snap_length = 0.0 if attached else 0.3
	move_and_slide()
	if is_on_floor():
		air_grapples = AIR_GRAPPLES
	_update_trail()


func _walk(wish: Vector3, dt: float) -> void:
	var h := Vector3(velocity.x, 0, velocity.z)
	if h.length() > WALK_SPEED * 1.05:
		# Landed with swing momentum: bleed it off smoothly instead of a hard stop
		h = h.lerp(wish * WALK_SPEED, clamp(GROUND_FRICTION * 0.35 * dt, 0.0, 1.0))
	elif wish != Vector3.ZERO:
		h = h.move_toward(wish * WALK_SPEED, GROUND_ACCEL * dt)
	else:
		h = h.move_toward(Vector3.ZERO, GROUND_ACCEL * dt)
	velocity.x = h.x
	velocity.z = h.z


func _swing(wish: Vector3, dt: float) -> void:
	var rope_dir := (global_position - anchor).normalized()

	# Pump: push perpendicular to the rope in the direction you're holding
	var push := wish - rope_dir * wish.dot(rope_dir)
	velocity += push * pump * dt

	# Bungee preset: rope tugs you toward the hook, harder the farther you are
	if elastic > 0.0:
		var dist := global_position.distance_to(anchor)
		velocity -= rope_dir * min(elastic * max(dist - 3.0, 0.0), 22.0) * dt
		rope_len = min(rope_len, dist + 0.5)   # rope tightens as you're pulled in

	# The initial tug, then manual reeling
	if pull_left > 0.0:
		var p: float = min(pull_left, REEL_SPEED * 1.5 * dt)
		rope_len -= p
		pull_left -= p
	if controls_enabled:
		if Input.is_action_pressed("reel_in") or Input.is_action_pressed("jump"):
			rope_len -= REEL_SPEED * dt
		if Input.is_action_pressed("reel_out"):
			rope_len += REEL_SPEED * dt
	rope_len = clamp(rope_len, MIN_ROPE, MAX_RANGE)

	# Verlet distance constraint: predict, project back onto the rope sphere
	var next := global_position + velocity * dt
	var off := next - anchor
	var d := off.length()
	if d > rope_len and d > 0.001:
		var corrected := anchor + off / d * rope_len
		var fix := (corrected - next) / dt
		if fix.length() > MAX_CORRECTION:
			fix = fix.normalized() * MAX_CORRECTION
		velocity += fix


func _process(_dt: float) -> void:
	# Crosshair state
	var hit := aim_ray()
	aim_valid = not hit.is_empty()
	aim_point = hit.position if aim_valid else Vector3.ZERO
	aim_distance = global_position.distance_to(aim_point) if aim_valid else 0.0
	target_marker.visible = aim_valid and not attached and controls_enabled and (air_grapples > 0 or is_on_floor())
	if target_marker.visible:
		target_marker.global_position = aim_point

	# Speed FOV kick
	var spd := velocity.length()
	cam.fov = lerp(cam.fov, 72.0 + clamp((spd - 8.0) * 0.6, 0.0, 22.0), 0.08)
	arm.spring_length = lerp(arm.spring_length, CAM_DISTANCE + CAM_PULLBACK * clamp((spd - 6.0) / (MAX_SPEED - 6.0), 0.0, 1.0), 0.05)

	# Rope visual from the gun tip to the anchor
	rope.visible = attached
	hook.visible = attached
	if attached:
		var a := global_position + Vector3(0, 0.3, 0)
		var b := anchor
		var dir := b - a
		var length := dir.length()
		if length > 0.01:
			var y := dir / length
			var helper := Vector3.UP if abs(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
			var x := y.cross(helper).normalized()
			var z := x.cross(y)
			rope.global_transform = Transform3D(Basis(x, y * length, z), (a + b) * 0.5)
		hook.global_position = anchor


# Fading ribbon behind the capsule so you can read your arc.
func _update_trail() -> void:
	var spd := velocity.length()
	if spd > 5.0:
		trail_pts.push_front(global_position)
	elif not trail_pts.is_empty():
		trail_pts.pop_back()   # shrink away when you slow down
	while trail_pts.size() > TRAIL_POINTS:
		trail_pts.pop_back()
	trail_mesh.clear_surfaces()
	if trail_pts.size() < 2:
		return
	var eye := cam.global_position
	trail_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := trail_pts.size()
	for i in n:
		var p := trail_pts[i]
		var nxt := trail_pts[min(i + 1, n - 1)]
		var prv := trail_pts[max(i - 1, 0)]
		var along := (nxt - prv)
		if along.length_squared() < 0.0001:
			along = Vector3.FORWARD
		var side := along.cross(eye - p).normalized()
		var t := float(i) / (n - 1)
		var w := 0.35 * (1.0 - t)
		var c := Color(1.0, 0.6, 0.2, 0.6 * (1.0 - t))
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(p + side * w)
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(p - side * w)
	trail_mesh.surface_end()
