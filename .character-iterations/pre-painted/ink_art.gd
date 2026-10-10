extends RefCounted
## Small reusable procedural asset kit. Units are metres in the view.

const INK = Color("302b43")
const PAPER = Color("e4e1eb")
const BLUE = Color("426db6")
const RED = Color("bd5369")
const STONE = Color("aaa4b9")
const INK_SHADER = preload("res://shaders/ink_surface.gdshader")
const Batch = preload("res://scripts/mesh_batch.gd")
const Layout = preload("res://scripts/house_layout.gd")
static var materials: Dictionary = {}
static var baked_meshes: Dictionary = {}

static func uniform_mesh(parent: Node3D, resource_name: String, color: Color, skeleton: Skeleton3D = null) -> MeshInstance3D:
	if not baked_meshes.has(resource_name):
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/"+resource_name+".mesh.json"))
		var vertices = PackedVector3Array()
		var normals = PackedVector3Array()
		var bones = PackedInt32Array()
		var weights = PackedFloat32Array()
		for i in range(0,data.vertices.size(),3):
			var p = Vector3(data.vertices[i],data.vertices[i+1],data.vertices[i+2])
			vertices.append(p)
			normals.append(Vector3(data.normals[i],data.normals[i+1],data.normals[i+2]))
			if resource_name.begins_with("uniform_trousers"):
				var hip = 1 if p.x<0 else 3
				var knee = hip+1
				var root_weight = smoothstep(0.72,0.93,p.y)
				var knee_weight = (1.0-smoothstep(0.39,0.64,p.y))*(1.0-root_weight)
				bones.append_array(PackedInt32Array([0,hip,knee,0]))
				weights.append_array(PackedFloat32Array([root_weight,1.0-root_weight-knee_weight,knee_weight,0]))
			elif resource_name.begins_with("uniform_jacket"):
				var side = 0 if p.x<0 else 1
				var shoulder = Vector3(-.205,1.438,-.038) if side==0 else Vector3(.205,1.438,-.038)
				var elbow = Vector3(-.290,1.218,-.20) if side==0 else Vector3(.310,1.198,.006)
				var wrist = Vector3(.025,1.302,-.565) if side==0 else Vector3(.133,1.275,-.255)
				# Forward left sleeve crosses the centre line; infer it from depth too.
				if p.z < -.34:
					side=0
					shoulder=Vector3(-.205,1.438,-.038)
					elbow=Vector3(-.290,1.218,-.20)
					wrist=Vector3(.025,1.302,-.565)
				var upper_t = clampf((p-shoulder).dot(elbow-shoulder)/(elbow-shoulder).length_squared(),0,1)
				var lower_t = clampf((p-elbow).dot(wrist-elbow)/(wrist-elbow).length_squared(),0,1)
				var upper_dist=p.distance_to(shoulder.lerp(elbow,upper_t))
				var lower_dist=p.distance_to(elbow.lerp(wrist,lower_t))
				var arm_weight=smoothstep(.16,.25,absf(p.x))
				arm_weight=maxf(arm_weight,1.0-smoothstep(-.26,-.16,p.z))
				var forearm_weight=smoothstep(.60,1.0,upper_t) if upper_dist<lower_dist else 1.0
				arm_weight*=smoothstep(.93,1.12,p.y)
				bones.append_array(PackedInt32Array([7,8+side*2,9+side*2,0]))
				weights.append_array(PackedFloat32Array([1-arm_weight,arm_weight*(1-forearm_weight),arm_weight*forearm_weight,0]))
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array(data.indices)
		if not bones.is_empty():
			arrays[Mesh.ARRAY_BONES]=bones
			arrays[Mesh.ARRAY_WEIGHTS]=weights
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		baked_meshes[resource_name]=mesh
	var node = mesh_node(parent,baked_meshes[resource_name],Vector3.ZERO,color)
	var mat = ink_material(color,false,0.15).duplicate()
	mat.set_shader_parameter("silhouette",true)
	mat.set_shader_parameter("garment",2 if resource_name.begins_with("uniform_trousers") else 1)
	node.material_override=mat
	if skeleton!=null:
		var skin_resource = Skin.new()
		for i in range(skeleton.get_bone_count()):
			skin_resource.add_bind(i,skeleton.get_bone_global_rest(i).affine_inverse())
		node.skin=skin_resource
		node.skeleton=node.get_path_to(skeleton)
	return node

static func ink_material(color: Color, vertex_tint: bool = false, strength: float = 0.32) -> ShaderMaterial:
	var key = "ink"+color.to_html()+str(vertex_tint)+str(strength)
	if materials.has(key):
		return materials[key]
	var mat = ShaderMaterial.new()
	mat.shader = INK_SHADER
	mat.set_shader_parameter("pigment",color)
	mat.set_shader_parameter("vertex_tint",vertex_tint)
	mat.set_shader_parameter("hatch_strength",strength)
	materials[key] = mat
	return mat

