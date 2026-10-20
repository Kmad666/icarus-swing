extends Node3D
## The heroine's grapple: a floating brass chain that leaves the pocket watch on
## her hip, drifts around her back, and ends in an arrowhead hovering over her
## right shoulder. When she fires, the arrowhead flies to the lantern with the
## chain paying out behind it; when she lets go it zips back and re-coils.
##
## The player owns the hook's position and state (it matters for physics);
## this node only draws it. Links are one MultiMesh, so the whole chain is a
## single draw call however long it gets.

enum { STOWED, FLYING, HOOKED, RETURNING }

const BRASS := Color(0.88, 0.70, 0.36)
const ARROW_BRASS := Color(1.0, 0.82, 0.45)
const LINK_SPACING := 0.085
const MAX_LINKS := 560
const ARROW_LEN := 0.36        # tip to the ring the chain hangs from
const LOOP_SAMPLES := 28

var heroine: Node3D
var _mm: MultiMesh
var _links: MultiMeshInstance3D
var arrow: Node3D
var _t := 0.0
var _tension := 0.0            # 0 = drifting loose, 1 = pulled taut
var _aim := Vector3.FORWARD    # smoothed direction the stowed arrow points


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.mesh = _link_mesh()
	_mm.instance_count = MAX_LINKS
	_mm.visible_instance_count = 0
	_links = MultiMeshInstance3D.new()
	_links.multimesh = _mm
	_links.material_override = PS1.lit_char(BRASS, "", 2.0, 0.6)
	_links.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_links.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	add_child(_links)

	arrow = Node3D.new()
	add_child(arrow)
	var am := MeshInstance3D.new()
	am.mesh = _arrow_mesh()
	am.material_override = PS1.lit_char(ARROW_BRASS, "", 2.0, 0.9)
	am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrow.add_child(am)


## Where the arrow tip rests while stowed, pointing along `aim_dir`.
func stowed_tip(aim_dir: Vector3) -> Vector3:
	return heroine.hover_point() + aim_dir.normalized() * ARROW_LEN


## Called every frame by the player.
## `tip` is the arrow tip in world space; `aim_dir` is where a stowed arrow should point.
func update(dt: float, state: int, tip: Vector3, aim_dir: Vector3) -> void:
	_t += dt
	var taut := state == FLYING or state == HOOKED
	_tension = lerpf(_tension, 1.0 if taut else 0.0, 1.0 - exp(-(14.0 if taut else 5.0) * dt))

	var hover: Vector3 = heroine.hover_point()
	# where the loose loop hands over to the outgoing chain: the hover point,
	# or her hand once she reaches up and grabs it on the swing
	var grab: float = heroine.grab_amount()
	var junction := hover.lerp(heroine.hand_position(), grab)

	# Arrow direction
	var dir: Vector3
	if state == STOWED:
		if aim_dir.length_squared() > 0.0001:
			_aim = _aim.slerp(aim_dir.normalized(), 1.0 - exp(-10.0 * dt)).normalized()
		dir = _aim
		tip = stowed_tip(_aim) + Vector3(0, sin(_t * 2.1) * 0.025, 0)
	else:
		dir = tip - junction
		if dir.length_squared() < 0.0001:
			dir = _aim
		dir = dir.normalized()
		_aim = dir
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	arrow.global_transform = Transform3D(Basis.looking_at(dir, up), tip)
	var tail := tip - dir * ARROW_LEN

	# --- the chain as a polyline: watch -> around her back -> junction -> arrow tail
	var pts := PackedVector3Array()
	var loose := 1.0 - 0.85 * _tension
	var xf: Transform3D = heroine.global_transform
	var watch: Vector3 = heroine.watch_ring()
	var hp_local := xf.affine_inverse() * (junction if state != STOWED else tail)
	var th0 := -0.6                                    # watch sits front-left
	var th1 := atan2(hp_local.x, -hp_local.z) - TAU    # round her left side and back to the right shoulder
	th1 = clampf(th1, th0 - 6.0, th0 - 2.6)
	var loop0 := _loop(0.0, th0, th1, loose)
	var loop1 := _loop(1.0, th0, th1, loose)
	var w_local := xf.affine_inverse() * watch
	for i in LOOP_SAMPLES + 1:
		var s := float(i) / LOOP_SAMPLES
		# blend so the loop starts exactly at the watch and ends exactly at the shoulder
		var p := _loop(s, th0, th1, loose) + (w_local - loop0).lerp(hp_local - loop1, s)
		pts.append(xf * p)
	if state != STOWED:
		# outgoing chain: a ripple travels along it while it flies or recoils
		var seg := tail - pts[pts.size() - 1]
		var length := seg.length()
		var m := clampi(int(length / 0.4), 1, 60)
		var side := seg.cross(Vector3.UP)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		side = side.normalized()
		var ripple := 0.18 * (1.0 - _tension) + (0.0 if state == HOOKED else 0.04)
		var base := pts[pts.size() - 1]
		for j in range(1, m + 1):
			var u := float(j) / m
			var off := side * sin(u * PI * 3.0 - _t * 20.0) * sin(u * PI) * ripple
			pts.append(base + seg * u + off)

	_place_links(pts)


