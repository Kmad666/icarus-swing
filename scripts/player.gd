extends CharacterBody3D
## Third-person thief with a Verlet-style grapple: her pocket-watch chain.
##
## Hold LEFT MOUSE to fire the arrowhead at the lantern under the reticle; when it
## lands she swings. Let go to fly, and the arrow zips back to her shoulder.
## The rope is a distance constraint: each tick we predict where gravity and
## momentum would carry us, and if that point is farther from the anchor than
## the rope allows, we project it back onto the rope's sphere (classic Verlet
## constraint) and derive the velocity from the corrected position.

signal grappled

const Chain := preload("res://scripts/chain.gd")

const GRAVITY := 13.0
const WALK_SPEED := 6.0
const GROUND_ACCEL := 25.0
const GROUND_FRICTION := 8.0
const JUMP_VELOCITY := 6.0
const AIR_ACCEL := 22.0
const AIR_SPEED := 9.0          # air strafe cap (quake-style)
const SWING_ACCEL := 7.0       # WASD "pump" force while hanging
const MIN_ROPE := 2.5
const REEL_SPEED := 7.0
const ATTACH_PULL := 0.03       # rope shortens by this fraction on attach (the "tug")
const MAX_CORRECTION := 25.0    # caps rope-yank velocity so it never explodes
const MAX_SPEED := 11.11        # = 40 on the HUD speedometer (km/h)
const RELEASE_HOP := 3.5
const CAM_DISTANCE := 4.6
const CAM_SHOULDER := 0.6
const CAM_HEIGHT := 0.9
const CAM_IDLE_DISTANCE := 2.3   # camera eases in when she stands still...
const IDLE_DELAY := 1.5          # ...for this many seconds, and she turns to face you
const RETICLE_RADIUS := 48.0     # keep in sync with reticle.gd
# Grapple levels 1..10: reach (m) and how many grapples you get before touching the ground
const LEVEL_RANGE := [12.0, 15.0, 18.0, 21.0, 24.0, 27.0, 30.0, 33.0, 36.0, 40.0]
const ARROW_SPEED := 90.0        # m/s the arrowhead flies out
const RETURN_SPEED := 55.0       # m/s it zips back
const DASH_SPEED := 10.0         # dash redirects you along the camera at least this fast
const DASH_COOLDOWN := 1.2
const RELEASE_BOOST := 0.15      # +15% speed when you let go while moving fast
const BOOST_MIN_SPEED := 6.0
const OVERSPEED_ALLOW := 1.3     # dash/release boost may briefly exceed the cap by 30%...
const OVERSPEED_BLEED := 2.5     # ...then bleed back down to it this fast (per second)
const CAM_PULLBACK := 3.0        # camera eases back this far at top speed
const TRAIL_POINTS := 24

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
var thief: Node3D
var lanterns: Array = []          # set by main: the only grapple targets
var target_lantern: Node3D
var hooked_lantern: Node3D
var arm: SpringArm3D
var chain: Node3D

var attached := false
var anchor := Vector3.ZERO
var rope_len := 0.0
var pull_left := 0.0

# What the crosshair is pointing at (read by the HUD)
var grapple_level := 1
var grapple_range: float = LEVEL_RANGE[0]
var air_max := 1                 # grapples allowed per jump at this level
var air_grapples := 1
var hook_state := 0              # chain.gd: STOWED, FLYING, HOOKED, RETURNING
var hook_tip := Vector3.ZERO     # arrowhead tip, world space
var hook_target: Node3D          # lantern the arrow is flying at
var idle_time := 0.0
var idle_amount := 0.0   # 0..1, read by the HUD to fade the reticle in close-up
var dash_cd := 0.0
var trail: MeshInstance3D
var trail_mesh: ImmediateMesh
var trail_pts: Array[Vector3] = []
var aim_valid := false
var aim_point := Vector3.ZERO
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

	thief = preload("res://scripts/heroine.gd").new()
	add_child(thief)

	# Third-person rig: yaw on the body, pitch on the head pivot, camera on a
	# spring arm so it pulls in instead of clipping through walls.
	head = Node3D.new()
	head.position.y = CAM_HEIGHT
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

	chain = Chain.new()
	chain.heroine = thief
	add_child(chain)

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

	set_level(1)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Mouse look and grapple buttons. Main forwards mouse events here, because the
## player lives inside the low-res SubViewport, which doesn't receive them itself.
func handle_mouse(event: InputEvent) -> void:
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
			rope_len = min(grapple_range, rope_len + 0.75)


func aim_ray() -> Dictionary:
	# Of the lanterns inside the reticle circle, in range and in line of sight,
	# pick the one nearest the player. Returns {} or {position, lantern}.
	var vp := cam.get_viewport()
	var vp_size := vp.get_visible_rect().size
	var center := vp_size * 0.5
	var radius := RETICLE_RADIUS / 720.0 * vp_size.y   # HUD is laid out on a 720-high canvas
	var space := get_world_3d().direct_space_state
	var best := {}
	var best_d := INF
	for l in lanterns:
		var anchor_pos: Vector3 = l.global_position
		var d := global_position.distance_to(anchor_pos)
		if d > grapple_range or d >= best_d:
			continue
		var look_at_pos: Vector3 = anchor_pos + Vector3(0, -l.chain_length - 0.5, 0)   # the glowing body
		if cam.is_position_behind(look_at_pos):
			continue
		if cam.unproject_position(look_at_pos).distance_to(center) > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, look_at_pos, 1, [get_rid()])
		if not space.intersect_ray(q).is_empty():
			continue   # a wall or roof is in the way
		best_d = d
		best = {"position": anchor_pos, "lantern": l}
	return best