static func loft(parent: Node3D, at: Vector3, profiles: Array, color: Color, segments: int = 16, contour: bool = true) -> Node3D:
	# Elliptical section loft: tapered anatomy / cloth / helmets, with explicit ink edges.
	# Each profile is (height, half-width, half-depth, front/back offset).
	var root = Node3D.new()
	root.position = at
	parent.add_child(root)
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var colors = PackedColorArray()
	for row in range(profiles.size()-1):
		var a: Vector4 = profiles[row]
		var b: Vector4 = profiles[row+1]
		for i in range(segments):
			var angle = float(i)/segments*TAU
			var next = float(i+1)/segments*TAU
			var p = [Vector3(cos(angle)*a.y,a.x,sin(angle)*a.z+a.w),Vector3(cos(next)*a.y,a.x,sin(next)*a.z+a.w),Vector3(cos(next)*b.y,b.x,sin(next)*b.z+b.w),Vector3(cos(angle)*b.y,b.x,sin(angle)*b.z+b.w)]
			var n = (p[2]-p[0]).cross(p[1]-p[0]).normalized()
			var shade = 0.88+maxf(0.0,n.y)*0.13+maxf(0.0,n.x)*0.035
			for k in [0,2,1,0,3,2]:
				vertices.append(p[k])
				normals.append(n)
				colors.append(Color(color.r*shade,color.g*shade,color.b*shade))
	for end in [0,profiles.size()-1]:
		var r: Vector4 = profiles[end]
		var normal = Vector3.DOWN if end==0 else Vector3.UP
		for i in range(segments):
			var a = float(i)/segments*TAU
			var b = float(i+1)/segments*TAU
			for p in [Vector3(0,r.x,r.w),Vector3(cos(a)*r.y,r.x,sin(a)*r.z+r.w),Vector3(cos(b)*r.y,r.x,sin(b)*r.z+r.w)]:
				vertices.append(p)
				normals.append(normal)
				colors.append(color)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node = mesh_node(root,mesh,Vector3.ZERO,color)
	var mat = ink_material(color,true,0.17).duplicate()
	if contour:
		mat.set_shader_parameter("silhouette",true)
	node.material_override=mat
	return root

static func cloth_limb(parent: Node3D, a: Vector3, b: Vector3, radius_a: float, radius_b: float, color: Color) -> Node3D:
	var distance = a.distance_to(b)
	var root = loft(parent,a,[Vector4(0,radius_a*0.88,radius_a,0),Vector4(distance*0.20,radius_a,radius_a*0.9,0),Vector4(distance*0.72,radius_b*1.08,radius_b,0),Vector4(distance,radius_b,radius_b*0.85,0)],color,12)
	root.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	for fraction in [0.24,0.75]:
		var r = lerpf(radius_a,radius_b,fraction)
		line(root,Vector3(-r*0.55,distance*fraction,-r*0.85),Vector3(r*0.60,distance*fraction+0.022,-r*0.77),INK.lightened(0.13))
	return root

static func material(color: Color, shaded: bool = false) -> StandardMaterial3D:
	var key = color.to_html() + str(shaded)
	if materials.has(key):
		return materials[key]
	var m = StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if shaded else BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[key] = m
	return m

static func mesh_node(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, shaded: bool = false) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material(color, shaded)
	instance.position = at
	parent.add_child(instance)
	return instance

static func line(parent: Node3D, a: Vector3, b: Vector3, color: Color = INK) -> MeshInstance3D:
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([a, b])
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh_node(parent, mesh, Vector3.ZERO, color)

static func box(parent: Node3D, at: Vector3, size: Vector3, color: Color, outline: bool = true) -> Node3D:
	var root = Node3D.new()
	root.position = at
	parent.add_child(root)
	var half = size * 0.5
	var v = PackedVector3Array([
		Vector3(-half.x, -half.y, -half.z), Vector3(half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, half.z), Vector3(-half.x, -half.y, half.z),
		Vector3(-half.x, half.y, -half.z), Vector3(half.x, half.y, -half.z),
		Vector3(half.x, half.y, half.z), Vector3(-half.x, half.y, half.z)])
	var faces = [[0, 1, 2, 3], [4, 7, 6, 5], [0, 4, 5, 1], [3, 2, 6, 7], [1, 5, 6, 2], [0, 3, 7, 4]]
	var shades = [0.72, 1.05, 0.83, 0.94, 0.84, 0.92]
	var normals = [Vector3.DOWN,Vector3.UP,Vector3.FORWARD,Vector3.BACK,Vector3.RIGHT,Vector3.LEFT]
	var points = PackedVector3Array()
	var colors = PackedColorArray()
	var vertex_normals = PackedVector3Array()
	for i in range(faces.size()):
		for corner in [0, 1, 2, 0, 2, 3]:
			points.append(v[faces[i][corner]])
			colors.append(Color(color.r * shades[i], color.g * shades[i], color.b * shades[i], color.a))
			vertex_normals.append(normals[i])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_NORMAL] = vertex_normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface = mesh_node(root, mesh, Vector3.ZERO, Color.WHITE)
	surface.material_override = ink_material(Color.WHITE,true,0.23 if outline else 0.0)
	if outline:
		var edges = PackedVector3Array()
		for pair in [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]:
			edges.append(v[pair[0]])
			edges.append(v[pair[1]])
		var edge_arrays = []
		edge_arrays.resize(Mesh.ARRAY_MAX)
		edge_arrays[Mesh.ARRAY_VERTEX] = edges
		var edge_mesh = ArrayMesh.new()
		edge_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, edge_arrays)
		mesh_node(root, edge_mesh, Vector3.ZERO, INK)
	return root