## A point on the drifting loop, in the heroine's local space. s: 0 at the watch, 1 at the shoulder.
func _loop(s: float, th0: float, th1: float, loose: float) -> Vector3:
	var th := lerpf(th0, th1, s)
	var r := lerpf(0.24, 0.38, smoothstep(0.0, 0.35, s)) * lerpf(0.82, 1.0, loose)
	r += sin(_t * 1.6 + s * 10.0) * 0.03 * loose
	# stays low across her back, rises up her right side to the shoulder
	var y := lerpf(0.07, 0.70, pow(s, 2.2)) + sin(s * TAU) * 0.04 * loose + sin(_t * 1.2 + s * 7.0) * 0.035 * loose
	return Vector3(sin(th) * r, y, -cos(th) * r)


func _place_links(pts: PackedVector3Array) -> void:
	var n := 0
	var carried := 0.0
	var next_at := 0.0
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var seg_len := a.distance_to(b)
		if seg_len < 0.0001:
			continue
		var z := (b - a) / seg_len
		var helper := Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
		var x0 := helper.cross(z).normalized()
		var y0 := z.cross(x0)
		while next_at <= carried + seg_len and n < MAX_LINKS:
			var p := a + z * (next_at - carried)
			# every other link turned 90 degrees, like a real chain
			var basis := Basis(x0, y0, z) if n % 2 == 0 else Basis(y0, -x0, z)
			_mm.set_instance_transform(n, Transform3D(basis, p))
			n += 1
			next_at += LINK_SPACING
		carried += seg_len
	_mm.visible_instance_count = n


# ------------------------------------------------------------ meshes
## An oval chain link, long along Z, made of 8 bars.
static func _link_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := 0.056     # half length
	var b := 0.032     # half width
	var w := 0.017     # wire thickness
	for i in 8:
		var t0 := TAU * i / 8.0
		var t1 := TAU * (i + 1) / 8.0
		var p0 := Vector3(cos(t0) * b, 0, sin(t0) * a)
		var p1 := Vector3(cos(t1) * b, 0, sin(t1) * a)
		var d := p1 - p0
		var bar := BoxMesh.new()
		bar.size = Vector3(w, w, d.length() + w * 0.5)
		st.append_from(bar, 0, Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), (p0 + p1) * 0.5))
	return st.commit()


## Diamond arrowhead. Tip at the origin pointing -Z; the body trails back along +Z
## to a small ring at +ARROW_LEN where the chain attaches.
static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := 1.6
	var tip := Vector3.ZERO
	var back := Vector3(0, 0, 0.17 * k)
	var w := 0.07 * k
	var ring := [Vector3(w, 0, 0.075 * k), Vector3(0, w * 0.55, 0.075 * k), Vector3(-w, 0, 0.075 * k), Vector3(0, -w * 0.55, 0.075 * k)]
	for i in 4:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 4]
		_face(st, tip, a, b, (a + b) * 0.5 - Vector3(0, 0, 0.03))
		_face(st, back, a, b, (a + b) * 0.5 + Vector3(0, 0, 0.2))
	# little barbs flaring back from the widest point
	for sx in [-1.0, 1.0]:
		var p := Vector3(sx * w, 0, 0.075 * k)
		_face(st, p, Vector3(sx * w * 1.45, 0, 0.17 * k), Vector3(sx * w * 0.6, 0, 0.13 * k), Vector3(0, 1, 0))
		_face(st, p, Vector3(sx * w * 1.45, 0, 0.17 * k), Vector3(sx * w * 0.6, 0, 0.13 * k), Vector3(0, -1, 0))
	var collar := BoxMesh.new()
	collar.size = Vector3(0.05, 0.05, 0.09)
	st.append_from(collar, 0, Transform3D(Basis(), Vector3(0, 0, 0.17 * k + 0.04)))
	return st.commit()


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(hint) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	for v in [a, c, b]:
		st.set_normal(n)
		st.add_vertex(v)