func set_level(lv: int) -> void:
	grapple_level = clampi(lv, 1, LEVEL_RANGE.size())
	grapple_range = LEVEL_RANGE[grapple_level - 1]
	air_max = grapple_level
	air_grapples = air_max if is_on_floor() else mini(air_grapples, air_max)


## Fire the arrowhead at the lantern under the reticle. It attaches when it arrives.
func try_grapple() -> void:
	if hook_state == Chain.FLYING or attached:
		return
	var hit := aim_ray()
	if hit.is_empty():
		return
	if not is_on_floor():
		if air_grapples <= 0:
			return
		air_grapples -= 1
	hook_target = hit.lantern
	hook_state = Chain.FLYING


func _attach() -> void:
	attached = true
	hook_state = Chain.HOOKED
	anchor = hook_target.global_position
	hook_tip = anchor
	hooked_lantern = hook_target
	rope_len = minf(global_position.distance_to(anchor), grapple_range)
	pull_left = rope_len * ATTACH_PULL
	grappled.emit()


## Let go (or cancel a shot still in flight); the arrow heads home.
func release(hop := false) -> void:
	if hook_state == Chain.FLYING:
		hook_state = Chain.RETURNING
		return
	if not attached:
		return
	attached = false
	hook_state = Chain.RETURNING
	# Release boost: letting go at speed flings you a little harder
	var spd := velocity.length()
	if spd > BOOST_MIN_SPEED:
		velocity *= 1.0 + RELEASE_BOOST
	if hop:
		velocity.y = max(velocity.y, 0.0) + RELEASE_HOP


## Moves the arrowhead out to its lantern or back home. Runs on the physics tick
## because arriving is what attaches the rope.
func _update_hook(dt: float) -> void:
	match hook_state:
		Chain.FLYING:
			var goal: Vector3 = hook_target.global_position
			var to := goal - hook_tip
			var step := ARROW_SPEED * dt
			if to.length() <= step:
				_attach()
			else:
				hook_tip += to / to.length() * step
		Chain.HOOKED:
			hook_tip = anchor
		Chain.RETURNING:
			var home: Vector3 = chain.stowed_tip(_aim_dir())
			var to := home - hook_tip
			var step := maxf(RETURN_SPEED * dt, to.length() * (1.0 - exp(-18.0 * dt)))
			if to.length() <= step + 0.02:
				hook_state = Chain.STOWED
			else:
				hook_tip += to / to.length() * step
		_:
			hook_tip = chain.stowed_tip(_aim_dir())


## Where the stowed arrowhead points: at the targeted lantern, else where the camera looks.
func _aim_dir() -> Vector3:
	if is_instance_valid(target_lantern) and not attached:
		return target_lantern.global_position - thief.hover_point()
	return -cam.global_basis.z


func reset_to(pos: Vector3, yaw: float) -> void:
	release()
	global_position = pos
	velocity = Vector3.ZERO
	air_grapples = air_max
	hook_state = Chain.STOWED
	idle_time = 0.0
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

	if is_on_floor() and not attached and input == Vector2.ZERO and Vector2(velocity.x, velocity.z).length() < 0.5:
		idle_time += dt
	else:
		idle_time = 0.0

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
		air_grapples = air_max
	_update_hook(dt)
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
	rope_len = clamp(rope_len, MIN_ROPE, grapple_range)

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
	var can_fire := controls_enabled and not attached and hook_state != Chain.FLYING and (air_grapples > 0 or is_on_floor())
	aim_valid = not hit.is_empty()
	aim_point = hit.position if aim_valid else Vector3.ZERO
	aim_distance = global_position.distance_to(aim_point) if aim_valid else 0.0
	var new_target: Node3D = hit.lantern if aim_valid and can_fire else null
	if attached:
		new_target = hooked_lantern
	elif hook_state == Chain.FLYING:
		new_target = hook_target
	if new_target != target_lantern:
		if is_instance_valid(target_lantern):
			target_lantern.set_targeted(false)
		target_lantern = new_target
		if target_lantern:
			target_lantern.set_targeted(true)

	var idle_k := smoothstep(IDLE_DELAY, IDLE_DELAY + 1.0, idle_time)
	idle_amount = idle_k
	thief.animate(_dt, velocity, is_on_floor(), attached, anchor, cam.global_position, idle_k)

	# Speed FOV kick
	var spd := velocity.length()
	cam.fov = lerp(cam.fov, 72.0 + clamp((spd - 4.0) * 1.4, 0.0, 14.0), 0.08)
	var cam_target := CAM_DISTANCE + CAM_PULLBACK * clampf((spd - 6.0) / (MAX_SPEED - 6.0), 0.0, 1.0)
	arm.spring_length = lerp(arm.spring_length, lerpf(cam_target, CAM_IDLE_DISTANCE, idle_k), 0.05)
	arm.position.x = lerpf(CAM_SHOULDER, 0.0, idle_k)
	head.position.y = lerpf(CAM_HEIGHT, 0.6, idle_k)

	chain.update(_dt, hook_state, hook_tip, _aim_dir())


# Fading ribbon behind the thief so you can read your arc.
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
		var w := 0.07 * (1.0 - t)
		var c := Color(0.75, 0.82, 1.0, 0.12 * (1.0 - t))   # faint wind streak
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(p + side * w)
		trail_mesh.surface_set_color(c)
		trail_mesh.surface_add_vertex(p - side * w)
	trail_mesh.surface_end()