static func cylinder(parent: Node3D, at: Vector3, radius: float, height: float, color: Color, top: float = -1) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius if top < 0 else top
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	var node = mesh_node(parent, mesh, at, color)
	if color.a >= 1:
		node.material_override = ink_material(color)
	return node

static func sphere(parent: Node3D, at: Vector3, radius: float, color: Color, shape: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 20
	mesh.rings = 10
	var node = mesh_node(parent, mesh, at, color)
	node.material_override = ink_material(color,false,0.25)
	node.scale = shape
	return node

static func ring(parent: Node3D, center: Vector3, radius: float, color: Color, width: float = 0.035, segments: int = 64) -> MeshInstance3D:
	var vertices = PackedVector3Array()
	for i in range(segments):
		var a = float(i) / segments * TAU
		var b = float(i + 1) / segments * TAU
		var points = [Vector3(cos(a) * radius, 0, sin(a) * radius), Vector3(cos(b) * radius, 0, sin(b) * radius),
			Vector3(cos(b) * (radius + width), 0, sin(b) * (radius + width)), Vector3(cos(a) * (radius + width), 0, sin(a) * (radius + width))]
		for k in [0, 1, 2, 0, 2, 3]:
			vertices.append(points[k])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh_node(parent, mesh, center, color)

static func soldier(parent: Node3D, team: int, controlled: bool, detailed: bool = true) -> Dictionary:
	var root = Node3D.new()
	parent.add_child(root)
	var team_color = BLUE if team==0 else RED
	var fabric = Color("a5aec3") if team==0 else Color("b7a7b3")
	var webbing = Color("747286")
	var skin = Color("c2b5b9")
	cylinder(root,Vector3(0,0.018,0),0.33,0.01,Color(0.20,0.17,0.27,0.14)).scale.z=1.3
	if controlled:
		ring(root,Vector3(0,0.03,0),0.48,BLUE.lightened(0.12),0.020)
	var body = Node3D.new()
	root.add_child(body)
	# A seven-and-a-half-head adult silhouette with a staggered, flexed rifle stance.
	var skeleton = Skeleton3D.new()
	skeleton.name="UniformRig"
	body.add_child(skeleton)
	skeleton.add_bone("pelvis")
	skeleton.set_bone_rest(0,Transform3D.IDENTITY)
	for side in [-1,1]:
		var prefix = "left" if side==-1 else "right"
		var hip_index = skeleton.get_bone_count()
		skeleton.add_bone(prefix+"_hip")
		skeleton.set_bone_parent(hip_index,0)
		var hip_point = Vector3(side*0.115,0.90,0.03)
		skeleton.set_bone_rest(hip_index,Transform3D(Basis.IDENTITY,hip_point))
		var knee_index = skeleton.get_bone_count()
		skeleton.add_bone(prefix+"_knee")
		skeleton.set_bone_parent(knee_index,hip_index)
		var knee_point = Vector3(side*0.16,0.52,-0.105 if side==-1 else 0.015)
		skeleton.set_bone_rest(knee_index,Transform3D(Basis.IDENTITY,knee_point-hip_point))
		var knee = BoneAttachment3D.new()
		skeleton.add_child(knee)
		knee.set_meta("pending_bone",prefix+"_ankle")
		var ankle = Vector3.ZERO
		var boot = loft(knee,ankle+Vector3(0,-0.11,-0.066),[Vector4(0,0.079,0.152,-0.015),Vector4(0.036,0.085,0.164,-0.02),Vector4(0.10,0.072,0.13,0),Vector4(0.21,0.065,0.078,0.045)],Color("514c5f"),16)
		for lace in range(4):
			line(boot,Vector3(-0.034,0.12+lace*0.012,-0.075+lace*0.026),Vector3(0.034,0.12+lace*0.012,-0.075+lace*0.026),Color("b6afc2"))
		var thigh = BoneAttachment3D.new()
		skeleton.add_child(thigh)
		thigh.bone_name=prefix+"_hip"
		var pocket = loft(thigh,Vector3(side*0.093,-0.18,-0.025),[Vector4(0,0.039,0.072,0),Vector4(0.13,0.045,0.079,0),Vector4(0.16,0.041,0.076,0)],fabric.darkened(0.04),10)
		line(pocket,Vector3(side*0.044,0.12,-0.071),Vector3(side*0.044,0.12,0.071),webbing)
	for side in [-1,1]:
		var index=skeleton.get_bone_count()
		skeleton.add_bone("left_ankle" if side==-1 else "right_ankle")
		skeleton.set_bone_parent(index,2 if side==-1 else 4)
		var knee_point=Vector3(side*.16,.52,-.105 if side==-1 else .015)
		skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,Vector3(side*.185,.15,-.02 if side==-1 else .16)-knee_point))
	skeleton.add_bone("chest")
	skeleton.set_bone_parent(7,0)
	skeleton.set_bone_rest(7,Transform3D(Basis.IDENTITY,Vector3(0,.96,0)))
	for side in [0,1]:
		var shoulder=Vector3(-.205,1.438,-.038) if side==0 else Vector3(.205,1.438,-.038)
		var elbow=Vector3(-.290,1.218,-.20) if side==0 else Vector3(.310,1.198,.006)
		skeleton.add_bone("left_arm" if side==0 else "right_arm")
		skeleton.set_bone_parent(8+side*2,7)
		skeleton.set_bone_rest(8+side*2,Transform3D(Basis.IDENTITY,shoulder-Vector3(0,.96,0)))
		skeleton.add_bone("left_forearm" if side==0 else "right_forearm")
		skeleton.set_bone_parent(9+side*2,8+side*2)
		skeleton.set_bone_rest(9+side*2,Transform3D(Basis.IDENTITY,elbow-shoulder))
	skeleton.add_bone("neck")
	skeleton.set_bone_parent(12,7)
	skeleton.set_bone_rest(12,Transform3D(Basis.IDENTITY,Vector3(0,1.54,-.07)-Vector3(0,.96,0)))
	skeleton.reset_bone_poses()
	for attachment in skeleton.get_children():
		if attachment.has_meta("pending_bone"):
			attachment.bone_name=attachment.get_meta("pending_bone")
	var suffix="" if detailed else "_lod"
	uniform_mesh(body,"uniform_trousers"+suffix,fabric.darkened(0.045),skeleton)
	uniform_mesh(body,"uniform_jacket"+suffix,fabric,skeleton)
	var chest_attachment=BoneAttachment3D.new()
	skeleton.add_child(chest_attachment)
	chest_attachment.bone_name="chest"
	var torso=Node3D.new()
	chest_attachment.add_child(torso)
	torso.position.y=-.96
	# A tailored collar and continuous lower hem establish the garment silhouette.
	var collar = loft(torso,Vector3(0,1.49,-0.055),[Vector4(0,0.108,0.100,0),Vector4(0.047,0.090,0.086,0)],fabric.darkened(0.05),20)
	line(collar,Vector3(-0.079,0.043,-0.047),Vector3(-0.028,0.014,-0.09),webbing)
	line(collar,Vector3(0.079,0.043,-0.047),Vector3(0.028,0.014,-0.09),webbing)
	# Shoulder yoke and elbow creases follow the continuous surface, not limb end caps.
	for side in [-1,1]:
		line(torso,Vector3(side*0.08,1.50,-0.048),Vector3(side*0.21,1.474,-0.065),webbing)
		line(torso,Vector3(side*0.16,1.449,0.081),Vector3(side*0.20,1.39,0.11),webbing)
	# Vest plates, webbing, seams, pouch flaps and belt hardware.
	for x in [-0.09,0.09]:
		var chest_pocket=loft(torso,Vector3(x,1.28,-0.18),[Vector4(0,0.044,0.014,0),Vector4(0.105,0.047,0.019,0),Vector4(0.135,0.042,0.012,0)],fabric.darkened(0.03),10)
		line(chest_pocket,Vector3(-0.04,0.10,-0.018),Vector3(0.04,0.10,-0.018),webbing)
		box(chest_pocket,Vector3(0,0.09,-0.022),Vector3(0.012,0.014,0.008),INK,false)
	for x in [-0.085,0.015,0.115]:
		loft(torso,Vector3(x,1.08,-0.175),[Vector4(0,0.038,0.036,0),Vector4(0.13,0.041,0.038,0),Vector4(0.18,0.034,0.030,0)],fabric.darkened(0.08),8)
		line(torso,Vector3(x-0.034,1.215,-0.216),Vector3(x+0.034,1.215,-0.216),INK)
		box(torso,Vector3(x,1.185,-0.217),Vector3(0.018,0.034,0.01),webbing,false)
	for x in [-0.13,0.13]:
		cloth_limb(torso,Vector3(x,1.02,0.166),Vector3(x,1.49,0.09),0.019,0.018,webbing)
		cloth_limb(torso,Vector3(x,1.49,0.09),Vector3(x,1.42,-0.16),0.020,0.021,webbing)
		box(torso,Vector3(x,1.01,-0.151),Vector3(0.074,0.055,0.052),Color("6c647c"))
	line(torso,Vector3(-0.15,1.08,0.151),Vector3(-0.12,1.40,0.152),INK)
	line(torso,Vector3(0.14,1.08,0.151),Vector3(0.12,1.40,0.152),INK)
	# Compact field pack: curved canvas, bedroll and straps, rather than a box torso.
	loft(torso,Vector3(0,1.12,0.20),[Vector4(0,0.13,0.07,0),Vector4(0.06,0.17,0.09,0),Vector4(0.29,0.16,0.105,0),Vector4(0.37,0.11,0.07,0)],Color("9290a3"),14)
	var bedroll = cylinder(torso,Vector3(0,1.40,0.28),0.068,0.38,Color("beb8c9"))
	bedroll.rotation.z=PI/2
	for x in [-0.115,0.115]:
		line(torso,Vector3(x,1.05,0.27),Vector3(x,1.42,0.35),webbing)
	box(torso,Vector3(-0.235,1.08,0.04),Vector3(0.065,0.15,0.10),webbing)
	line(torso,Vector3(-0.26,1.17,0.04),Vector3(-0.27,1.53,0.04),INK)
	# Neck, jaw, ears and a small fitted helmet with a curved rim.
	var head_attachment=BoneAttachment3D.new();skeleton.add_child(head_attachment);head_attachment.bone_name="neck"
	var head=Node3D.new();head_attachment.add_child(head);head.position=-Vector3(0,1.54,-.07)
	cylinder(head,Vector3(0,1.56,-0.07),0.065,0.16,skin)
	loft(head,Vector3(0,1.60,-0.09),[Vector4(0,0.060,0.068,-0.01),Vector4(0.045,0.082,0.081,-0.015),Vector4(0.13,0.107,0.091,0),Vector4(0.21,0.089,0.087,0)],skin,16)
	box(head,Vector3(0,1.72,-0.194),Vector3(0.034,0.065,0.031),skin)
	for side in [-1,1]:
		loft(head,Vector3(side*0.102,1.67,-0.09),[Vector4(0,0.019,0.020,0),Vector4(0.055,0.021,0.025,0)],skin,8)
		line(head,Vector3(side*0.091,1.72,-0.16),Vector3(side*0.055,1.63,-0.17),webbing)
		line(head,Vector3(side*0.055,1.63,-0.17),Vector3(0,1.625,-0.17),webbing)
	var helmet = loft(head,Vector3(0,1.765,-0.085),[Vector4(0,0.16,0.19,0),Vector4(0.026,0.166,0.19,0),Vector4(0.085,0.155,0.169,0.012),Vector4(0.145,0.112,0.133,0.014),Vector4(0.172,0.035,0.050,0.012)],fabric.lightened(0.15),24)
	var rim = ring(helmet,Vector3(0,0.02,0),0.165,INK,0.009,40)
	rim.scale.z=1.15
	var band = ring(helmet,Vector3(0,0.07,0.01),0.156,team_color,0.018,40)
	band.scale.z=1.1
	for side in [-1,1]:
		var last = Vector3(side*0.072,0.044,-0.165)
		for k in range(1,13):
			var a = float(k)/12*PI
			var p = Vector3(side*0.072,0.042+sin(a)*0.121,-cos(a)*0.165+0.01)
			line(helmet,last,p,Color("68627b"))
			last=p
	# Gloves overlap the jacket cuffs; bent sleeves are one continuous baked mesh.
	var gloves: Array = []
	for side in [0,1]:
		var attachment=BoneAttachment3D.new()
		skeleton.add_child(attachment)
		attachment.bone_name="left_forearm" if side==0 else "right_forearm"
		var elbow=Vector3(-.290,1.218,-.20) if side==0 else Vector3(.310,1.198,.006)
		var p=Vector3(.035,1.31,-.58) if side==0 else Vector3(.135,1.275,-.255)
		var glove=loft(attachment,p-elbow,[Vector4(-.025,.048,.071,0),Vector4(.065,.039,.065,0)],Color("686276"),10)
		gloves.append(glove)
	box(torso,Vector3(-0.29,1.385,-0.10),Vector3(0.017,0.095,0.09),team_color)
	var rifle = rifle_model(torso)
	var muzzle = sphere(rifle,Vector3(0,0.015,-0.66),0.09,Color("efe1b8"),Vector3(0.55,0.55,1.8))
	muzzle.visible=false
	Batch.collapse(rifle,[muzzle],"rifle")
	Batch.collapse(torso,[rifle],"torso_"+str(team))
	for attachment in skeleton.get_children():
		if attachment is BoneAttachment3D and attachment!=chest_attachment:
			Batch.collapse(attachment,[],"attachment_"+str(team)+attachment.bone_name)
	Batch.skin_attachments(skeleton,[rifle],"skin_details_"+str(team))
	return {"root":root,"body":body,"skeleton":skeleton,"rifle":rifle,"muzzle":muzzle,"rifle_rest":Vector3(0.115,1.355,-0.33)}

