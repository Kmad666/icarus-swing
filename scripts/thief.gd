extends Node3D
## Low-poly hooded thief with procedural (code-driven) animation.
## Faces -Z. Origin sits at the centre of the player's 1.8 m collision capsule,
## so the feet are at y = -0.9.
##
## Poses: idle, run, jump, fall, swing, land squash. Cape trails with speed.

const CLOAK := Color(0.30, 0.36, 0.40)
const CLOAK_IN := Color(0.55, 0.16, 0.14)   # cape lining
const TUNIC := Color(0.42, 0.36, 0.28)
const LEATHER := Color(0.55, 0.35, 0.20)
const TROUSERS := Color(0.28, 0.27, 0.30)
const BOOTS := Color(0.22, 0.16, 0.12)
const SKIN_SHADOW := Color(0.03, 0.03, 0.04)
const EYES := Color(0.75, 0.9, 1.0)

var hips: Node3D
var torso: Node3D
var head: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var cape: Array[Node3D] = []
var hand_r: Node3D

var _phase := 0.0
var _t := 0.0
var _squash := 0.0
var _was_floor := true
var _facing := 0.0


func _ready() -> void:
	var cloak := PS1.lit(CLOAK, "cloth", 0.6)
	var lining := PS1.lit(CLOAK_IN, "cloth", 0.6)
	var tunic := PS1.lit(TUNIC, "cloth", 0.6)
	var leather := PS1.lit(LEATHER, "cloth", 0.6)
	var trousers := PS1.lit(TROUSERS, "cloth", 0.6)
	var boots := PS1.lit(BOOTS)

	hips = _pivot(self, Vector3(0, 0.0, 0))

	# --- torso, belt, pouch, shoulder mantle
	torso = _pivot(hips, Vector3(0, 0.05, 0))
	_box(torso, Vector3(0.40, 0.52, 0.24), Vector3(0, 0.28, 0), tunic)
	_box(torso, Vector3(0.43, 0.08, 0.27), Vector3(0, 0.05, 0), leather)          # belt
	_box(torso, Vector3(0.12, 0.13, 0.08), Vector3(0.16, -0.02, -0.12), leather)   # coin pouch
	_box(torso, Vector3(0.06, 0.06, 0.04), Vector3(0.0, 0.05, -0.14), PS1.lit(Color(0.6, 0.5, 0.25)))  # buckle
	var mantle := _cyl(torso, 0.17, 0.33, 0.30, Vector3(0, 0.50, 0), cloak, 6)
	mantle.rotation.y = PI / 6.0
	_box(torso, Vector3(0.05, 0.42, 0.05), Vector3(-0.1, 0.32, 0.14), leather)     # strap across the back
	_box(torso, Vector3(0.5, 0.06, 0.06), Vector3(0, 0.32, 0.15), leather).rotation.z = 0.7

	# --- head: hood with a peak, shadowed face, two pale glinting eyes
	head = _pivot(torso, Vector3(0, 0.66, 0))
	var hood := _sphere(head, 0.21, Vector3(0, 0.12, 0.01), cloak)
	hood.scale = Vector3(1.0, 1.12, 1.15)
	var peak := _cyl(head, 0.0, 0.11, 0.22, Vector3(0, 0.27, 0.10), cloak, 4)
	peak.rotation.x = -0.9
	_box(head, Vector3(0.22, 0.17, 0.06), Vector3(0, 0.08, -0.19), PS1.unlit(SKIN_SHADOW))
	_box(head, Vector3(0.24, 0.05, 0.08), Vector3(0, 0.19, -0.18), cloak)          # hood brim
	for sx in [-1, 1]:
		_box(head, Vector3(0.035, 0.025, 0.02), Vector3(sx * 0.05, 0.1, -0.225), PS1.unlit(EYES))
	# scarf around the lower face
	_box(head, Vector3(0.26, 0.08, 0.22), Vector3(0, 0.0, -0.06), lining)

	# --- arms (sleeve, leather bracer, dark glove)
	shoulder_l = _pivot(torso, Vector3(-0.26, 0.48, 0))
	shoulder_r = _pivot(torso, Vector3(0.26, 0.48, 0))
	for s in [shoulder_l, shoulder_r]:
		_box(s, Vector3(0.13, 0.32, 0.13), Vector3(0, -0.15, 0), cloak)
	elbow_l = _pivot(shoulder_l, Vector3(0, -0.31, 0))
	elbow_r = _pivot(shoulder_r, Vector3(0, -0.31, 0))
	for e in [elbow_l, elbow_r]:
		_box(e, Vector3(0.11, 0.26, 0.11), Vector3(0, -0.13, 0), leather)
		_box(e, Vector3(0.10, 0.10, 0.10), Vector3(0, -0.30, 0), boots)
	hand_r = _pivot(elbow_r, Vector3(0, -0.32, 0))

	# --- legs
	thigh_l = _pivot(hips, Vector3(-0.11, 0.0, 0))
	thigh_r = _pivot(hips, Vector3(0.11, 0.0, 0))
	for th in [thigh_l, thigh_r]:
		_box(th, Vector3(0.15, 0.44, 0.16), Vector3(0, -0.21, 0), trousers)
	knee_l = _pivot(thigh_l, Vector3(0, -0.43, 0))
	knee_r = _pivot(thigh_r, Vector3(0, -0.43, 0))
	for k in [knee_l, knee_r]:
		_box(k, Vector3(0.14, 0.40, 0.15), Vector3(0, -0.2, 0), boots)
		_box(k, Vector3(0.16, 0.08, 0.17), Vector3(0, -0.03, 0), boots)          # boot cuff
		_box(k, Vector3(0.13, 0.07, 0.25), Vector3(0, -0.43, -0.05), boots)       # foot

	# --- cape: three chained panels hanging from the shoulders
	var parent: Node3D = torso
	var y := 0.55
	var widths := [0.52, 0.60, 0.66]
	for i in 3:
		var p := _pivot(parent, Vector3(0, y, 0.15) if i == 0 else Vector3(0, -0.34, 0))
		_box(p, Vector3(widths[i], 0.35, 0.035), Vector3(0, -0.17, 0), cloak)
		_box(p, Vector3(widths[i] - 0.02, 0.33, 0.01), Vector3(0, -0.17, -0.022), lining)
		cape.append(p)
		parent = p
		y = 0.0


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


