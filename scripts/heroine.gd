extends Node3D
## The heroine: a tall, lithe thief with a big faceted anime head of lavender
## hair, sleepy glowing eyes, a cone cloak that swallows her torso and arms,
## and long slim legs that taper to points like a ballerina's.
##
## Faces -Z. Origin is the centre of the player's 1.8 m capsule (feet at y = -0.9).
##
## The head is built straight from the 2D concept sheet: every head point below
## is in the sheet's units (x 0..300 left to right, y downward, chin at y = 222),
## and H() turns them into metres. The face is a tiny painted texture, the way
## PS1 games did faces, rasterised from the same concept shapes.

const HAIR := Color(0.79, 0.78, 0.93)        # #c9c6ee
const HAIR_SHADE := Color(0.71, 0.69, 0.89)  # #b4b0e2
const SKIN := Color(0.913, 0.725, 0.576)     # #e9b993
const CLOAK := Color(0.36, 0.20, 0.38)
const CLOAK_DARK := Color(0.26, 0.14, 0.28)
const COPPER := Color(0.85, 0.55, 0.28)
const LEGS := Color(0.82, 0.80, 0.90)        # pale ballet tights
const GLOVE := Color(0.25, 0.17, 0.12)
const WATCH_BRASS := Color(0.86, 0.66, 0.30)
const WATCH_FACE := Color(1.0, 0.94, 0.78)
const HOVER := Vector3(0.42, 0.70, 0.08)   # where the arrowhead floats: above her right shoulder

const S := 0.0022          # metres per concept-sheet unit (head is ~0.48 m wide)
const FACE_W := 48         # face texture size in pixels
const FACE_H := 35

var body: Node3D           # hips upward; leans and bobs
var cloak: Node3D
var head: Node3D
var hem: Array[Node3D] = []
var leg_l: Node3D
var leg_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var arm: Node3D            # the one arm that comes out of the cloak to hold the rope
var hand: Node3D
var face_mi: MeshInstance3D
var watch: Node3D
var hour_hand: Node3D
var minute_hand: Node3D
var _face_mats := {}
var _expr := ""

var _t := 0.0
var _phase := 0.0
var _squash := 0.0
var _was_floor := true
var _facing := 0.0
var _arm_out := 0.0
var _blink_t := 2.0
var _surprise := 0.0


func _ready() -> void:
	var legs := PS1.lit_char(LEGS)
	var copper := PS1.lit_char(COPPER)
	var cloth := PS1.lit_char(CLOAK, "cloth", 0.5)

	body = _pivot(self, Vector3(0, -0.02, 0))

	# --- long slim legs: thigh, shin, copper point. Feet tips at y = -0.9.
	leg_l = _pivot(self, Vector3(0.065, -0.02, 0))
	leg_r = _pivot(self, Vector3(-0.065, -0.02, 0))
	for leg in [leg_l, leg_r]:
		_cyl(leg, 0.05, 0.038, 0.42, Vector3(0, -0.21, 0), legs, 5)
	knee_l = _pivot(leg_l, Vector3(0, -0.42, 0))
	knee_r = _pivot(leg_r, Vector3(0, -0.42, 0))
	for k in [knee_l, knee_r]:
		_cyl(k, 0.038, 0.015, 0.38, Vector3(0, -0.19, 0), legs, 5)
		_cyl(k, 0.015, 0.0, 0.08, Vector3(0, -0.42, 0), copper, 5)

	# --- cone cloak from the neck to mid-thigh, ragged hem
	cloak = _pivot(body, Vector3(0, 0.42, 0))
	_cyl(cloak, 0.085, 0.25, 0.68, Vector3(0, -0.34, 0), cloth, 8)
	_cyl(cloak, 0.08, 0.23, 0.64, Vector3(0, -0.34, 0), PS1.lit_char(CLOAK_DARK), 8).scale = Vector3(-1, 1, 1)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var flap := _pivot(cloak, Vector3(sin(a) * 0.235, -0.67, cos(a) * 0.235))
		flap.rotation.y = a
		var tri := _cyl(flap, 0.1, 0.0, 0.12, Vector3(0, -0.06, 0), cloth, 3)
		tri.scale = Vector3(1, 1, 0.35)
		hem.append(flap)
	# hood bunched at the neck as a collar, copper clasp, a sliver of neck
	_cyl(cloak, 0.12, 0.15, 0.08, Vector3(0, -0.03, 0), PS1.lit_char(CLOAK.lightened(0.12), "cloth", 0.5), 8)
	_box(cloak, Vector3(0.05, 0.05, 0.03), Vector3(0, -0.05, -0.145), copper)
	_cyl(cloak, 0.035, 0.04, 0.08, Vector3(0, 0.02, 0.0), PS1.lit_char(SKIN, "", 2.0, 0.5), 6)

	# --- the arm that slides out of the cloak to fire and hold the rope
	arm = _pivot(cloak, Vector3(0.12, -0.12, -0.03))
	_cyl(arm, 0.042, 0.048, 0.42, Vector3(0, -0.21, 0), cloth, 5)
	hand = _pivot(arm, Vector3(0, -0.44, 0))
	_box(hand, Vector3(0.07, 0.08, 0.07), Vector3.ZERO, PS1.lit_char(GLOVE))
	arm.scale = Vector3.ONE * 0.01
	arm.visible = false

	# --- pocket watch resting on the front-left of her cloak at the waist
	_build_watch()

	# --- head
	head = _pivot(cloak, Vector3(0, 0.03, 0.02))
	_build_head()
	set_expression("neutral")