static func rifle_model(parent: Node3D) -> Node3D:
	var root = Node3D.new()
	root.position=Vector3(0.115,1.355,-0.33)
	root.rotation.y=-0.06
	parent.add_child(root)
	var metal = Color("68647a")
	box(root,Vector3(0,0,0.015),Vector3(0.070,0.105,0.24),metal)
	box(root,Vector3(0,0.01,-0.22),Vector3(0.068,0.08,0.25),Color("a8a5b8"))
	box(root,Vector3(0,0.05,-0.065),Vector3(0.046,0.022,0.43),INK)
	box(root,Vector3(0,-0.075,0.083),Vector3(0.045,0.13,0.055),INK).rotation.x=-0.28
	box(root,Vector3(0,-0.115,-0.005),Vector3(0.042,0.16,0.080),metal).rotation.x=-0.14
	for x in [-0.027,0.027]:
		line(root,Vector3(x,-0.055,-0.04),Vector3(x,-0.18,-0.015),INK)
	box(root,Vector3(0,0.002,0.25),Vector3(0.065,0.09,0.22),Color("8b869c"))
	box(root,Vector3(0,-0.027,0.356),Vector3(0.078,0.14,0.026),INK)
	var barrel = cylinder(root,Vector3(0,0.012,-0.45),0.014,0.23,INK)
	barrel.rotation.x=PI/2
	box(root,Vector3(0,0.015,-0.586),Vector3(0.027,0.032,0.07),INK)
	box(root,Vector3(0,0.051,-0.405),Vector3(0.014,0.081,0.018),INK)
	box(root,Vector3(0,0.088,0.085),Vector3(0.054,0.05,0.065),INK)
	for i in range(11):
		box(root,Vector3(0,0.064,0.12-i*0.037),Vector3(0.06,0.012,0.013),Color("bdb7cc"),false)
	for i in range(5):
		for side in [-1,1]:
			box(root,Vector3(side*0.036,0.013,-0.12-i*0.042),Vector3(0.008,0.027,0.021),INK,false)
	line(root,Vector3(0.044,0.005,0.10),Vector3(0.044,0.005,0.02),Color("dcd6e7"))
	return root

