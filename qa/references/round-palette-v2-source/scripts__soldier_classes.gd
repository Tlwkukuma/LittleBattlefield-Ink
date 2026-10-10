extends RefCounted
## Modular rigid kit on the supplied helmet/chest attachments; no rig or skin edits.
const Art=preload("res://scripts/ink_art.gd")
const Batch=preload("res://scripts/mesh_batch.gd")
const IDS=["assault","medic","engineer","support","recon"]
const DATA={
	"assault":{"name":"突击兵","accent":Color("c4aa68"),"description":"紧凑战斗背包 · 胸前弹匣 · 头盔双箭标","weapon":"m416"},
	"medic":{"name":"医疗兵","accent":Color("6ca69b"),"description":"白色医疗包 · 绿色医疗标识 · 绷带卷","weapon":"ump-45"},
	"engineer":{"name":"工程兵","accent":Color("c99558"),"description":"护目镜 · 工具背包 · 扳手与工具袋","weapon":"mp5k"},
	"support":{"name":"支援兵","accent":Color("b5a575"),"description":"宽型弹药背架 · 双侧弹箱 · 弹链","weapon":"m249"},
	"recon":{"name":"侦察兵","accent":Color("8eaa91"),"description":"围巾 · 望远镜 · 无线电与短天线","weapon":"awm"}
}
const DARK=Color("4c4854")
const CANVAS=Color("99957e")
const WHITE=Color("dbdbd5")
static var rounded_meshes: Dictionary={}

static func profile(id: String) -> Dictionary:return DATA.get(id,DATA.assault)

static func rounded(parent: Node3D,at: Vector3,size: Vector3,color: Color,bevel: float=.025) -> MeshInstance3D:
	var key=str(size)+"/"+str(bevel)
	if not rounded_meshes.has(key):
		var box=BoxMesh.new();box.size=size;box.subdivide_width=1;box.subdivide_height=1;box.subdivide_depth=1
		var arrays=box.get_mesh_arrays();var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals=PackedVector3Array()
		var edge=minf(bevel,minf(size.x,minf(size.y,size.z))*.45);var inner=size*.5-Vector3.ONE*edge
		for i in range(points.size()):
			var core=points[i].clamp(-inner,inner);var normal=(points[i]-core).normalized()
			points[i]=core+normal*edge;normals.append(normal)
		arrays[Mesh.ARRAY_VERTEX]=points;arrays[Mesh.ARRAY_NORMAL]=normals
		var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);rounded_meshes[key]=mesh
	var node=Art.mesh_node(parent,rounded_meshes[key],at,color);node.material_override=Art.ink_material(color)
	return node

static func kit_cylinder(parent: Node3D,at: Vector3,radius: float,height: float,color: Color) -> MeshInstance3D:
	# At battle scale these are stitching, straps and pouch rolls. Eight sides
	# retain the silhouette without the previous 16-sided detail on every kit.
	var node=Art.cylinder(parent,at,radius,height,color)
	node.mesh.radial_segments=8
	return node

static func bar(parent: Node3D,a: Vector3,b: Vector3,width: float,color: Color):
	var node=kit_cylinder(parent,(a+b)*.5,width*.5,a.distance_to(b),color)
	if a.distance_squared_to(b)>.00001:node.quaternion=Quaternion(Vector3.UP,(b-a).normalized())

static func cross_mark(parent: Node3D,at: Vector3,size: float,color: Color,top: bool=false):
	var node=Node3D.new();parent.add_child(node);node.position=at
	if top:node.rotation.x=-PI*.5
	rounded(node,Vector3.ZERO,Vector3(size*.32,size,.008),color,.003)
	rounded(node,Vector3.ZERO,Vector3(size,size*.32,.01),color,.003)

static func pouch(parent: Node3D,at: Vector3,size: Vector3,color: Color):
	var front=-1.0 if at.z<-.15 else 1.0
	rounded(parent,at,size,color)
	rounded(parent,at+Vector3(0,size.y*.28,size.z*.49*front),Vector3(size.x*.94,size.y*.27,.026),color.lightened(.08),.009)
	rounded(parent,at+Vector3(0,-size.y*.03,size.z*.52*front),Vector3(.037,.065,.024),DARK,.006)

