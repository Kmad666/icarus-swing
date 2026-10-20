extends Node3D
## The heroine: a chibi thief with a big round head of lavender hair, sleepy
## glowing eyes, a cone cloak that swallows her torso and arms, and slim legs
## that taper to points like a ballerina's.
##
## Faces -Z. Origin is the centre of the player's 1.8 m capsule (feet at y = -0.9).
## Everything is code-built, low-poly, and animated procedurally.

const HAIR := Color(0.80, 0.78, 0.95)
const HAIR_SHADE := Color(0.66, 0.63, 0.88)
const SKIN := Color(1.0, 0.82, 0.68)
const SKIN_SHADE := Color(0.88, 0.64, 0.50)
const CLOAK := Color(0.36, 0.20, 0.38)
const CLOAK_DARK := Color(0.26, 0.14, 0.28)
const COPPER := Color(0.85, 0.55, 0.28)
const LEGS := Color(0.82, 0.80, 0.90)   # pale ballet tights
const GLOVE := Color(0.25, 0.17, 0.12)
const EYE_GLOW := Color(1.0, 0.78, 0.36)
const PUPIL := Color(0.16, 0.08, 0.19)
const LID := Color(0.10, 0.06, 0.12)
const BLUSH := Color(0.95, 0.55, 0.55)
const MOUTH := Color(0.45, 0.16, 0.16)

var body: Node3D        # everything above the hips; leans and bobs
var head: Node3D
var cloak: Node3D
var hem: Array[Node3D] = []
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var arm: Node3D         # the one arm that pokes out of the cloak to hold the rope
var hand: Node3D
var eyes: Array[Node3D] = []
var pupils: Array[Node3D] = []
var lids: Array[Node3D] = []

var _t := 0.0
var _phase := 0.0
var _squash := 0.0
var _was_floor := true
var _facing := 0.0
var _arm_out := 0.0
var _blink_t := 2.0
var _surprise := 0.0