static func roof(parent: Node3D, width: float, depth: float, height: float, color: Color) -> Node3D:
	var root = Node3D.new()
	parent.add_child(root)
	var w = width / 2 + 0.24
	var d = depth / 2 + 0.25
	var ridge = height + 1.2
	var v = [Vector3(-w,height,-d),Vector3(w,height,-d),Vector3(w,height,d),Vector3(-w,height,d),Vector3(-w,ridge,0),Vector3(w,ridge,0)]
	var faces = [[0,1,5,0,5,4],[3,4,5,3,5,2],[0,4,3],[1,2,5]]
	for i in range(faces.size()):
		var points = PackedVector3Array()
		for index in faces[i]:
			points.append(v[index])
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		var mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var normals = PackedVector3Array()
		var n = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
		for point in points:
			normals.append(n)
		arrays[Mesh.ARRAY_NORMAL] = normals
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var node = mesh_node(root,mesh,Vector3.ZERO,color)
		node.material_override = ink_material(color.lightened(0.04) if i==1 else color.darkened(0.10),false,0.23)
	for pair in [[0,1],[1,2],[2,3],[3,0],[0,4],[3,4],[1,5],[2,5],[4,5]]:
		line(root,v[pair[0]],v[pair[1]])
	for i in range(1, 13):
		var t = float(i) / 13
		line(root, Vector3(-w, lerpf(ridge,height,t)+0.008, d*t),Vector3(w,lerpf(ridge,height,t)+0.008,d*t),Color("817990"))
		line(root, Vector3(-w, lerpf(ridge,height,t)+0.008,-d*t),Vector3(w,lerpf(ridge,height,t)+0.008,-d*t),Color("817990"))
		for j in range(int(width/0.45)):
			var x = -w+0.15+float(j)*0.45+float(i%2)*0.22
			var t2 = float(i-1)/13
			line(root,Vector3(x,lerpf(ridge,height,t)+0.01,d*t),Vector3(x,lerpf(ridge,height,t2)+0.01,d*t2),Color("9990a5"))
	box(root,Vector3(0,ridge+0.035,0),Vector3(width+0.55,0.055,0.15),Color("e4e1eb"))
	return root

