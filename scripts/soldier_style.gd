extends RefCounted
## Smooth, game-scale character details for the supplied painted reference.
const SHADER=preload("res://shaders/soldier_soft.gdshader")
const SHADOW_SHADER=preload("res://shaders/soldier_shadow.gdshader")
static var materials: Dictionary={}
static var meshes: Dictionary={}
static var high_detail=true

static func shadow(parent: Node3D) -> MeshInstance3D:
	var mesh=PlaneMesh.new();mesh.size=Vector2(3.5,3.5)
	var n=MeshInstance3D.new();n.mesh=mesh;n.position.y=.022;n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(n)
	var mat=ShaderMaterial.new();mat.shader=SHADOW_SHADER;n.material_override=mat;return n

static func update_shadow(view: Dictionary):
	if not view.has("shadow") or not is_instance_valid(view.shadow):return
	var rig: Skeleton3D=view.skeleton;var root: Node3D=view.root;var mat: ShaderMaterial=view.shadow.material_override
	var samples={"head":[12,Vector3(0,.12,-.06)],"chest":[7,Vector3(0,.28,0)],"hip":[0,Vector3(0,.88,0)],"left_foot":[5,Vector3.ZERO],"right_foot":[6,Vector3.ZERO]}
	if view.get("source_rig",false):samples={"head":[rig.find_bone("Head"),Vector3(0,.10,0)],"chest":[rig.find_bone("Spine02"),Vector3.ZERO],"hip":[rig.find_bone("Hip"),Vector3.ZERO],"left_foot":[rig.find_bone("L_Foot"),Vector3.ZERO],"right_foot":[rig.find_bone("R_Foot"),Vector3.ZERO]}
	for key in samples:
		var sample: Array=samples[key];var p: Vector3=rig.to_global(rig.get_bone_global_pose(sample[0])*sample[1])
		var offset=p-root.global_position;var h=maxf(0,p.y-view.shadow.global_position.y)
		mat.set_shader_parameter(key,Vector2(offset.x,offset.z)+Vector2(-.45,-.30)*h)
	mat.set_shader_parameter("softness",.025+maxf(0,root.global_position.y-view.shadow.global_position.y)*.025)

static func material(color: Color,vertex_tint: bool=false,garment: int=0) -> ShaderMaterial:
	var key=color.to_html()+str(vertex_tint)+str(garment)
	if not materials.has(key):
		var m=ShaderMaterial.new();m.shader=SHADER;m.set_shader_parameter("pigment",color);m.set_shader_parameter("vertex_tint",vertex_tint);m.set_shader_parameter("garment",garment);materials[key]=m
	return materials[key]

static func node(parent: Node3D,mesh: Mesh,at: Vector3,color: Color) -> MeshInstance3D:
	var n=MeshInstance3D.new();n.mesh=mesh;n.position=at;n.material_override=material(color);parent.add_child(n);return n

static func ellipsoid(parent: Node3D,at: Vector3,radii: Vector3,color: Color) -> MeshInstance3D:
	var key="sphere_hero" if high_detail else "sphere_crowd"
	if not meshes.has(key):
		var m=SphereMesh.new();m.radius=1;m.height=2;m.radial_segments=24 if high_detail else 12;m.rings=12 if high_detail else 6;meshes[key]=m
	var n=node(parent,meshes[key],at,color);n.scale=radii;return n

static func mesh_from(vertices: PackedVector3Array,normals: PackedVector3Array) -> ArrayMesh:
	var a=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=vertices;a[Mesh.ARRAY_NORMAL]=normals;var m=ArrayMesh.new();m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a);return m