func _ready() -> void:
	body = _pivot(self, Vector3(0, -0.45, 0))

	# --- legs: thin, tapering to copper points (under the cloak hem)
	leg_l = _pivot(self, Vector3(-0.09, -0.5, 0))
	leg_r = _pivot(self, Vector3(0.09, -0.5, 0))
	for leg in [leg_l, leg_r]:
		_cyl(leg, 0.075, 0.055, 0.21, Vector3(0, -0.1, 0), PS1.lit_char(LEGS), 5)
	knee_l = _pivot(leg_l, Vector3(0, -0.2, 0))
	knee_r = _pivot(leg_r, Vector3(0, -0.2, 0))
	for k in [knee_l, knee_r]:
		_cyl(k, 0.055, 0.022, 0.16, Vector3(0, -0.08, 0), PS1.lit_char(LEGS), 5)
		_cyl(k, 0.022, 0.0, 0.07, Vector3(0, -0.195, 0), PS1.lit_char(COPPER), 5)

	# --- cloak: an 8-sided cone from the neck to the thighs, ragged hem flaps
	cloak = _pivot(body, Vector3(0, 0.5, 0))
	_cyl(cloak, 0.13, 0.38, 0.56, Vector3(0, -0.28, 0), PS1.lit_char(CLOAK, "cloth", 0.5), 8)
	_cyl(cloak, 0.12, 0.35, 0.53, Vector3(0, -0.28, 0.0), PS1.lit_char(CLOAK_DARK), 8).scale = Vector3(-1, 1, 1)  # lining seen from below
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var flap := _pivot(cloak, Vector3(sin(a) * 0.36, -0.55, cos(a) * 0.36))
		flap.rotation.y = a
		var tri := _cyl(flap, 0.12, 0.0, 0.13, Vector3(0, -0.065, 0), PS1.lit_char(CLOAK, "cloth", 0.5), 3)
		tri.scale = Vector3(1, 1, 0.35)
		hem.append(flap)
	# Hood bunched at the neck as a collar, with a copper clasp
	_cyl(cloak, 0.20, 0.25, 0.1, Vector3(0, -0.02, 0), PS1.lit_char(CLOAK.lightened(0.12), "cloth", 0.5), 8)
	_box(cloak, Vector3(0.07, 0.07, 0.04), Vector3(0, -0.05, -0.24), PS1.lit_char(COPPER))

	# --- the arm that comes out of the cloak to fire and hold the rope
	arm = _pivot(cloak, Vector3(0.2, -0.12, -0.05))
	_cyl(arm, 0.06, 0.07, 0.34, Vector3(0, -0.17, 0), PS1.lit_char(CLOAK, "cloth", 0.5), 5)
	hand = _pivot(arm, Vector3(0, -0.36, 0))
	_box(hand, Vector3(0.09, 0.1, 0.09), Vector3.ZERO, PS1.lit_char(GLOVE))
	arm.scale = Vector3.ONE * 0.01

	# --- head: round, wide, faceted
	head = _pivot(cloak, Vector3(0, 0.0, 0))
	var hc := Vector3(0, 0.40, 0)     # head centre
	# hair dome (back and top), wider than tall
	_sphere(head, 0.46, 0.84, hc + Vector3(0, 0.13, 0.05), PS1.lit_char(HAIR), 10, 6).scale = Vector3(1.2, 1.0, 1.02)
	# face: a squashed sphere pushed forward under the dome
	_sphere(head, 0.40, 0.70, hc + Vector3(0, -0.06, -0.1), PS1.lit_char(SKIN, "", 2.0, 0.5), 10, 6).scale = Vector3(1.12, 0.92, 0.82)
	# small pointed ears
	for sx in [-1, 1]:
		var ear := _cyl(head, 0.06, 0.0, 0.13, hc + Vector3(sx * 0.47, -0.08, -0.04), PS1.lit_char(SKIN_SHADE), 4)
		ear.rotation.z = -sx * PI * 0.5
	# bangs: a slab across the forehead plus notched spikes
	var bangs := PS1.lit_char(HAIR_SHADE)
	_sphere(head, 0.44, 0.88, hc + Vector3(0, 0.1, -0.05), PS1.lit_char(HAIR), 10, 4).scale = Vector3(1.08, 0.3, 0.93)
	for bx in [-0.32, -0.16, 0.0, 0.17, 0.33]:
		var spike := _cyl(head, 0.065, 0.0, 0.12, hc + Vector3(bx, 0.01, -0.37 + abs(bx) * 0.12), bangs, 3)
		spike.rotation.x = PI   # point down
		spike.scale = Vector3(1, 1, 0.5)
	# long side locks down past the jaw, and flicks out at the sides
	for sx in [-1, 1]:
		var lock := _cyl(head, 0.08, 0.035, 0.52, hc + Vector3(sx * 0.42, -0.2, -0.16), PS1.lit_char(HAIR if sx < 0 else HAIR_SHADE), 4)
		lock.scale = Vector3(1, 1, 0.6)
		var flick := _cyl(head, 0.07, 0.0, 0.22, hc + Vector3(sx * 0.58, -0.02, 0.02), bangs, 4)
		flick.rotation.z = -sx * (PI * 0.5 + 0.35)

	# face details, sitting on the face surface
	var fz := -0.38   # front of the face
	for sx in [-1, 1]:
		var e := _pivot(head, hc + Vector3(sx * 0.18, -0.12, fz + 0.035))
		e.rotation.y = -sx * 0.32
		_box(e, Vector3(0.19, 0.17, 0.02), Vector3.ZERO, PS1.unlit(EYE_GLOW))            # glowing eye
		var pupil := _pivot(e, Vector3(0.03, -0.01, -0.012))                          # glancing to her right
		_box(pupil, Vector3(0.12, 0.15, 0.02), Vector3.ZERO, PS1.unlit(PUPIL))
		_box(pupil, Vector3(0.03, 0.03, 0.01), Vector3(-0.025, 0.03, -0.012), PS1.unlit(Color(1, 0.96, 0.85)))
		var lid := _pivot(e, Vector3(0, 0.08, -0.02))
		_box(lid, Vector3(0.22, 0.035, 0.025), Vector3.ZERO, PS1.unlit(LID))             # heavy upper lid
		_box(e, Vector3(0.15, 0.014, 0.02), Vector3(0, -0.09, -0.005), PS1.unlit(LID))   # lower lash
		_box(head, Vector3(0.1, 0.035, 0.02), hc + Vector3(sx * 0.22, -0.25, fz + 0.08), PS1.unlit(BLUSH)).rotation.y = -sx * 0.4
		eyes.append(e)
		pupils.append(pupil)
		lids.append(lid)
	# little upside-down V mouth
	for sx in [-1, 1]:
		var m := _box(head, Vector3(0.05, 0.016, 0.02), hc + Vector3(sx * 0.02, -0.3, fz + 0.06), PS1.unlit(MOUTH))
		m.rotation.z = sx * -0.6