static func building(parent: Node3D, item: Dictionary) -> Dictionary:
	var root=Node3D.new()
	root.position=Vector3(float(item.position[0]),0,float(item.position[1]))
	parent.add_child(root)
	var w=float(item.size[0])
	var d=float(item.size[1])
	var h=float(item.height)
	var floor_group=Node3D.new()
	root.add_child(floor_group)
	box(floor_group,Vector3(0,.025,0),Vector3(w,.05,d),Color("b8acb7"))
	for i in range(int(d/.22)):
		var z=-d*.5+i*.22
		line(floor_group,Vector3(-w*.5,.057,z),Vector3(w*.5,.057,z),Color("908597"))
		for j in range(4):
			var x=-w*.5+float(j)*w/4+float(i%2)*.4
			line(floor_group,Vector3(x,.058,z),Vector3(x,.058,z+.22),Color("908597"))
	var upper=Node3D.new()
	root.add_child(upper)
	for part in Layout.walls(item):
		var at: Vector2=part.at
		var size: Vector2=part.size
		box(floor_group,Vector3(at.x,.275,at.y),Vector3(size.x,.55,size.y),Color("c4bdce"))
		box(upper,Vector3(at.x,.55+(h-.55)*.5,at.y),Vector3(size.x,h-.55,size.y),PAPER)
		box(floor_group,Vector3(at.x,.57,at.y),Vector3(size.x+.015,.04,size.y+.015),STONE)
	for z in [-d*.5,d*.5]:
		box(upper,Vector3(0,2.20+(h-2.20)*.5,z),Vector3(1.6,h-2.20,.22),PAPER)
		for side in [-1,1]:
			box(upper,Vector3(side*.85,1.1,z),Vector3(.10,2.2,.28),Color("8c829b"))
		box(floor_group,Vector3(0,.035,z),Vector3(1.7,.07,.5),Color("c8c1ce"))
		for x in [-w*.31,w*.31]:
			var face=z+signf(z)*.13
			box(upper,Vector3(x,1.67,face),Vector3(.94,1.1,.05),INK)
			box(upper,Vector3(x,1.67,face+signf(z)*.035),Vector3(.76,.9,.035),Color("8d8aab"))
			box(upper,Vector3(x,1.67,face+signf(z)*.060),Vector3(.045,.96,.04),PAPER)
			box(upper,Vector3(x,1.67,face+signf(z)*.060),Vector3(.82,.045,.04),PAPER)
			box(upper,Vector3(x,1.08,face),Vector3(1.06,.09,.28),STONE)
			for side in [-1,1]:
				box(upper,Vector3(x+side*.59,1.67,face),Vector3(.22,1.04,.05),Color("aaa9bf"))
				for slat in range(7):
					line(upper,Vector3(x+side*.59-.09,1.23+slat*.13,face+signf(z)*.03),Vector3(x+side*.59+.09,1.23+slat*.13,face+signf(z)*.03),INK)
	for part in Layout.furniture(item):
		var at=Vector3(part.at.x,0,part.at.y)
		if part.kind=="bed":
			box(floor_group,at+Vector3(0,.21,0),Vector3(1.05,.30,1.65),Color("777285"))
			box(floor_group,at+Vector3(0,.41,0),Vector3(.98,.14,1.58),Color("d0c9d7"))
			box(floor_group,at+Vector3(0,.51,-.48),Vector3(.64,.14,.38),PAPER)
			box(floor_group,at+Vector3(0,.50,.25),Vector3(.99,.035,.99),Color("8d92ad"))
			for z in [.05,.22,.39,.56]:
				line(floor_group,at+Vector3(-.45,.523,z),at+Vector3(.45,.523,z),Color("72758c"))
		else:
			box(floor_group,at+Vector3(0,.74,0),Vector3(1.15,.08,.70),Color("8d8095"))
			for x in [-.46,.46]:
				for z in [-.25,.25]:
					box(floor_group,at+Vector3(x,.35,z),Vector3(.055,.7,.055),INK,false)
			box(floor_group,at+Vector3(-.22,.80,0),Vector3(.36,.025,.28),PAPER,false)
			box(floor_group,at+Vector3(.29,.86,-.15),Vector3(.31,.18,.19),Color("625d73"))
			line(floor_group,at+Vector3(.4,.89,-.15),at+Vector3(.42,1.2,-.15),INK)
	# Supply shelf along the rear wall; detail only, outside the walking corridor.
	for y in [.3,.65,1.0]:
		box(floor_group,Vector3(w*.5-.35,y,-d*.5+.4),Vector3(.42,.05,.6),Color("8b8098"))
		box(floor_group,Vector3(w*.5-.35,y+.12,-d*.5+.4),Vector3(.32,.18,.42),Color("aaa1b2"))
	var roof_node=roof(root,w,d,h,Color("bfbed2") if item.roof=="blue" else Color("c9c2d6"))
	box(roof_node,Vector3(w*.29,h+1.03,-.55),Vector3(.56,1.15,.6),STONE)
	box(roof_node,Vector3(w*.29,h+1.64,-.55),Vector3(.68,.13,.72),INK)
	Batch.collapse(floor_group)
	var fade_nodes=Batch.collapse(roof_node)
	fade_nodes.append_array(Batch.collapse(upper))
	for node in fade_nodes:
		node.material_override=node.material_override.duplicate()
	return {"root":root,"roof":roof_node,"body":upper,"fade_nodes":fade_nodes,"fade":1.0,"inside":false,"position":Vector2(root.position.x,root.position.z),"size":Vector2(w,d),"height":h}

