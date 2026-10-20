class_name PS1
## Shared PS1-style materials and tiny procedural textures (32x32, nearest filtered).

const LIT := preload("res://shaders/ps1.gdshader")
const UNLIT := preload("res://shaders/ps1_unlit.gdshader")
const GLOW := preload("res://shaders/ps1_glow.gdshader")

static var _mats := {}
static var _texs := {}


## Lit surface. `tex_name` is one of: cobble, plaster, stone, roof, wood, metal, cloth.
static func lit(color: Color, tex_name := "", tile := 2.0) -> ShaderMaterial:
	var key := "L%s%s%s" % [color, tex_name, tile]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = LIT
	m.set_shader_parameter("albedo", color)
	if tex_name != "":
		m.set_shader_parameter("tex", texture(tex_name))
		m.set_shader_parameter("use_tex", true)
		m.set_shader_parameter("tile", tile)
	_mats[key] = m
	return m


## Lit, plus a soft self-glow so a character stays readable at night.
static func lit_char(color: Color, tex_name := "", tile := 2.0, glow := 0.35) -> ShaderMaterial:
	var key := "C%s%s%s%s" % [color, tex_name, tile, glow]
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial = lit(color, tex_name, tile).duplicate()
	m.set_shader_parameter("emission", Color(color.r * glow, color.g * glow, color.b * glow))
	_mats[key] = m
	return m


## Unlit colour. `through_fog` keeps it bright at any distance (lantern flames).
static func unlit(color: Color, through_fog := false) -> ShaderMaterial:
	var key := "U%s%s" % [color, through_fog]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = GLOW if through_fog else UNLIT
	m.set_shader_parameter("albedo", color)
	_mats[key] = m
	return m


static func texture(tex_name: String) -> ImageTexture:
	if _texs.has(tex_name):
		return _texs[tex_name]
	var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(tex_name)
	match tex_name:
		"cobble":
			_bricks(img, rng, 8, 8, Color(0.42, 0.40, 0.38), Color(0.16, 0.14, 0.13), 0.10, true)
		"stone":
			_bricks(img, rng, 16, 8, Color(0.46, 0.46, 0.50), Color(0.22, 0.22, 0.25), 0.07, false)
		"roof":
			_bricks(img, rng, 8, 4, Color(0.50, 0.22, 0.16), Color(0.22, 0.09, 0.07), 0.08, false)
		"plaster":
			for y in 32:
				for x in 32:
					var v := rng.randf_range(-0.05, 0.05)
					img.set_pixel(x, y, Color(0.78 + v, 0.71 + v, 0.58 + v))
			for i in 4:   # a few grimy stains
				var cx := rng.randi_range(0, 31)
				var cy := rng.randi_range(0, 31)
				for k in 10:
					var px := (cx + rng.randi_range(-2, 2)) % 32
					var py := (cy + rng.randi_range(-2, 2)) % 32
					img.set_pixel(px, py, img.get_pixel(px, py).darkened(0.18))
		"wood":
			for x in 32:
				for y in 32:
					var base := Color(0.38, 0.25, 0.14)
					var grain := 0.06 * sin(y * 0.9 + (x / 8) * 2.0 + rng.randf() * 0.6)
					var c := Color(base.r + grain, base.g + grain * 0.8, base.b + grain * 0.5)
					if x % 8 == 0:
						c = c.darkened(0.45)
					img.set_pixel(x, y, c)
		"metal":
			for y in 32:
				for x in 32:
					var v := rng.randf_range(-0.04, 0.04)
					img.set_pixel(x, y, Color(0.22 + v, 0.22 + v, 0.24 + v))
		"cloth":
			for y in 32:
				for x in 32:
					var v := rng.randf_range(-0.05, 0.05) + (0.04 if (x + y) % 4 == 0 else 0.0)
					img.set_pixel(x, y, Color(0.8 + v, 0.8 + v, 0.8 + v))
		_:
			img.fill(Color.WHITE)
	var t := ImageTexture.create_from_image(img)
	_texs[tex_name] = t
	return t


## Brick/cobble pattern: rows of cells with mortar lines and per-cell tint.
static func _bricks(img: Image, rng: RandomNumberGenerator, bw: int, bh: int,
		base: Color, mortar: Color, vary: float, cobble: bool) -> void:
	var tints := {}
	for y in 32:
		var row := y / bh
		var offset := (bw / 2) * (row % 2)
		for x in 32:
			var col := ((x + offset) % 32) / bw
			var key := Vector2i(col, row)
			if not tints.has(key):
				tints[key] = rng.randf_range(-vary, vary)
			var lx := (x + offset) % bw
			var ly := y % bh
			var edge := lx == 0 or ly == 0
			if cobble:
				# round the corners off so cobbles look like stones, not bricks
				edge = edge or (lx <= 1 and ly <= 1) or (lx >= bw - 1 and ly >= bh - 1)
			var n := rng.randf_range(-0.03, 0.03)
			var t: float = tints[key] + n
			var c := mortar if edge else Color(base.r + t, base.g + t, base.b + t)
			if not edge and ly == bh - 1:
				c = c.darkened(0.2)   # shadowed lower lip
			img.set_pixel(x, y, c)