static func helmet(root: Node3D,id: String,team: int):
	var color: Color=profile(id).accent
	match id:
		"medic":
			rounded(root,Vector3(0,-.005,-.345),Vector3(.24,.16,.025),WHITE,.02)
			cross_mark(root,Vector3(0,-.005,-.361),.115,color)
			rounded(root,Vector3(0,.205,0),Vector3(.18,.016,.18),WHITE,.006)
			cross_mark(root,Vector3(0,.217,0),.13,color,true)
		"engineer":
			for side in [-1,1]:
				var frame=rounded(root,Vector3(side*.115,-.01,-.328),Vector3(.205,.125,.086),DARK,.032);frame.rotation.y=side*-.16
				var lens=rounded(root,Vector3(side*.115,-.008,-.377),Vector3(.15,.077,.025),Color("9bafb0"),.018);lens.rotation.y=side*-.16
				rounded(root,Vector3(side*.304,-.015,-.12),Vector3(.045,.08,.18),DARK,.012)
			bar(root,Vector3(-.04,-.012,-.36),Vector3(.04,-.012,-.36),.028,color)
		"support":
			for side in [-1,1]:rounded(root,Vector3(side*.35,-.11,.0),Vector3(.075,.15,.12),DARK,.03)
			rounded(root,Vector3(0,.035,-.335),Vector3(.16,.075,.026),color,.012)
			for x in [-.045,0,.045]:bar(root,Vector3(x,.02,-.352),Vector3(x,.05,-.352),.014,DARK)
		"recon":
			# Small cloth panels keep the team band and original helmet silhouette readable.
			for side in [-1,1]:
				var panel=rounded(root,Vector3(side*.255,.04,.08),Vector3(.13,.035,.30),color,.017);panel.rotation.z=side*-.40
			rounded(root,Vector3(.325,-.11,-.07),Vector3(.075,.115,.11),DARK,.025)
			bar(root,Vector3(.34,-.13,-.08),Vector3(.24,-.20,-.25),.018,DARK)
		_:
			for y in [.012,.057]:
				bar(root,Vector3(-.05,y+.015,-.345),Vector3(0,y-.012,-.36),.014,color)
				bar(root,Vector3(0,y-.012,-.36),Vector3(.05,y+.015,-.345),.014,color)
	# Side team marker remains independent of the profession's small accent colour.
	rounded(root,Vector3(-.34,-.08,.04),Vector3(.018,.065,.12),Art.RED if team==1 else Art.BLUE,.006)