static func wall(parent: Node3D, item: Dictionary) -> Node3D:
	var root = Node3D.new()
	root.position = Vector3(float(item.position[0]),0,float(item.position[1]))
	parent.add_child(root)
	var sx = float(item.size[0])
	var sz = float(item.size[1])
	var horizontal = sx > sz
	var length = maxf(sx,sz)
	var count = int(ceil(length / 0.7))
	for row in range(3):
		for i in range(count):
			var offset = (float(i)+0.5)/count*length-length/2
			var at = Vector3(offset,0.22+row*0.36,0) if horizontal else Vector3(0,0.22+row*0.36,offset)
			var size = Vector3(length/count-0.04,0.32,sz) if horizontal else Vector3(sx,0.32,length/count-0.04)
			box(root,at,size,STONE.lightened(float((i+row)%3)*0.035))
	box(root,Vector3(0,1.17,0),Vector3(sx+0.1,0.16,sz+0.1),PAPER.darkened(0.08))
	return root

static func tree(parent: Node3D, point: Vector2, rng: RandomNumberGenerator) -> void:
	var root = Node3D.new()
	parent.add_child(root)
	root.position = Vector3(point.x,0,point.y)
	var h = rng.randf_range(2.7,3.5)
	cylinder(root,Vector3(0,0.01,0),1.0,0.015,Color(0.24,0.29,0.30,0.13))
	loft(root,Vector3.ZERO,[Vector4(0,0.20,0.17,0),Vector4(0.45,0.10,0.11,0.025),Vector4(h*0.56,0.065,0.055,-0.09),Vector4(h*0.83,0.024,0.025,-0.16)],Color("8b8299"),12)
	for i in range(8):
		var a = float(i)*2.4
		var center = Vector3(cos(a)*0.67,h*0.67+float(i%3)*0.31,sin(a)*0.36)
		cloth_limb(root,Vector3(0,h*0.35,-0.025),center,0.045,0.012,Color("797187"))
		foliage_patch(root,center,Vector2(rng.randf_range(0.52,0.86),rng.randf_range(0.42,0.65)),Color("9f98ac").lightened(float(i%3)*0.055),rng)