# ------------------------------------------------------------ mesh helpers
func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _mesh(parent: Node3D, m: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh(parent, m, pos, mat)


func _cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, mat: Material, seg := 6) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	m.radial_segments = seg
	m.rings = 1
	return _mesh(parent, m, pos, mat)


func _sphere(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, seg := 8, rings := 4) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = seg
	m.rings = rings
	return _mesh(parent, m, pos, mat)


func hand_position() -> Vector3:
	return hand.global_position


# ------------------------------------------------------------ animation
## Called every frame by the player.
func animate(dt: float, vel: Vector3, on_floor: bool, attached: bool, anchor: Vector3) -> void:
	_t += dt
	var k := 1.0 - exp(-14.0 * dt)
	var hvel := Vector3(vel.x, 0, vel.z)
	var hs := hvel.length()
	var speed := vel.length()

	if hs > 0.6:
		_facing = lerp_angle(_facing, atan2(-hvel.x, -hvel.z), 1.0 - exp(-10.0 * dt))
	global_rotation = Vector3(0, _facing, 0)

	# Light landing hop instead of a heavy squash
	if on_floor and not _was_floor:
		_squash = 1.0
	_was_floor = on_floor
	_squash = max(_squash - dt * 6.0, 0.0)
	scale = Vector3(1.0 + 0.08 * _squash, 1.0 - 0.12 * _squash, 1.0 + 0.08 * _squash)

	var lean := Vector3.ZERO           # body tilt
	var head_rot := Vector3.ZERO
	var ll := Vector3.ZERO             # leg_l, leg_r, knee_l, knee_r targets
	var lr := Vector3.ZERO
	var kl := Vector3.ZERO
	var kr := Vector3.ZERO
	var bob := 0.0
	var arm_target := 0.0

	if attached:
		# Swing stance: left leg raised and bent at the knee, right leg pointed down,
		# arm out of the cloak gripping the rope, body leaning toward the hook.
		var to_anchor := (anchor - global_position).normalized()
		var local := global_basis.inverse() * to_anchor
		# lean toward the hook sideways, but tilt back a little so the front hem lifts off the raised knee
		lean = Vector3(clampf(atan2(local.z, local.y) * 0.35, -0.6, 0.6) + 0.45, 0, clampf(-atan2(local.x, local.y) * 0.5, -0.7, 0.7))
		ll = Vector3(1.05 + sin(_t * 2.5) * 0.08, 0, -0.3)
		kl = Vector3(-2.0, 0, 0)
		lr = Vector3(-0.15 + sin(_t * 2.5 + 1.0) * 0.06, 0, 0.05)
		kr = Vector3(-0.05, 0, 0)
		head_rot = Vector3(-0.15, 0, 0)
		arm_target = 1.0
	elif on_floor:
		# Quick tip-toe steps
		var run := clampf(hs / 6.0, 0.0, 1.0)
		_phase += hs * dt * 2.6
		var s := sin(_phase)
		var c := cos(_phase)
		lean = Vector3(-0.18 * run, 0, sin(_phase) * 0.06 * run)
		ll = Vector3(s * 0.7 * run, 0, 0)
		lr = Vector3(-s * 0.7 * run, 0, 0)
		kl = Vector3(-max(0.0, -c) * 1.1 * run, 0, 0)
		kr = Vector3(-max(0.0, c) * 1.1 * run, 0, 0)
		bob = abs(s) * 0.05 * run + sin(_t * 2.0) * 0.008 * (1.0 - run)
		head_rot = Vector3(0.08 * run, 0, sin(_t * 0.9) * 0.05 * (1.0 - run))   # idle head tilt
	elif vel.y > 0.5:
		# Rising: one knee tucked, toe pointed
		lean = Vector3(-0.1, 0, 0)
		ll = Vector3(1.0, 0, -0.05)
		kl = Vector3(-1.6, 0, 0)
		lr = Vector3(-0.2, 0, 0.05)
		head_rot = Vector3(-0.1, 0, 0)
	else:
		# Falling: legs together, pointed down, cloak flaring
		lean = Vector3(0.08, 0, 0)
		ll = Vector3(0.1, 0, -0.08)
		lr = Vector3(-0.05, 0, 0.08)
		kl = Vector3(-0.2, 0, 0)
		kr = Vector3(-0.1, 0, 0)
		head_rot = Vector3(0.1, 0, 0)

	_ease(body, lean, k)
	_ease(head, head_rot, k)
	_ease(leg_l, ll, k)
	_ease(leg_r, lr, k)
	_ease(knee_l, kl, k)
	_ease(knee_r, kr, k)
	body.position.y = lerp(body.position.y, -0.45 + bob, k)
	# legs ride with the body lean so the hips stay tucked under the cloak
	leg_l.position.y = -0.5 + bob
	leg_r.position.y = -0.5 + bob

	# Arm slides out of the cloak when hooked and points up the rope
	_arm_out = lerp(_arm_out, arm_target, 1.0 - exp(-16.0 * dt))
	arm.scale = Vector3.ONE * max(_arm_out, 0.01)
	arm.visible = _arm_out > 0.05
	if attached:
		var dir := (cloak.global_basis.inverse() * (anchor - arm.global_position)).normalized()
		arm.basis = Basis(Quaternion(Vector3.DOWN, dir)).scaled(Vector3.ONE * max(_arm_out, 0.01))

	# Cloak hem: flares with speed and when falling, flutters
	var sf := clampf(speed / 16.0, 0.0, 1.0)
	var lift := clampf(-vel.y / 12.0, 0.0, 1.0) if not on_floor else 0.0
	for i in hem.size():
		var flutter := sin(_t * (10.0 + i) + i * 1.7) * (0.06 + 0.25 * sf)
		var target := -(0.25 + sf * 0.35 + lift * 0.6 + (0.75 if attached else 0.0) + flutter)   # negative = flare outward
		hem[i].rotation.x = lerp_angle(hem[i].rotation.x, target, 1.0 - exp(-10.0 * dt))

	# Eyes: occasional blink; wide-eyed surprise on a long fall
	_blink_t -= dt
	var blink := 0.0
	if _blink_t < 0.12:
		blink = 1.0
		if _blink_t < 0.0:
			_blink_t = randf_range(2.5, 5.0)
	_surprise = lerp(_surprise, 1.0 if (not on_floor and not attached and vel.y < -12.0) else 0.0, 1.0 - exp(-6.0 * dt))
	for i in eyes.size():
		lids[i].position.y = lerp(0.08 + 0.03 * _surprise, 0.0, blink)
		lids[i].scale.y = 1.0 + blink * 3.4
		pupils[i].scale = Vector3.ONE * (1.0 - 0.35 * _surprise)


func _ease(n: Node3D, target: Vector3, k: float) -> void:
	n.rotation = Vector3(
		lerp_angle(n.rotation.x, target.x, k),
		lerp_angle(n.rotation.y, target.y, k),
		lerp_angle(n.rotation.z, target.z, k))
