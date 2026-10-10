extends RefCounted
## Shared paper/ink treatment for vehicles and the weapons operated by the source soldier.
const Art = preload("res://scripts/ink_art.gd")
const Batch = preload("res://scripts/mesh_batch.gd")
const SURFACE = preload("res://shaders/vehicle_ink.gdshader")
const OUTLINE = preload("res://shaders/character_outline.gdshader")
const SHADOW = preload("res://shaders/vehicle_shadow.gdshader")
const Livery = preload("res://scripts/vehicle_livery.gd")
# Vertex alpha carries a material role (1..9 / 15), never opacity. Tagged sources
# are made opaque before batching; mesh_batch preserves the tag in the final mesh.
const HULL = Color("8c9faf11")
const LIGHT = Color("b3c2d022")
const DARK = Color("35435333")
const STEEL = Color("65758944")
const RUBBER = Color("24253055")
const GLASS = Color("38536e66")
const CLOTH = Color("aaa39777")
const ACCENT = Color("426db688")
const MARK = Color("eee2bd99")
const INK = Color(.28,.25,.35)

static func material(lines: bool = false, team: int = -1) -> ShaderMaterial:
	var m = ShaderMaterial.new()
	m.shader = SURFACE
	m.set_shader_parameter("line_pass",lines)
	Livery.apply(m,team)
	if not lines:
		var outline = ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.set_shader_parameter("width_pixels",.72)
		m.next_pass = outline
	return m

static func recognition(parent: Node3D, at: Vector3, size: Vector2, team: int, normal: Vector3 = Vector3.UP) -> void:
	# Two cream bars for blue, three for red: readable in addition to the body hue.
	var badge=Node3D.new()
	parent.add_child(badge);badge.position=at
	var tangent=(Vector3.FORWARD if absf(normal.x)>.8 else Vector3.RIGHT).slide(normal).normalized()
	badge.basis=Basis(tangent,normal,tangent.cross(normal))
	box(badge,Vector3.ZERO,Vector3(size.x,.008,size.y),ACCENT,false)
	var count=3 if team==1 else 2 if team==0 else 1
	for i in range(count):
		var x=(float(i)-(count-1)*.5)*size.x*.24
		box(badge,Vector3(x,.005,0),Vector3(size.x*.115,.003,size.y*.62),MARK,false)

static func finish_group(group: Node3D, keep: Array, surface: ShaderMaterial, edges: ShaderMaterial) -> void:
	prepare_sources(group,keep)
	for mesh in Batch.collapse(group,keep):
		mesh.material_override = edges if mesh.mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_LINES else surface
	Batch.prune_empty(group,keep)

static func prepare_sources(group: Node, keep: Array) -> void:
	# The general art kit interprets alpha as opacity. Override only our tagged
	# vehicle sources so they enter the opaque rigid batch, without changing it
	# for world objects, character attachments or actual transparent effects.
	for child in group.get_children():
		if child in keep:continue
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var color: Color=child.material_override.albedo_color
			var role=roundi(color.a*15.0)
			if role>=1 and role<=9 and absf(color.a*15.0-role)<.01:
				child.material_override=Art.ink_material(color)
		prepare_sources(child,keep)

static func mesh_part(parent: Node3D, at: Vector3, vertices: PackedVector3Array, normals: PackedVector3Array, color: Color) -> MeshInstance3D:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return Art.mesh_node(parent,mesh,at,color)

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color, rounded: bool = true) -> Node3D:
	# Broad faces and actual small fillets, without a wire cage around every detail.
	if not rounded:
		var flat = BoxMesh.new()
		flat.size = size
		return Art.mesh_node(parent,flat,at,color)
	var half = size*.5
	var radius = minf(.055,minf(half.x,minf(half.y,half.z))*.46)
	var core = half-Vector3.ONE*radius
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:
		var a = Vector3.UP if absf(direction.x)>.5 else Vector3.RIGHT
		var b = direction.cross(a)
		var extent_a = half.dot(a.abs())
		var extent_b = half.dot(b.abs())
		var coordinates_a = [-extent_a,-extent_a+radius,extent_a-radius,extent_a]
		var coordinates_b = [-extent_b,-extent_b+radius,extent_b-radius,extent_b]
		for row in range(3):
			for col in range(3):
				for corner in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(1,0)]:
					var p = direction*half+a*coordinates_a[col+corner.x]+b*coordinates_b[row+corner.y]
					var center = p.clamp(-core,core)
					var normal = (p-center).normalized()
					vertices.append(center+normal*radius)
					normals.append(normal)
	return mesh_part(parent,at,vertices,normals,color)

