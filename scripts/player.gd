extends CharacterBody3D
## First-person player with a Verlet-style grapple hook.
##
## Hold LEFT MOUSE on any surface to fire the hook and swing. Let go to fly.
## The rope is a distance constraint: each tick we predict where gravity and
## momentum would carry us, and if that point is farther from the anchor than
## the rope allows, we project it back onto the rope's sphere (classic Verlet
## constraint) and derive the velocity from the corrected position.

signal grappled

const GRAVITY := 24.0
const WALK_SPEED := 9.0
const GROUND_ACCEL := 70.0
const GROUND_FRICTION := 8.0
const JUMP_VELOCITY := 8.0
const AIR_ACCEL := 30.0
const AIR_SPEED := 7.0          # air strafe cap (quake-style)
const SWING_ACCEL := 14.0       # WASD "pump" force while hanging
const MAX_RANGE := 70.0         # how far the hook can reach
const MIN_ROPE := 2.5
const REEL_SPEED := 18.0
const ATTACH_PULL := 0.15       # rope shortens by this fraction on attach (the "tug")
const MAX_CORRECTION := 45.0    # caps rope-yank velocity so it never explodes
const MAX_SPEED := 90.0
const RELEASE_HOP := 5.0

var mouse_sensitivity := 0.0025

var head: Node3D
var cam: Camera3D
var gun: MeshInstance3D
var rope: MeshInstance3D
var hook: MeshInstance3D

var attached := false
var anchor := Vector3.ZERO
var rope_len := 0.0
var pull_left := 0.0

# What the crosshair is pointing at (read by the HUD)
var aim_valid := false
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

	head = Node3D.new()
	head.position.y = 0.65
	add_child(head)

	cam = Camera3D.new()
	cam.fov = 80
	cam.far = 1500
	cam.near = 0.05
	head.add_child(cam)

	# Placeholder grapple gun: a chunky box in the lower right of the view
	gun = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.12, 0.12, 0.5)
	gun.mesh = gm
	gun.material_override = _mat(Color(0.25, 0.27, 0.32))
	gun.position = Vector3(0.32, -0.28, -0.55)
	cam.add_child(gun)
	var tip := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.08, 0.08, 0.1)
	tip.mesh = tm
	tip.material_override = _mat(Color(1.0, 0.55, 0.1), true)
	tip.position = Vector3(0, 0, -0.28)
	gun.add_child(tip)

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
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-89), deg_to_rad(89))
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				try_grapple()
			else:
				release()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP and attached:
			rope_len = max(MIN_ROPE, rope_len - 1.5)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and attached:
			rope_len = min(MAX_RANGE, rope_len + 1.5)


func aim_ray() -> Dictionary:
	var from := cam.global_position
	var to := from - cam.global_basis.z * MAX_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q)


func try_grapple() -> void:
	var hit := aim_ray()
	if hit.is_empty():
		return
	attached = true
	anchor = hit.position
	rope_len = global_position.distance_to(anchor)
	pull_left = rope_len * ATTACH_PULL
	grappled.emit()


func release(hop := false) -> void:
	if not attached:
		return
	attached = false
	if hop:
		velocity.y = max(velocity.y, 0.0) + RELEASE_HOP


func reset_to(pos: Vector3, yaw: float) -> void:
	release()
	global_position = pos
	velocity = Vector3.ZERO
	rotation.y = yaw
	head.rotation.x = 0.0


func _physics_process(dt: float) -> void:
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish := global_basis * Vector3(input.x, 0, input.y)
	wish.y = 0
	wish = wish.normalized()

	velocity.y -= GRAVITY * dt

	if attached:
		_swing(wish, dt)
		if controls_enabled and Input.is_action_just_pressed("jump"):
			release(true)
	elif is_on_floor():
		_walk(wish, dt)
		if controls_enabled and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		# Air strafe: can steer, but can't accelerate past AIR_SPEED in the wish direction
		var cur := Vector3(velocity.x, 0, velocity.z).dot(wish)
		if wish != Vector3.ZERO and cur < AIR_SPEED:
			velocity += wish * min(AIR_ACCEL * dt, AIR_SPEED - cur)

	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED

	floor_snap_length = 0.0 if attached else 0.3
	move_and_slide()


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
	velocity += push * SWING_ACCEL * dt

	# The initial tug, then manual reeling
	if pull_left > 0.0:
		var p: float = min(pull_left, REEL_SPEED * 1.5 * dt)
		rope_len -= p
		pull_left -= p
	if controls_enabled:
		if Input.is_action_pressed("reel_in"):
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
	aim_distance = cam.global_position.distance_to(hit.position) if aim_valid else 0.0

	# Speed FOV kick
	var spd := velocity.length()
	cam.fov = lerp(cam.fov, 78.0 + clamp((spd - 8.0) * 0.6, 0.0, 22.0), 0.08)

	# Rope visual from the gun tip to the anchor
	rope.visible = attached
	hook.visible = attached
	if attached:
		var a := gun.global_position + gun.global_basis * Vector3(0, 0, -0.3)
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