# ============================================================ pocket watch
func _build_watch() -> void:
	var th := -0.6                       # front-left, same angle the chain starts from
	var y := -0.33                       # cloak-local: about waist height
	var r := 0.085 + 0.33 / 0.68 * 0.165 + 0.018   # cone radius here, plus a hair
	watch = _pivot(cloak, Vector3(sin(th) * r, y, -cos(th) * r))
	watch.rotation = Vector3(-0.24, -th, 0)       # face outward, tilted to sit on the cone
	var brass := PS1.lit_char(WATCH_BRASS, "", 2.0, 0.55)
	var case_ := _cyl(watch, 0.07, 0.07, 0.03, Vector3.ZERO, brass, 10)
	case_.rotation.x = PI * 0.5
	var face := _cyl(watch, 0.056, 0.056, 0.032, Vector3(0, 0, -0.002), PS1.unlit(WATCH_FACE), 10)
	face.rotation.x = PI * 0.5
	var ink := PS1.unlit(Color(0.12, 0.08, 0.14))
	for i in 4:   # 12, 3, 6, 9 marks
		var a := TAU * i / 4.0
		_box(watch, Vector3(0.008, 0.016, 0.004), Vector3(sin(a) * 0.044, cos(a) * 0.044, -0.019), ink).rotation.z = -a
	hour_hand = _pivot(watch, Vector3(0, 0, -0.02))
	_box(hour_hand, Vector3(0.01, 0.028, 0.004), Vector3(0, 0.014, 0), ink)
	minute_hand = _pivot(watch, Vector3(0, 0, -0.021))
	_box(minute_hand, Vector3(0.007, 0.042, 0.004), Vector3(0, 0.021, 0), ink)
	# crown and bow on top, where the chain is fastened
	_cyl(watch, 0.012, 0.012, 0.022, Vector3(0, 0.079, 0), brass, 6)
	_box(watch, Vector3(0.036, 0.03, 0.01), Vector3(0, 0.1, 0), brass)


## The bow ring the chain is fastened to (world space).
func watch_ring() -> Vector3:
	return watch.to_global(Vector3(0, 0.1, 0))


## Where the arrowhead floats when stowed (world space).
func hover_point() -> Vector3:
	return global_transform * (HOVER + Vector3(0, sin(_t * 2.1) * 0.025, 0))


## 0..1: how far her hand has reached out to grip the chain.
func grab_amount() -> float:
	return clampf(_arm_out, 0.0, 1.0)