func _sphere(parent: Node3D, r: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 7
	m.rings = 4
	return _mesh(parent, m, pos, mat)


func hand_position() -> Vector3:
	return hand_r.global_position


## Called every frame by the player.
func animate(dt: float, vel: Vector3, on_floor: bool, attached: bool, anchor: Vector3) -> void:
	_t += dt
	var k := 1.0 - exp(-14.0 * dt)      # smoothing factor
	var hvel := Vector3(vel.x, 0, vel.z)
	var hs := hvel.length()
	var speed := vel.length()

	# Face the direction of travel
	if hs > 0.6:
		_facing = lerp_angle(_facing, atan2(-hvel.x, -hvel.z), 1.0 - exp(-10.0 * dt))
	global_rotation = Vector3(0, _facing, 0)

	# Landing squash
	if on_floor and not _was_floor and vel.y > -50.0:
		_squash = 1.0
	_was_floor = on_floor
	_squash = max(_squash - dt * 5.0, 0.0)
	scale = Vector3(1.0 + 0.12 * _squash, 1.0 - 0.18 * _squash, 1.0 + 0.12 * _squash)

	# Target pose (euler radians per joint); defaults = neutral standing
	var P := {
		"hips": Vector3.ZERO, "torso": Vector3.ZERO, "head": Vector3.ZERO,
		"sl": Vector3(0, 0, -0.08), "sr": Vector3(0, 0, 0.08), "el": Vector3(0.2, 0, 0), "er": Vector3(0.2, 0, 0),
		"tl": Vector3.ZERO, "tr": Vector3.ZERO, "kl": Vector3.ZERO, "kr": Vector3.ZERO,
	}
	var hips_y := 0.0

	if attached:
		# Swing: right arm reaches up the rope, body leans toward the hook, legs trail
		var to_anchor := (anchor - global_position).normalized()
		var local := global_basis.inverse() * to_anchor
		P.hips = Vector3(clampf(atan2(local.z, local.y) * 0.7, -1.0, 1.0), 0, clampf(-atan2(local.x, local.y) * 0.7, -0.9, 0.9))
		var arm_dir := (hips.global_basis * Basis.from_euler(P.hips)).inverse() * to_anchor
		P.sr = Quaternion(Vector3.DOWN, arm_dir.normalized()).get_euler()
		P.er = Vector3.ZERO
		P.sl = Vector3(-0.5, 0, -0.9)
		P.el = Vector3(0.6, 0, 0)
		P.tl = Vector3(-0.35 + sin(_t * 3.0) * 0.1, 0, -0.08)
		P.tr = Vector3(0.25 + sin(_t * 3.0 + 1.5) * 0.1, 0, 0.08)
		P.kl = Vector3(-0.7, 0, 0)
		P.kr = Vector3(-0.35, 0, 0)
	elif on_floor:
		var run := clampf(hs / 6.0, 0.0, 1.0)
		_phase += hs * dt * 1.7
		var s := sin(_phase)
		var c := cos(_phase)
		var breathe := sin(_t * 2.2) * 0.03 * (1.0 - run)
		P.hips = Vector3(-0.22 * run, sin(_phase) * 0.12 * run, 0)
		P.torso = Vector3(breathe, 0, 0)
		P.head = Vector3(0.15 * run - breathe, 0, 0)
		P.tl = Vector3(s * 0.85 * run, 0, 0)
		P.tr = Vector3(-s * 0.85 * run, 0, 0)
		P.kl = Vector3(-max(0.0, -c) * 1.3 * run - 0.05, 0, 0)
		P.kr = Vector3(-max(0.0, c) * 1.3 * run - 0.05, 0, 0)
		P.sl = Vector3(-s * 0.7 * run, 0, -0.08)
		P.sr = Vector3(s * 0.7 * run, 0, 0.08)
		P.el = Vector3(0.3 + 0.6 * run, 0, 0)
		P.er = Vector3(0.3 + 0.6 * run, 0, 0)
		hips_y = abs(s) * 0.06 * run - 0.02 * run + breathe * 0.3
	elif vel.y > 0.5:
		# Rising: knees tucked, arms up
		P.hips = Vector3(-0.15, 0, 0)
		P.tl = Vector3(0.9, 0, -0.05)
		P.tr = Vector3(0.4, 0, 0.05)
		P.kl = Vector3(-1.4, 0, 0)
		P.kr = Vector3(-0.9, 0, 0)
		P.sl = Vector3(1.0, 0, -0.5)
		P.sr = Vector3(1.6, 0, 0.4)
		P.el = Vector3(0.7, 0, 0)
		P.er = Vector3(0.4, 0, 0)
	else:
		# Falling: arms out for balance, legs reaching down
		var flail := sin(_t * 9.0) * 0.12
		P.hips = Vector3(0.05, 0, 0)
		P.tl = Vector3(0.3, 0, -0.15)
		P.tr = Vector3(-0.15, 0, 0.15)
		P.kl = Vector3(-0.5, 0, 0)
		P.kr = Vector3(-0.25, 0, 0)
		P.sl = Vector3(0.3, 0, -1.3 + flail)
		P.sr = Vector3(0.3, 0, 1.3 - flail)
		P.el = Vector3(0.4, 0, 0)
		P.er = Vector3(0.4, 0, 0)

	_ease(hips, P.hips, k)
	_ease(torso, P.torso, k)
	_ease(head, P.head, k)
	_ease(shoulder_l, P.sl, k)
	_ease(shoulder_r, P.sr, k)
	_ease(elbow_l, P.el, k)
	_ease(elbow_r, P.er, k)
	_ease(thigh_l, P.tl, k)
	_ease(thigh_r, P.tr, k)
	_ease(knee_l, P.kl, k)
	_ease(knee_r, P.kr, k)
	hips.position.y = lerp(hips.position.y, hips_y, k)

	# Cape: blown back by speed, lifted when falling, fluttering at the hem
	var sf := clampf(speed / 16.0, 0.0, 1.0)
	var lift := clampf(-vel.y / 14.0, 0.0, 1.0) if not on_floor else 0.0
	var base := -(0.12 + sf * 0.9 + lift * 0.5)
	for i in cape.size():
		var flutter := sin(_t * (9.0 + i * 3.0) - i * 1.2) * (0.05 + 0.18 * sf) * (i + 1) * 0.6
		var target := (base if i == 0 else -0.12 * sf - lift * 0.15) + flutter
		cape[i].rotation.x = lerp_angle(cape[i].rotation.x, target, 1.0 - exp(-10.0 * dt))


func _ease(n: Node3D, target: Vector3, k: float) -> void:
	n.rotation = Vector3(
		lerp_angle(n.rotation.x, target.x, k),
		lerp_angle(n.rotation.y, target.y, k),
		lerp_angle(n.rotation.z, target.z, k))