static func rounded_box(parent: Node3D,at: Vector3,size: Vector3,color: Color,bevel: float=.025) -> Node3D:
	var v=PackedVector3Array();var n=PackedVector3Array();var half=size*.5;var r=minf(bevel,minf(half.x,minf(half.y,half.z))*.95);var core=half-Vector3.ONE*r
	var steps=6 if high_detail else 3
	for face in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:
		var a=Vector3.UP if absf(face.x)>.5 else Vector3.RIGHT;var b=face.cross(a)
		for row in range(steps):
			for col in range(steps):
				for corner in [Vector2(0,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(1,0)]:
					var p=(face+a*((col+corner.x)/steps*2-1)+b*((row+corner.y)/steps*2-1))*half
					var center=p.clamp(-core,core);var normal=(p-center).normalized();v.append(center+normal*r);n.append(normal)
	return node(parent,mesh_from(v,n),at,color)

static func loft(parent: Node3D,at: Vector3,profiles: Array,color: Color,segments: int=32) -> MeshInstance3D:
	if not high_detail:segments=mini(segments,16)
	var v=PackedVector3Array();var n=PackedVector3Array()
	for row in range(profiles.size()-1):
		for col in range(segments):
			for corner in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var k=row+corner.y;var a=float(col+corner.x)/segments*TAU;var p: Vector4=profiles[k]
				var previous: Vector4=profiles[maxi(0,k-1)];var next: Vector4=profiles[mini(profiles.size()-1,k+1)]
				var tangent=Vector3(-sin(a)*p.y,0,cos(a)*p.z)
				var up=Vector3(cos(a)*(next.y-previous.y),next.x-previous.x,sin(a)*(next.z-previous.z)+next.w-previous.w)
				v.append(Vector3(cos(a)*p.y,p.x,sin(a)*p.z+p.w));n.append(up.cross(tangent).normalized())
	return node(parent,mesh_from(v,n),at,color)

static func ribbon(parent: Node3D,points: Array,width: float,color: Color,across: Vector3=Vector3.RIGHT) -> MeshInstance3D:
	var v=PackedVector3Array();var n=PackedVector3Array()
	for i in range(points.size()-1):
		var a: Vector3=points[i];var b: Vector3=points[i+1];var side=across*width*.5
		var normal=(b-a).cross(across).normalized()
		for p in [a-side,b+side,b-side,a-side,a+side,b+side]:v.append(p);n.append(normal)
	var result=node(parent,mesh_from(v,n),Vector3.ZERO,color)
	# Ribbons wrap both front and back. Duplicate reverse faces at construction time.
	var count=v.size()
	for i in range(0,count,3):
		for k in [0,2,1]:v.append(v[i+k]);n.append(-n[i+k])
	result.mesh=mesh_from(v,n);return result

static func boot(parent: Node3D):
	var leather=Color("494153")
	ellipsoid(parent,Vector3(0,-.034,-.068),Vector3(.112,.116,.181),leather)
	loft(parent,Vector3(0,0,.017),[Vector4(-.035,.095,.102,0),Vector4(.055,.106,.108,0),Vector4(.14,.104,.106,0),Vector4(.205,.098,.100,0),Vector4(.22,.094,.096,0),Vector4(.22,.001,.001,0)],leather,24)
	ellipsoid(parent,Vector3(0,-.111,-.070),Vector3(.111,.027,.173),leather.darkened(.08))
	loft(parent,Vector3(0,.105,.016),[Vector4(0,.112,.116,0),Vector4(.008,.119,.121,0),Vector4(.057,.119,.121,0),Vector4(.065,.112,.116,0),Vector4(.065,.096,.100,0),Vector4(0,.096,.100,0),Vector4(0,.112,.116,0)],Color("696375"),24)

static func pocket(parent: Node3D,side: float,fabric: Color):
	var p=rounded_box(parent,Vector3(side*.090,-.15,-.125),Vector3(.14,.17,.041),fabric.darkened(.07),.020)
	p.rotation.y=side*-.25
	var flap=rounded_box(p,Vector3(0,.061,-.024),Vector3(.143,.046,.015),fabric.lightened(.04),.007)
	flap.rotation.x=-.08

static func torso(parent: Node3D,fabric: Color):
	var webbing=Color("504553");var canvas=Color("82816a")
	loft(parent,Vector3(0,1.40,-.055),[Vector4(0,.123,.118,0),Vector4(.064,.106,.106,0),Vector4(.076,.096,.094,0)],fabric.darkened(.22))
	for side in [-1,1]:
		var x=side*.16
		ribbon(parent,[Vector3(x,1.07,-.181),Vector3(x*1.13,1.20,-.222),Vector3(x,1.38,-.211),Vector3(x*.9,1.48,-.095),Vector3(x*.9,1.48,.10),Vector3(x,1.28,.21),Vector3(x,1.05,.19)],.048,webbing)
		rounded_box(parent,Vector3(x*1.08,1.23,-.226),Vector3(.052,.060,.010),webbing.lightened(.20),.004)
	loft(parent,Vector3(0,.985,.0),[Vector4(0,.221,.171,0),Vector4(.060,.222,.173,0)],webbing,32)
	rounded_box(parent,Vector3(.02,1.016,-.178),Vector3(.075,.060,.029),Color("777285"),.010)
	var pouch=rounded_box(parent,Vector3(-.228,.993,-.058),Vector3(.14,.23,.14),webbing,.039);pouch.rotation.z=-.14
	rounded_box(pouch,Vector3(0,.075,-.073),Vector3(.13,.053,.015),webbing.lightened(.07),.007)
	ellipsoid(pouch,Vector3(0,.037,-.076),Vector3(.013,.021,.005),webbing.darkened(.22))
	rounded_box(parent,Vector3(0,1.235,.244),Vector3(.42,.47,.22),canvas,.094)
	rounded_box(parent,Vector3(0,1.40,.276),Vector3(.41,.115,.218),canvas.lightened(.07),.047)
	rounded_box(parent,Vector3(0,1.175,.363),Vector3(.105,.13,.033),webbing,.018)
	for side in [-1,1]:
		var side_pouch=rounded_box(parent,Vector3(side*.235,1.16,.247),Vector3(.112,.29,.177),canvas.darkened(.025),.045)
		rounded_box(side_pouch,Vector3(side*.058,.01,.005),Vector3(.025,.070,.171),webbing,.012)
		rounded_box(parent,Vector3(side*.17,1.067,.348),Vector3(.056,.08,.021),webbing,.012)
		ellipsoid(parent,Vector3(side*.17,1.068,.362),Vector3(.012,.013,.006),webbing.darkened(.2))
	var roll=Node3D.new();parent.add_child(roll);roll.position=Vector3(0,1.52,.31);roll.rotation.z=PI/2
	loft(roll,Vector3(0,-.27,0),[Vector4(0,.093,.095,0),Vector4(.02,.108,.108,0),Vector4(.52,.108,.108,0),Vector4(.54,.093,.095,0)],canvas.lightened(.05))
	for side in [-1,1]:
		var cap=ellipsoid(parent,Vector3(side*.274,1.52,.31),Vector3(.007,.095,.095),canvas.darkened(.10))
		ellipsoid(parent,cap.position+Vector3(side*.004,0,0),Vector3(.006,.054,.054),canvas.darkened(.22))
		ellipsoid(parent,cap.position+Vector3(side*.010,-.006,0),Vector3(.006,.031,.031),canvas.darkened(.09))
		loft(roll,Vector3(0,side*.17-.023,0),[Vector4(0,.111,.111,0),Vector4(.047,.111,.111,0)],webbing,24)
		ribbon(parent,[Vector3(side*.17,1.49,.397),Vector3(side*.17,1.28,.36),Vector3(side*.16,1.04,.33)],.037,webbing)

static func head(parent: Node3D,fabric: Color,team: Color):
	var skin=Color("e9b780");var dark=Color("413b4d")
	ellipsoid(parent,Vector3(0,1.583,-.077),Vector3(.225,.175,.201),Color("463c41"))
	ellipsoid(parent,Vector3(0,1.556,-.204),Vector3(.215,.172,.131),skin)
	for side in [-1,1]:
		ellipsoid(parent,Vector3(side*.214,1.547,-.148),Vector3(.038,.059,.044),skin.darkened(.045))
		ellipsoid(parent,Vector3(side*.234,1.551,-.171),Vector3(.011,.030,.015),skin.darkened(.13))
		ellipsoid(parent,Vector3(side*.074,1.556,-.325),Vector3(.018,.033,.009),dark)
		ellipsoid(parent,Vector3(side*.214,1.594,-.182),Vector3(.029,.045,.031),Color("4f4149"))
		ribbon(parent,[Vector3(side*.216,1.586,-.198),Vector3(side*.186,1.457,-.224),Vector3(side*.080,1.411,-.253)],.016,Color("4f4149"),Vector3(1,0,0))
	ellipsoid(parent,Vector3(0,1.516,-.332),Vector3(.015,.013,.012),skin.darkened(.025))
	var helmet_color=fabric.lightened(.17)
	var base=Vector3(0,1.634,-.047)
	loft(parent,base,[Vector4(0,.291,.300,-.006),Vector4(.019,.300,.308,-.006),Vector4(.044,.286,.295,0),Vector4(.080,.278,.285,.005),Vector4(.128,.268,.272,.008),Vector4(.189,.244,.248,.011),Vector4(.246,.204,.207,.014),Vector4(.287,.153,.156,.014),Vector4(.315,.080,.082,.014),Vector4(.327,.001,.001,.014)],helmet_color,40)
	loft(parent,base,[Vector4(.061,.284,.291,.003),Vector4(.100,.276,.281,.006)],team,40)
	# Two broad painted scuffs, following the dome rather than extra black contours.
	for side in [-1,1]:
		var angle=-PI*.5+side*.55;var points=[]
		for profile in [Vector4(.189,.244,.248,.011),Vector4(.218,.224,.228,.0125),Vector4(.246,.204,.207,.014)]:
			points.append(base+Vector3(cos(angle)*(profile.y+.0015),profile.x,sin(angle)*(profile.z+.0015)+profile.w))
		ribbon(parent,points,.012,helmet_color.darkened(.12),Vector3(-sin(angle),0,cos(angle)))

static func cuff(parent: Node3D,side: int,elbow: Vector3):
	var wrist=Vector3(.025,1.302,-.565) if side==0 else Vector3(.133,1.275,-.255)
	var axis=(wrist-elbow).normalized();var cuff=Node3D.new();parent.add_child(cuff);cuff.position=wrist-elbow-axis*.025;cuff.quaternion=Quaternion(Vector3.UP,axis)
	loft(cuff,Vector3.ZERO,[Vector4(-.067,.110,.108,0),Vector4(-.055,.114,.112,0),Vector4(.025,.094,.092,0),Vector4(.040,.083,.081,0)],Color("586176"),24)

static func hand(parent: Node3D,side: int):
	var skin=Color("e9b780")
	ellipsoid(parent,Vector3(.011,-.012,-.015),Vector3(.058,.065,.060),skin)
	# Readable palm and thumb; grouped fingers wrap the fore-end or pistol grip.
	ellipsoid(parent,Vector3(-.029,.031,-.034),Vector3(.027,.041,.030),skin.lightened(.025))
	for i in range(3):
		var finger=ellipsoid(parent,Vector3(.018,-.036,-.055+i*.029),Vector3(.042,.029,.019),skin.darkened(.025))
		finger.rotation.z=-.15 if side==0 else .15