# ============================================================ head
## Concept-sheet point -> metres in head space. z is in sheet units too (- is forward).
## Sheet x grows to the viewer's right, which is her left (world -X when she faces -Z).
func H(x: float, y: float, z: float) -> Vector3:
	return Vector3(-(x - 150.0) * S, (222.0 - y) * S, z * S)


func _build_head() -> void:
	var hair := SurfaceTool.new()
	hair.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shade := SurfaceTool.new()
	shade.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Hair cap: an 8-sided faceted shell with a ridge down the middle (the
	# concept's light/dark top facets). Rings: [sheet y, half width, front depth, back depth, centre z]
	# Front depth shrinks below the bangs so the face sits proud of the hair.
	var rings := [
		[38.0, 8.0, 3.0, 3.0, 8.0],
		[72.0, 86.0, 71.0, 79.0, 8.0],
		[110.0, 104.0, 67.0, 92.0, 8.0],
		[140.0, 108.0, 38.0, 96.0, 8.0],
		[200.0, 96.0, 33.0, 88.0, 12.0],
		[232.0, 70.0, 21.0, 67.0, 25.0],
	]
	var pts := []
	for r in rings:
		var ring := []
		for k in 8:
			var th := TAU * k / 8.0
			var sn := sin(th)
			var depth: float = r[2] if sn < 0.0 else r[3]
			ring.append(H(150.0 + r[1] * cos(th), r[0], r[4] + depth * sn))
		pts.append(ring)
	for i in pts.size() - 1:
		var axis := H(150.0, (rings[i][0] + rings[i + 1][0]) * 0.5, (rings[i][4] + rings[i + 1][4]) * 0.5)
		for k in 8:
			var a: Vector3 = pts[i][k]
			var b: Vector3 = pts[i][(k + 1) % 8]
			var c: Vector3 = pts[i + 1][(k + 1) % 8]
			var d: Vector3 = pts[i + 1][k]
			var out := (a + b + c + d) * 0.25 - axis
			_tri(hair, a, b, c, out)
			_tri(hair, a, c, d, out)
	var top := H(150.0, 34.0, 8.0)
	var bottom := H(150.0, 238.0, 25.0)
	for k in 8:
		_tri(hair, top, pts[0][k], pts[0][(k + 1) % 8], Vector3.UP)
		_tri(hair, bottom, pts[-1][k], pts[-1][(k + 1) % 8], Vector3.DOWN)

	# Bangs: straight-cut fringe with three notches, curving back at the edges
	var bangs := PackedVector2Array([
		Vector2(78, 90), Vector2(222, 90), Vector2(222, 138), Vector2(198, 138), Vector2(192, 126),
		Vector2(186, 140), Vector2(160, 140), Vector2(154, 128), Vector2(148, 140), Vector2(116, 140),
		Vector2(110, 128), Vector2(104, 138), Vector2(78, 138)])
	_extrude(hair, bangs, func(x, _y): return -71.0 + 0.00405 * pow(x - 150.0, 2.0), 17.0)

	# Long side locks framing the face, hanging past the jaw
	_extrude(shade, PackedVector2Array([Vector2(70, 118), Vector2(98, 118), Vector2(94, 238), Vector2(80, 254), Vector2(64, 200)]),
		func(x, _y): return -54.0 + (98.0 - x) * 0.5, 12.0)
	_extrude(shade, PackedVector2Array([Vector2(230, 118), Vector2(202, 118), Vector2(206, 238), Vector2(220, 254), Vector2(236, 200)]),
		func(x, _y): return -54.0 + (x - 202.0) * 0.5, 12.0)
	# Flicks sticking out at the sides, swept back
	_extrude(shade, PackedVector2Array([Vector2(250, 126), Vector2(290, 146), Vector2(256, 162)]),
		func(x, _y): return (x - 250.0) * 0.4, 16.0)
	_extrude(shade, PackedVector2Array([Vector2(50, 126), Vector2(10, 146), Vector2(44, 162)]),
		func(x, _y): return (50.0 - x) * 0.4, 16.0)

	var hair_mesh := ArrayMesh.new()
	hair.commit(hair_mesh)
	shade.commit(hair_mesh)
	var hmi := MeshInstance3D.new()
	hmi.mesh = hair_mesh
	hmi.set_surface_override_material(0, PS1.lit_char(HAIR, "", 2.0, 0.4))
	hmi.set_surface_override_material(1, PS1.lit_char(HAIR_SHADE, "", 2.0, 0.4))
	hmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(hmi)

	# Face: the concept's V-chin outline, pushed slightly forward in the middle.
	# Front is textured (surface 0), the sides that tuck under the hair are skin (surface 1).
	var outline := [Vector2(82, 118), Vector2(218, 118), Vector2(222, 170), Vector2(200, 205),
		Vector2(150, 222), Vector2(100, 205), Vector2(78, 170)]
	var rim_z := [-44.0, -44.0, -44.0, -45.0, -47.0, -45.0, -44.0]
	var centre := Vector2(150, 168)
	var front := SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cv := H(centre.x, centre.y, -58.0)
	var n := outline.size()
	for i in n:
		var j := (i + 1) % n
		var pa: Vector2 = outline[i]
		var pb: Vector2 = outline[j]
		_tri(front, cv, H(pa.x, pa.y, rim_z[i]), H(pb.x, pb.y, rim_z[j]), Vector3.FORWARD,
			_face_uv(centre), _face_uv(pa), _face_uv(pb))
		# side wall back to z = +8, tucked in by 8%
		var ba := H(150.0 + (pa.x - 150.0) * 0.92, pa.y, 8.0)
		var bb := H(150.0 + (pb.x - 150.0) * 0.92, pb.y, 8.0)
		var d := pb - pa
		var out := Vector3(-d.y, d.x, 0.0)   # outward normal of a clockwise sheet outline, in world axes
		_tri(sides, H(pa.x, pa.y, rim_z[i]), H(pb.x, pb.y, rim_z[j]), bb, out)
		_tri(sides, H(pa.x, pa.y, rim_z[i]), bb, ba, out)
		_tri(sides, H(150.0, 170.0, 8.0), ba, bb, Vector3.BACK)
	var face_mesh := ArrayMesh.new()
	front.commit(face_mesh)
	sides.commit(face_mesh)
	face_mi = MeshInstance3D.new()
	face_mi.mesh = face_mesh
	face_mi.set_surface_override_material(1, PS1.lit_char(SKIN, "", 2.0, 0.5))
	face_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(face_mi)


func _face_uv(p: Vector2) -> Vector2:
	return Vector2((p.x - 78.0) / 144.0, (p.y - 118.0) / 104.0)


## Adds a flat-shaded triangle whose normal points along `hint` (outward).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, hint: Vector3,
		ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
	var nrm := (b - a).cross(c - a)
	if nrm.length_squared() < 1e-14:
		return
	if nrm.dot(hint) < 0.0:
		var t := b
		b = c
		c = t
		var tu := ub
		ub = uc
		uc = tu
		nrm = -nrm
	nrm = nrm.normalized()
	# Godot treats clockwise triangles as front-facing
	st.set_normal(nrm)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.set_uv(uc)
	st.add_vertex(c)
	st.set_normal(nrm)
	st.set_uv(ub)
	st.add_vertex(b)


## Extrudes a flat concept-sheet polygon backward by `depth` sheet units.
## `zf(x, y)` gives the front surface depth at each outline point.
func _extrude(st: SurfaceTool, poly: PackedVector2Array, zf: Callable, depth: float) -> void:
	var idx := Geometry2D.triangulate_polygon(poly)
	var n := poly.size()
	var fr := []
	var bk := []
	for p in poly:
		var z: float = zf.call(p.x, p.y)
		fr.append(H(p.x, p.y, z))
		bk.append(H(p.x, p.y, z + depth))
	for i in range(0, idx.size(), 3):
		_tri(st, fr[idx[i]], fr[idx[i + 1]], fr[idx[i + 2]], Vector3.FORWARD)
		_tri(st, bk[idx[i]], bk[idx[i + 1]], bk[idx[i + 2]], Vector3.BACK)
	var area := 0.0
	for i in n:
		var j := (i + 1) % n
		area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
	for i in n:
		var j := (i + 1) % n
		var d := poly[j] - poly[i]
		var o2 := Vector2(d.y, -d.x) if area > 0.0 else Vector2(-d.y, d.x)
		var hint := Vector3(-o2.x, -o2.y, 0.0)   # sheet axes -> world axes
		_tri(st, fr[i], fr[j], bk[j], hint)
		_tri(st, fr[i], bk[j], bk[i], hint)


# ============================================================ face texture
## Expressions: "neutral", "blink", "surprised".
func set_expression(expr: String) -> void:
	if expr == _expr:
		return
	_expr = expr
	if not _face_mats.has(expr):
		var m := ShaderMaterial.new()
		m.shader = PS1.LIT
		m.set_shader_parameter("tex", ImageTexture.create_from_image(_paint_face(expr)))
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("use_uv", true)
		m.set_shader_parameter("self_glow", 0.4)
		m.set_shader_parameter("glow_mask", true)
		m.set_shader_parameter("glow_strength", 0.55)
		_face_mats[expr] = m
	face_mi.set_surface_override_material(0, _face_mats[expr])


func _paint_face(expr: String) -> Image:
	var img := Image.create(FACE_W, FACE_H, false, Image.FORMAT_RGBA8)
	img.fill(SKIN)
	var layers := _face_layers(expr)
	for py in FACE_H:
		for px in FACE_W:
			var p := Vector2(78.0 + (px + 0.5) * 144.0 / FACE_W, 118.0 + (py + 0.5) * 104.0 / FACE_H)
			for L in layers:
				if Geometry2D.is_point_in_polygon(p, L[0]):
					var c: Color = L[1]
					c.a = 1.0 - L[2]   # alpha encodes glow for the shader
					img.set_pixel(px, py, c)
	return img


## Each layer: [polygon in sheet units, colour, glow 0..1]. Later layers paint over earlier ones.
func _face_layers(expr: String) -> Array:
	var sclera := Color8(255, 220, 140)
	var pupil := Color8(42, 22, 48)
	var lid := Color8(26, 16, 32)
	var shine := Color8(255, 195, 90)
	var blush := Color8(233, 159, 142)
	var mouth := Color8(122, 46, 46)
	var L := []
	L.append([_ellipse(108, 194, 11, 5), blush, 0.0])
	L.append([_ellipse(192, 194, 11, 5), blush, 0.0])
	match expr:
		"blink":
			for ox in [0.0, 60.0]:
				L.append([_quad(98 + ox, 163, 144 + ox, 161, 144 + ox, 168, 98 + ox, 170), lid, 0.0])
		"surprised":
			L.append([_quad(100, 148, 140, 148, 138, 181, 104, 182), sclera, 1.0])
			L.append([_quad(160, 148, 200, 148, 196, 182, 162, 181), sclera, 1.0])
			L.append([_quad(110, 155, 132, 155, 130, 176, 112, 177), pupil, 0.0])
			L.append([_quad(168, 155, 190, 155, 188, 177, 170, 176), pupil, 0.0])
			L.append([_rect(113, 158, 119, 164), shine, 1.0])
			L.append([_rect(171, 158, 177, 164), shine, 1.0])
			L.append([_quad(98, 141, 142, 141, 142, 146, 98, 147), lid, 0.0])
			L.append([_quad(158, 141, 202, 141, 202, 147, 158, 146), lid, 0.0])
		_:
			# sleepy side-glance: heavy flat lids, big pupils pushed to the viewer's right
			L.append([_quad(100, 152, 140, 152, 138, 178, 104, 180), sclera, 1.0])
			L.append([_quad(160, 152, 200, 152, 196, 180, 162, 178), sclera, 1.0])
			L.append([_quad(114, 153, 139, 153, 137, 178, 116, 179), pupil, 0.0])
			L.append([_quad(174, 153, 199, 153, 195, 179, 176, 178), pupil, 0.0])
			L.append([_rect(117, 158, 123, 164), shine, 1.0])
			L.append([_rect(177, 158, 183, 164), shine, 1.0])
			L.append([_quad(96, 145, 144, 145, 144, 156, 96, 158), lid, 0.0])
			L.append([_quad(156, 145, 204, 145, 204, 158, 156, 156), lid, 0.0])
	if expr == "surprised":
		L.append([_rect(146, 203, 154, 212), mouth, 0.0])
	else:
		L.append([_stroke(Vector2(142, 210), Vector2(150, 203), 3.4), mouth, 0.0])
		L.append([_stroke(Vector2(150, 203), Vector2(158, 210), 3.4), mouth, 0.0])
	return L


static func _quad(ax, ay, bx, by, cx, cy, dx, dy) -> PackedVector2Array:
	return PackedVector2Array([Vector2(ax, ay), Vector2(bx, by), Vector2(cx, cy), Vector2(dx, dy)])


static func _rect(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	return _quad(x0, y0, x1, y0, x1, y1, x0, y1)


static func _ellipse(cx: float, cy: float, rx: float, ry: float, seg := 12) -> PackedVector2Array:
	var p := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		p.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return p


static func _stroke(a: Vector2, b: Vector2, w: float) -> PackedVector2Array:
	var d := (b - a).normalized()
	var o := Vector2(-d.y, d.x) * w * 0.5
	return PackedVector2Array([a + o, b + o, b - o, a - o])


# ============================================================ mesh helpers
func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var nd := Node3D.new()
	nd.position = pos
	parent.add_child(nd)
	return nd


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


func hand_position() -> Vector3:
	return hand.global_position


# ============================================================ animation
## Called every frame by the player. `idle` (0..1) ramps up after she has stood
## still for a moment; she then turns to face the camera at `cam_pos`.
func animate(dt: float, vel: Vector3, on_floor: bool, attached: bool, anchor: Vector3,
		cam_pos := Vector3.ZERO, idle := 0.0) -> void:
	_t += dt
	var k := 1.0 - exp(-14.0 * dt)
	var hvel := Vector3(vel.x, 0, vel.z)
	var hs := hvel.length()
	var speed := vel.length()

	if hs > 0.6:
		_facing = lerp_angle(_facing, atan2(-hvel.x, -hvel.z), 1.0 - exp(-10.0 * dt))
	elif idle > 0.0:
		var d := cam_pos - global_position
		_facing = lerp_angle(_facing, atan2(-d.x, -d.z), (1.0 - exp(-4.0 * dt)) * idle)
	global_rotation = Vector3(0, _facing, 0)

	# light landing hop
	if on_floor and not _was_floor:
		_squash = 1.0
	_was_floor = on_floor
	_squash = max(_squash - dt * 6.0, 0.0)
	scale = Vector3(1.0 + 0.06 * _squash, 1.0 - 0.09 * _squash, 1.0 + 0.06 * _squash)

	var lean := Vector3.ZERO
	var head_rot := Vector3.ZERO
	var ll := Vector3.ZERO
	var lr := Vector3.ZERO
	var kl := Vector3.ZERO
	var kr := Vector3.ZERO
	var bob := 0.0
	var arm_target := 0.0

	if attached:
		# Swing stance: one leg pointed straight down, the other raised and bent
		# at the knee (a ballet passé), arm out of the cloak up the rope.
		var to_anchor := (anchor - global_position).normalized()
		var local := global_basis.inverse() * to_anchor
		lean = Vector3(clampf(atan2(local.z, local.y) * 0.4, -0.6, 0.6) + 0.12, 0, clampf(-atan2(local.x, local.y) * 0.45, -0.6, 0.6))
		ll = Vector3(1.2 + sin(_t * 2.5) * 0.07, 0, -0.3)
		kl = Vector3(-2.2, 0, 0)
		lr = Vector3(-0.1 + sin(_t * 2.5 + 1.0) * 0.05, 0, 0.04)
		kr = Vector3(-0.03, 0, 0)
		head_rot = Vector3(-0.12, 0, 0)
		arm_target = 1.0
	elif on_floor:
		# quick, light tip-toe steps on long legs
		var run := clampf(hs / 6.0, 0.0, 1.0)
		_phase += hs * dt * 2.1
		var s := sin(_phase)
		var c := cos(_phase)
		lean = Vector3(-0.14 * run, 0, s * 0.04 * run)
		ll = Vector3(s * 0.6 * run, 0, 0)
		lr = Vector3(-s * 0.6 * run, 0, 0)
		kl = Vector3(-max(0.0, -c) * 1.2 * run, 0, 0)
		kr = Vector3(-max(0.0, c) * 1.2 * run, 0, 0)
		bob = abs(s) * 0.04 * run + sin(_t * 2.0) * 0.006 * (1.0 - run)
		head_rot = Vector3(0.06 * run - 0.05 * idle, 0, sin(_t * 0.9) * 0.06 * (1.0 - run))
	elif vel.y > 0.5:
		lean = Vector3(-0.08, 0, 0)
		ll = Vector3(0.9, 0, -0.05)
		kl = Vector3(-1.7, 0, 0)
		lr = Vector3(-0.15, 0, 0.04)
		head_rot = Vector3(-0.08, 0, 0)
	else:
		lean = Vector3(0.06, 0, 0)
		ll = Vector3(0.08, 0, -0.06)
		lr = Vector3(-0.04, 0, 0.06)
		kl = Vector3(-0.15, 0, 0)
		kr = Vector3(-0.08, 0, 0)
		head_rot = Vector3(0.08, 0, 0)

	_ease(body, lean, k)
	_ease(head, head_rot, k)
	_ease(leg_l, ll, k)
	_ease(leg_r, lr, k)
	_ease(knee_l, kl, k)
	_ease(knee_r, kr, k)
	body.position.y = lerp(body.position.y, -0.02 + bob, k)
	leg_l.position.y = -0.02 + bob
	leg_r.position.y = -0.02 + bob

	# arm slides out of the cloak when hooked and points up the rope
	_arm_out = lerp(_arm_out, arm_target, 1.0 - exp(-16.0 * dt))
	arm.visible = _arm_out > 0.05
	if attached:
		var dir := (cloak.global_basis.inverse() * (anchor - arm.global_position)).normalized()
		arm.basis = Basis(Quaternion(Vector3.DOWN, dir)).scaled(Vector3.ONE * max(_arm_out, 0.01))
	else:
		arm.scale = Vector3.ONE * max(_arm_out, 0.01)

	# cloak hem flares with speed and when falling, flutters
	var sf := clampf(speed / 16.0, 0.0, 1.0)
	var lift := clampf(-vel.y / 12.0, 0.0, 1.0) if not on_floor else 0.0
	for i in hem.size():
		var flutter := sin(_t * (10.0 + i) + i * 1.7) * (0.06 + 0.25 * sf)
		var target := -(0.2 + sf * 0.35 + lift * 0.6 + (0.3 if attached else 0.0) + flutter)
		hem[i].rotation.x = lerp_angle(hem[i].rotation.x, target, 1.0 - exp(-10.0 * dt))

	# watch keeps real time, and swings a little on its bow
	var now := Time.get_time_dict_from_system()
	var mins: float = now.minute + now.second / 60.0
	minute_hand.rotation.z = -TAU * mins / 60.0
	hour_hand.rotation.z = -TAU * (fmod(float(now.hour), 12.0) + mins / 60.0) / 12.0
	watch.rotation.z = sin(_t * 3.0) * 0.08 * clampf(speed / 6.0, 0.2, 1.0)

	# face: blink every few seconds, wide eyes on a long fall
	_surprise = lerp(_surprise, 1.0 if (not on_floor and not attached and vel.y < -9.0) else 0.0, 1.0 - exp(-6.0 * dt))
	_blink_t -= dt
	if _blink_t < 0.0:
		_blink_t = randf_range(2.5, 5.0)
	if _surprise > 0.5:
		set_expression("surprised")
	elif _blink_t < 0.12:
		set_expression("blink")
	else:
		set_expression("neutral")


func _ease(nd: Node3D, target: Vector3, k: float) -> void:
	nd.rotation = Vector3(
		lerp_angle(nd.rotation.x, target.x, k),
		lerp_angle(nd.rotation.y, target.y, k),
		lerp_angle(nd.rotation.z, target.z, k))