static func foliage_patch(parent: Node3D, center: Vector3, radii: Vector2, color: Color, rng: RandomNumberGenerator) -> void:
	# Jagged ink silhouettes layered in the fixed camera plane, not intersecting balls.
	var up = Vector3(0,0.707,-0.707)
	var towards = Vector3(0,0.707,0.707)
	var count = 56
	var outline: Array = []
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var strokes = PackedVector3Array()
	for i in range(count):
		var a = float(i)/count*TAU
		var variation = 1.0+sin(a*7+center.x)*0.085+rng.randf_range(-0.08,0.09)
		outline.append(center+Vector3.RIGHT*cos(a)*radii.x*variation+up*sin(a)*radii.y*variation)
	for i in range(count):
		for p in [center,outline[i],outline[(i+1)%count]]:
			vertices.append(p)
			normals.append(towards)
		if i%7!=0:
			strokes.append(outline[i]+towards*0.009)
			strokes.append(outline[(i+1)%count]+towards*0.009)
	for i in range(60):
		var a = rng.randf()*TAU
		var r = sqrt(rng.randf())*0.89
		var at = center+Vector3.RIGHT*cos(a)*radii.x*r+up*sin(a)*radii.y*r+towards*0.015
		strokes.append(at)
		strokes.append(at+Vector3.RIGHT*rng.randf_range(0.025,0.065)+up*0.018)
		if i%3==0:
			strokes.append(at)
			strokes.append(at-Vector3.RIGHT*0.025+up*0.044)
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node = mesh_node(parent,mesh,Vector3.ZERO,color)
	node.material_override=ink_material(color,false,0.10)
	var lines = []
	lines.resize(Mesh.ARRAY_MAX)
	lines[Mesh.ARRAY_VERTEX]=strokes
	var line_mesh=ArrayMesh.new()
	line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,lines)
	mesh_node(parent,line_mesh,Vector3.ZERO,Color("68627b"))

static func crate(parent: Node3D, p: Vector2) -> void:
	var at = Vector3(p.x,0.43,p.y)
	box(parent,at,Vector3(0.8,0.86,0.8),Color("b4adbd"))
	for x in [-0.28,0.28]:
		box(parent,at+Vector3(x,0,0.415),Vector3(0.06,0.82,0.025),Color("726f67"),false)
	line(parent,at+Vector3(-0.35,-0.34,0.43),at+Vector3(0.35,0.34,0.43))