static func equipment(root: Node3D,id: String,team: int):
	var accent: Color=profile(id).accent;var cloth=(Art.RED if team==1 else Art.BLUE).lerp(Color("b9bec5"),.53)
	# Chest attachments share the original Backpack/Spine02 rigid frame.
	# Its origin is ~1.07 m high, 0.22 m behind the body; front is negative Z.
	match id:
		"medic":
			pouch(root,Vector3(0,.02,.025),Vector3(.48,.53,.29),WHITE)
			rounded(root,Vector3(0,-.025,.188),Vector3(.25,.24,.026),WHITE.darkened(.05),.018)
			cross_mark(root,Vector3(0,-.025,.208),.17,accent)
			for x in [-.29,.29]:
				kit_cylinder(root,Vector3(x,.02,.025),.072,.24,WHITE)
				rounded(root,Vector3(x,.02,.099),Vector3(.07,.06,.012),accent,.004)
			pouch(root,Vector3(-.28,-.16,-.23),Vector3(.16,.20,.14),WHITE)
			cross_mark(root,Vector3(-.28,-.16,-.31),.09,accent)
			rounded(root,Vector3(0,.24,-.41),Vector3(.16,.105,.026),WHITE,.014)
			cross_mark(root,Vector3(0,.24,-.43),.07,accent)
		"engineer":
			pouch(root,Vector3(0,0,.02),Vector3(.47,.49,.28),Color("9b856c"))
			for x in [-.14,0,.14]:pouch(root,Vector3(x,-.09,.20),Vector3(.115,.21,.095),accent.darkened(.12))
			# Large open-ended spanner readable from the usual rear camera angle.
			bar(root,Vector3(.24,-.18,.20),Vector3(.24,.30,.20),.044,Color("b3b6bb"))
			bar(root,Vector3(.24,.29,.20),Vector3(.18,.35,.20),.039,Color("b3b6bb"))
			bar(root,Vector3(.24,.29,.20),Vector3(.30,.35,.20),.039,Color("b3b6bb"))
			rounded(root,Vector3(-.29,-.04,.06),Vector3(.12,.31,.17),DARK,.025)
			bar(root,Vector3(-.29,.10,.11),Vector3(-.29,.28,.11),.025,Color("b0b1b6"))
			pouch(root,Vector3(.25,-.15,-.26),Vector3(.18,.20,.14),accent)
			for x in [-.095,.095]:pouch(root,Vector3(x,.10,-.42),Vector3(.14,.15,.08),Color("a79275"))
		"support":
			rounded(root,Vector3(0,.015,.015),Vector3(.51,.57,.29),CANVAS,.045)
			for side in [-1,1]:
				pouch(root,Vector3(side*.28,-.07,.08),Vector3(.17,.31,.24),Color("858878"))
				rounded(root,Vector3(side*.16,.02,.18),Vector3(.045,.51,.025),DARK,.008)
			pouch(root,Vector3(0,.08,.22),Vector3(.24,.24,.13),accent)
			for i in range(8):
				var x=-.17+i*.045;var y=.26-i*.025
				bar(root,Vector3(x,y,-.427),Vector3(x,y+.055,-.427),.023,Color("bca66d"))
			for side in [-1,1]:pouch(root,Vector3(side*.19,-.17,-.28),Vector3(.20,.22,.16),CANVAS)
		"recon":
			pouch(root,Vector3(0,.025,.015),Vector3(.38,.52,.26),Color("7f897c"))
			rounded(root,Vector3(.24,.075,.06),Vector3(.115,.30,.18),DARK,.016)
			bar(root,Vector3(.26,.18,.12),Vector3(.30,.66,.12),.013,DARK)
			rounded(root,Vector3(.26,.24,.12),Vector3(.06,.055,.10),accent,.012)
			# Soft short scarf and two binocular barrels at the upper chest.
			rounded(root,Vector3(0,.31,-.225),Vector3(.39,.105,.27),accent,.045)
			var tail=rounded(root,Vector3(-.14,.14,-.402),Vector3(.10,.24,.036),accent.darkened(.08),.012);tail.rotation.z=-.12
			for side in [-1,1]:
				var optic=kit_cylinder(root,Vector3(side*.058,.18,-.418),.044,.14,DARK);optic.rotation.x=PI*.5
				var lens=kit_cylinder(root,Vector3(side*.058,.18,-.493),.036,.012,Color("9faeb2"));lens.rotation.x=PI*.5
			bar(root,Vector3(-.06,.18,-.42),Vector3(.06,.18,-.42),.033,DARK)
		_:
			pouch(root,Vector3(0,.02,.02),Vector3(.43,.46,.25),CANVAS)
			var roll=kit_cylinder(root,Vector3(0,.325,.02),.10,.46,CANVAS.lightened(.1));roll.rotation.z=PI*.5
			for side in [-1,1]:rounded(root,Vector3(side*.135,.325,.02),Vector3(.035,.207,.21),DARK,.014)
			for x in [-.13,0,.13]:pouch(root,Vector3(x,.02,-.42),Vector3(.105,.20,.075),Color("8f8e7f"))
			pouch(root,Vector3(.27,-.17,-.19),Vector3(.15,.18,.13),CANVAS)
	# Rear team tab and backpack stitching keep friends/enemies legible in every kit.
	rounded(root,Vector3(0,-.18,.183 if id!="support" else .175),Vector3(.13,.042,.018),Art.RED if team==1 else Art.BLUE,.006)
	for side in [-1,1]:rounded(root,Vector3(side*.20,.14,-.31),Vector3(.048,.30,.04),cloth.darkened(.20),.013)

static func apply(view: Dictionary,id: String,team: int):
	if not view.get("source_rig",false):return
	if not DATA.has(id):id="assault"
	var key=id+"/"+str(team)
	if view.get("class_key","")==key:return
	view.class_key=key
	var pack: MeshInstance3D=view.backpack
	if not view.has("base_pack_mesh"):view.base_pack_mesh=pack.mesh
	pack.mesh=null
	for entry in [[view.helmet,"ClassHelmet"],[pack,"ClassEquipment"]]:
		var old=entry[0].get_node_or_null(entry[1])
		if old!=null:old.free()
		var node=Node3D.new();node.name=entry[1];entry[0].add_child(node)
		if entry[1]=="ClassHelmet":helmet(node,id,team)
		else:equipment(node,id,team)
		for mesh in Batch.collapse(node,[],"class/"+key+"/"+entry[1]):
			mesh.material_override.set_shader_parameter("silhouette",true)
