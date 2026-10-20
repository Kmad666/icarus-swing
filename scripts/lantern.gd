extends Node3D
## Hanging lantern: dark iron cage, glowing glass, flickering flame, real light.
## These are the only things the grapple can hook. The node's origin is the
## hook ring at the top, which is where the rope attaches.

const IRON := Color(0.13, 0.12, 0.13)
const FLAME_CORE := Color(1.0, 0.95, 0.7)
const FLAME_OUTER := Color(1.0, 0.55, 0.12)
const GLASS := Color(0.85, 0.45, 0.12)
const GLASS_TARGET := Color(1.0, 0.85, 0.45)

var chain_length := 0.8
var light: OmniLight3D
var flame: Node3D
var glass: MeshInstance3D
var halo: MeshInstance3D
static var _halo_mats := {}
var targeted := false
var _t := 0.0
var _seed := 0.0


func _init(chain := 0.8) -> void:
	chain_length = chain


func _ready() -> void:
	_seed = randf() * 100.0
	var iron := PS1.lit(IRON, "metal", 0.5)
	var st := SurfaceTool.new()   # every iron piece is merged into one mesh (one draw call)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Hook ring at the origin, then a chain of alternating links down to the cage
	_iron(st, BoxMesh, Vector3(0.14, 0.14, 0.04), Vector3.ZERO)
	var links := int(chain_length / 0.16)
	for i in links:
		_iron(st, BoxMesh, Vector3(0.05, 0.14, 0.05), Vector3(0, -0.12 - i * 0.16, 0), 0.0 if i % 2 == 0 else PI * 0.5)

	var top := -chain_length - 0.1
	# Pyramid cap (4-sided cone), top plate, bottom plate, finial
	_iron(st, CylinderMesh, Vector3(0.04, 0.3, 0.34), Vector3(0, top - 0.12, 0), PI * 0.25)
	_iron(st, BoxMesh, Vector3(0.48, 0.05, 0.48), Vector3(0, top - 0.28, 0))
	_iron(st, BoxMesh, Vector3(0.42, 0.07, 0.42), Vector3(0, top - 0.86, 0))
	_iron(st, CylinderMesh, Vector3(0.12, 0.14, 0.0), Vector3(0, top - 0.96, 0), PI * 0.25)
	# Corner bars and a middle band
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_iron(st, BoxMesh, Vector3(0.05, 0.56, 0.05), Vector3(sx * 0.2, top - 0.57, sz * 0.2))
	_iron(st, BoxMesh, Vector3(0.44, 0.03, 0.44), Vector3(0, top - 0.57, 0))
	var cage := MeshInstance3D.new()
	cage.mesh = st.commit()
	cage.material_override = iron
	cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cage)

	# Glowing amber glass (inside the bars) and the flame
	glass = _part(BoxMesh, Vector3(0.34, 0.5, 0.34), Vector3(0, top - 0.57, 0), PS1.unlit(GLASS))
	flame = Node3D.new()
	flame.position = Vector3(0, top - 0.66, 0)
	add_child(flame)
	var outer := _part(SphereMesh, Vector3(0.09, 0.22, 0), Vector3(0, 0.08, 0), PS1.unlit(FLAME_OUTER, true), flame)
	outer.scale = Vector3(1, 1.6, 1)
	var core := _part(SphereMesh, Vector3(0.05, 0.12, 0), Vector3(0, 0.05, 0), PS1.unlit(FLAME_CORE, true), flame)
	core.scale = Vector3(1, 1.5, 1)

	halo = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 2.2)
	halo.mesh = q
	halo.position = Vector3(0, top - 0.6, 0)
	halo.material_override = _halo_mat(false)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)

	light = OmniLight3D.new()
	light.position = Vector3(0, top - 0.55, 0)
	light.light_color = Color(1.0, 0.62, 0.3)
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	light.light_energy = 1.8
	light.shadow_enabled = false
	light.distance_fade_enabled = true   # far lanterns keep their glow but stop lighting things
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 10.0
	add_child(light)


func _make(mesh_class, dims: Vector3) -> PrimitiveMesh:
	var m: PrimitiveMesh = mesh_class.new()
	if m is BoxMesh:
		m.size = dims
	elif m is CylinderMesh:
		m.top_radius = dims.x
		m.height = dims.y
		m.bottom_radius = dims.z
		m.radial_segments = 4
		m.rings = 1
	return m


func _iron(st: SurfaceTool, mesh_class, dims: Vector3, pos: Vector3, yaw := 0.0) -> void:
	st.append_from(_make(mesh_class, dims), 0, Transform3D(Basis(Vector3.UP, yaw), pos))


func _part(mesh_class, dims: Vector3, pos: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m: PrimitiveMesh = mesh_class.new()
	if m is BoxMesh:
		m.size = dims
	elif m is CylinderMesh:
		m.top_radius = dims.x
		m.height = dims.y
		m.bottom_radius = dims.z
		m.radial_segments = 4
		m.rings = 1
	elif m is SphereMesh:
		m.radius = dims.x
		m.height = dims.y
		m.radial_segments = 5
		m.rings = 3
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


static func _halo_mat(on: bool) -> StandardMaterial3D:
	if _halo_mats.has(on):
		return _halo_mats[on]
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.4, 0.55) if on else Color(1.0, 0.6, 0.25, 0.35))
	g.set_color(1, Color(1.0, 0.5, 0.2, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 16
	gt.height = 16
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.disable_fog = true
	m.no_depth_test = false
	_halo_mats[on] = m
	return m


func set_targeted(on: bool) -> void:
	if on == targeted:
		return
	targeted = on
	glass.material_override = PS1.unlit(GLASS_TARGET if on else GLASS)
	halo.material_override = _halo_mat(on)


func _process(dt: float) -> void:
	_t += dt
	var f := sin(_t * 11.0 + _seed) * 0.5 + sin(_t * 17.3 + _seed * 2.0) * 0.3 + sin(_t * 4.1 + _seed) * 0.2
	var boost := 1.6 if targeted else 1.0
	light.light_energy = (1.8 + f * 0.35) * boost
	flame.scale = Vector3(1.0 - f * 0.08, 1.0 + f * 0.15, 1.0 - f * 0.08) * (1.2 if targeted else 1.0)
	# gentle sway on the chain
	rotation.z = sin(_t * 1.3 + _seed) * 0.04
	rotation.x = sin(_t * 1.1 + _seed * 0.7) * 0.03