static func ring_points(size: Vector3, y: float, offset: float, rounding: float) -> Array:
	var points: Array = []
	var half = Vector2(size.x,size.z)*.5
	var radius = minf(half.x,half.y)*rounding
	for corner in range(4):
		var center = Vector2(1 if corner in [1,2] else -1,1 if corner>=2 else -1)*(half-Vector2.ONE*radius)
		for i in range(4):
			var angle = -PI+corner*PI*.5+i*PI/6.0
			var p = center+Vector2.from_angle(angle)*radius
			points.append(Vector3(p.x,y,p.y+offset))
	return points

static func plate(parent: Node3D, at: Vector3, lower: Vector3, upper: Vector3, offset: float, color: Color, rounding: float) -> Node3D:
	# Four rounded rings roll over top/bottom edges while retaining each vehicle's armor slope.
	var lip = minf(.045,minf(upper.y*.15,minf(lower.x,lower.z)*.08))
	var inset = Vector3(lip*1.1,0,lip*1.1)
	var fraction = lip/maxf(.001,upper.y)
	var rings = [ring_points(lower-inset,0,0,rounding),
		ring_points(lower.lerp(upper,fraction),lip,offset*fraction,rounding),
		ring_points(lower.lerp(upper,1.0-fraction),upper.y-lip,offset*(1.0-fraction),rounding),
		ring_points(upper-inset,upper.y,offset,rounding)]
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var count: int = rings[0].size()
	var grid_normals: Array = []
	for row in range(4):
		var row_normals: Array = []
		for col in range(count):
			var around: Vector3 = rings[row][(col+1)%count]-rings[row][posmod(col-1,count)]
			var vertical: Vector3 = rings[mini(3,row+1)][col]-rings[maxi(0,row-1)][col]
			var n = vertical.cross(around).normalized()
			if row==0:n=(n+Vector3.DOWN*.45).normalized()
			if row==3:n=(n+Vector3.UP*.70).normalized()
			row_normals.append(n)
		grid_normals.append(row_normals)
	for row in range(3):
		for col in range(count):
			for index in [Vector2i(row,col),Vector2i(row+1,(col+1)%count),Vector2i(row+1,col),Vector2i(row,col),Vector2i(row,(col+1)%count),Vector2i(row+1,(col+1)%count)]:
				vertices.append(rings[index.x][index.y]);normals.append(grid_normals[index.x][index.y])
	for row in [0,3]:
		for col in range(1,count-1):
			for index in ([0,col+1,col] if row==0 else [0,col,col+1]):
				vertices.append(rings[row][index]);normals.append(Vector3.DOWN if row==0 else Vector3.UP)
	return mesh_part(parent,at,vertices,normals,color)

static func cast_turret(parent: Node3D, at: Vector3, profiles: Array, color: Color) -> Node3D:
	# Smooth normals on broad cast shells, with no polygon seams painted on the dome.
	var soldier_style = preload("res://scripts/soldier_style.gd")
	var closed = profiles.duplicate()
	var first: Vector4 = profiles[0]
	var last: Vector4 = profiles[-1]
	closed.push_front(Vector4(first.x,.001,.001,first.w))
	closed.append(Vector4(last.x,.001,.001,last.w))
	return soldier_style.loft(parent,at,closed,color,28)

static func tire(parent: Node3D, radius: float, width: float, color: Color) -> Node3D:
	var soldier_style = preload("res://scripts/soldier_style.gd")
	return soldier_style.loft(parent,Vector3.ZERO,[Vector4(-width*.5,.001,.001,0),
		Vector4(-width*.5,radius*.76,radius*.76,0),Vector4(-width*.43,radius*.95,radius*.95,0),
		Vector4(-width*.28,radius,radius,0),Vector4(width*.28,radius,radius,0),
		Vector4(width*.43,radius*.95,radius*.95,0),Vector4(width*.5,radius*.76,radius*.76,0),
		Vector4(width*.5,.001,.001,0)],color,24)

static func shadow(parent: Node3D, size: Vector2) -> void:
	var mesh = PlaneMesh.new()
	mesh.size = size*Vector2(1.20,1.12)
	var decal = MeshInstance3D.new()
	decal.name="GroundShadow"
	decal.mesh = mesh
	decal.position.y = .021
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m = ShaderMaterial.new()
	m.shader = SHADOW
	decal.material_override = m
	parent.add_child(decal)
