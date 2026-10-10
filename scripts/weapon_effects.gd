extends RefCounted
const Art=preload("res://scripts/ink_art.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
const OUTLINE=preload("res://shaders/character_outline.gdshader")
static var meshes: Dictionary={}
static var materials: Dictionary={}
static func material(color: Color,glowing: bool=false) -> StandardMaterial3D:
	var key=color.to_html()+str(glowing)
	if not materials.has(key):
		var m=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=color
		m.emission_enabled=glowing;m.emission=color;m.emission_energy_multiplier=1.5 if glowing else 0.0;materials[key]=m
	return materials[key]
static func outlined_material(color: Color,vertex_color: bool=false) -> StandardMaterial3D:
	var key="outlined/"+color.to_html()+str(vertex_color)
	if not materials.has(key):
		var m=StandardMaterial3D.new();m.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;m.albedo_color=color;m.vertex_color_use_as_albedo=vertex_color
		var outline=ShaderMaterial.new();outline.shader=OUTLINE;outline.set_shader_parameter("ink",Color("493529"));outline.set_shader_parameter("width_pixels",.85);m.next_pass=outline;materials[key]=m
	return materials[key]

static func visible_dimensions(p: Dictionary,kind: String,pixel: float,projected_length: float) -> Vector2:
	if kind in ["grenadeProjectile","vehicleGrenade","rocket","mortar","vehicleMortar","shell"]:
		# Uniform, bounded readability scale preserves the actual silhouette; looking
		# down the flight axis must not stretch a stubby grenade into a golden dart.
		# All calibers share a bounded zoom factor; a per-round pixel floor would
		# make 40/45/75/88 mm converge to the same on-screen diameter again.
		var factor=clampf(pixel/.028*1.45,1.15,1.85)
		return Vector2(float(p.radius),float(p.length))*factor
	if kind in ["bullet","hitscan","autocannon","canister","shell"]:
		var size=Ammo.round_dimensions(p.ammo_visual,pixel)
		if p.ammo_visual.round_shape!="pellet":size.y*=minf(1.35,1.0/maxf(.65,projected_length))
		return size
	var caliber=pow(float(p.radius)/.05,.38)
	return Vector2(maxf(float(p.radius)*2.4,pixel*5.0*caliber),maxf(float(p.length)*1.8,pixel*23.0/maxf(.4,projected_length)))

static func ordnance_mesh(p: Dictionary,kind: String) -> ArrayMesh:
	var key="ordnance/"+kind+"/"+str(p.get("flight_identity",""))+"/"+str(p.radius)+"/"+str(p.length)
	if meshes.has(key):return meshes[key]
	var steel: Color=p.get("nose_color",Color("bcc2ba"));var seam=Color("434a48");var olive: Color=p.get("body_color",Color("788468"));var band: Color=p.get("band_color",Color("bd995e"))
	# Nose at z=0, tail along +Z. Color bands are geometry within one surface.
	var rings: Array=[]
	if kind in ["grenadeProjectile","vehicleGrenade"]:
		rings=[[0,0,steel],[.025,.22,steel],[.10,.52,steel],[.22,.83,olive.lightened(.16)],
			[.35,1.0,olive],[.68,1.0,olive],[.69,1.02,seam],[.73,1.02,seam],
			[.74,1.04,band],[.85,1.04,band],[.86,.96,olive],[.95,.90,olive],[1,.75,seam],[1,0,seam]]
	elif kind in ["mortar","vehicleMortar"]:
		rings=[[0,0,steel],[.06,.28,steel],[.14,.38,steel],[.15,.43,seam],[.29,.88,olive],
			[.42,1,olive],[.50,1,band],[.55,1,band],[.67,.60,olive],[.76,.29,seam],
			[.95,.29,steel.darkened(.2)],[1,.25,seam],[1,0,seam]]
	elif kind=="rocket":
		rings=[[0,0,steel],[.06,.26,steel],[.15,.65,olive.lightened(.12)],[.25,1,olive],
			[.39,.96,olive],[.48,.58,olive],[.49,.58,band],[.54,.58,band],
			[.55,.49,seam],[.87,.49,steel.darkened(.15)],[.90,.55,seam],[1,.55,seam],[1,0,seam]]
	else:
		rings=[[0,0,steel],[.08,.27,steel],[.14,.38,seam],[.32,.89,olive],[.42,1,olive],
			[.76,1,olive],[.77,1.04,band],[.86,1.04,band],[.87,.97,seam],
			[.96,.94,olive],[1,.80,seam],[1,0,seam]]
	for ring in rings:ring[0]*=float(p.length);ring[1]*=float(p.radius)
	meshes[key]=lathe(rings,12)
	return meshes[key]

static func lathe(rings: Array,segments: int=10) -> ArrayMesh:
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	# Godot's clockwise front faces must agree with its primitive meshes.
	var order=[0,1,2,0,2,3] if rings[0][0]>rings.back()[0] else [0,2,1,0,3,2]
	for row in range(rings.size()-1):
		var a: Array=rings[row];var b: Array=rings[row+1]
		for i in range(segments):
			var t=float(i)*TAU/segments;var t2=float(i+1)*TAU/segments
			var points=[Vector3(cos(t)*a[1],sin(t)*a[1],a[0]),Vector3(cos(t2)*a[1],sin(t2)*a[1],a[0]),Vector3(cos(t2)*b[1],sin(t2)*b[1],b[0]),Vector3(cos(t)*b[1],sin(t)*b[1],b[0])]
			var normal=Vector3(cos((t+t2)*.5),sin((t+t2)*.5),0)
			var shade=clampf(.88+normal.dot(Vector3(.35,.75,0))*.22,.66,1.10)
			for k in order:
				var col: Color=a[2] if k<2 else b[2]
				v.append(points[k]);n.append(normal);c.append(Color(col.r*shade,col.g*shade,col.b*shade))
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=v;arrays[Mesh.ARRAY_NORMAL]=n;arrays[Mesh.ARRAY_COLOR]=c
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh

static func casing_mesh(a: Dictionary={}) -> ArrayMesh:
	if a.is_empty():a=Ammo.profile({"id":"default_case","kind":"bullet"})
	var key="case/"+str(a.key)
	if not meshes.has(key):
		var brass: Color=a.case_color;var rim: Color=a.rim_color;var mouth=Color("44382f")
		var neck=.31 if a.case_shape=="bottleneck" else .43
		var rings=[[.50,0.0,mouth],[.50,.12,mouth],[.50,.16,rim],[.50,.50,rim],[.44,.50,rim],
			[.42,.39,brass.darkened(.18)],[.37,.39,brass.darkened(.18)],[.35,.44,brass],[.20,.43,brass],[-.24,.43,brass]]
		if a.case_shape=="shell":
			rings=[[.50,0.0,rim],[.50,.50,rim],[.41,.50,rim],[.40,.45,rim],[.22,.45,rim],[.21,.43,brass],[-.45,.43,brass]]
		elif a.case_shape in ["heavy_bottleneck","autocannon"]:
			neck=.28 if a.case_shape=="heavy_bottleneck" else .34
			# Broad extraction rim, groove, long shoulder and a sooted empty neck.
			rings=[[.50,0.0,mouth],[.50,.12,mouth],[.50,.15,rim],[.50,.50,rim],
				[.445,.50,rim],[.43,.38,brass.darkened(.15)],[.39,.38,brass.darkened(.15)],
				[.37,.45,brass],[.02,.43,brass],[-.23,.41,brass],[-.36,neck,brass],[-.45,neck,brass.darkened(.25)]]
		elif a.case_shape=="artillery":
			neck=.385
			# Tapered large empty case with a wide base, rather than a scaled rifle bottleneck.
			rings=[[.50,0.0,mouth],[.50,.11,mouth],[.50,.14,rim],[.50,.50,rim],
				[.45,.50,rim],[.43,.445,brass],[.30,.44,brass],[-.18,.405,brass],[-.41,neck,brass],[-.45,neck,brass.darkened(.24)]]
		elif a.case_shape=="grenade_case":
			neck=.425
			# Stubby cup with a thick rim and a visibly hollow mouth.
			rings=[[.50,0.0,mouth],[.50,.13,mouth],[.50,.17,rim],[.50,.50,rim],
				[.35,.50,rim],[.31,.44,brass],[.06,.44,brass],[-.42,neck,brass.darkened(.08)],[-.45,neck,brass.darkened(.20)]]
		else:rings.append_array([[-.36,neck,brass],[-.45,neck,brass]])
		rings.append_array([[-.50,neck,rim if a.case_shape!="shell" else brass.lightened(.12)],[-.50,neck*.74,mouth],[-.43,0.0,mouth]])
		meshes[key]=lathe(rings)
	return meshes[key]

static func battle_casing_mesh(a: Dictionary) -> ArrayMesh:
	# A few screen pixels cannot resolve extraction grooves. Preserve caliber,
	# length, colored shell, shoulder and hollow mouth in 72 triangles / one pass.
	var key="battle_case/"+str(a.key)
	if not meshes.has(key):
		var brass: Color=a.case_color;var rim: Color=a.rim_color;var mouth=Color("44382f")
		var neck=.30 if a.case_shape in ["bottleneck","heavy_bottleneck"] else .43
		var rings=[[.50,0.0,rim],[.50,.50,rim],[.30,.44,brass],[-.22,.43,brass],[-.50,neck,brass],[-.50,neck*.72,mouth],[-.44,0.0,mouth]]
		meshes[key]=lathe(rings,6)
	return meshes[key]

static func casing(parent: Node3D,a: Dictionary={}) -> MeshInstance3D:
	var node=MeshInstance3D.new();node.mesh=casing_mesh(a);node.material_override=outlined_material(Color.WHITE,true);node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;parent.add_child(node);return node

static func round_mesh(p: Dictionary) -> ArrayMesh:
	var a: Dictionary=p.ammo_visual;var key="round/"+a.key+"/"+str(p.radius)+"/"+str(p.length)
	if not meshes.has(key):
		var tip: Color=a.tip_color;var jacket: Color=a.round_color;var r: float=p.radius;var h: float=p.length
		# Rounded bright nose, short jacket and bevelled base: readable in flight,
		# visually separate from the dark open mouth of an empty case.
		var taper=.26 if a.round_shape=="pointed" else .20
		var rings=[[0.0,0.0,tip],[h*.07,r*.58,tip],[h*taper,r,tip],[h*.48,r,jacket.lightened(.12)],
			[h*.88,r,jacket],[h*.97,r*.82,jacket.darkened(.12)],[h,0.0,jacket.darkened(.22)]]
		if a.round_shape=="pellet":rings=[[0.0,0.0,tip],[h*.22,r*.82,tip],[h*.50,r,jacket],[h*.80,r*.82,jacket],[h,0.0,jacket.darkened(.18)]]
		elif a.round_shape=="slug":rings=[[0.0,0.0,tip],[0.0,r*.75,tip],[h*.13,r,jacket],[h*.68,r,jacket],[h*.71,r*.82,jacket.darkened(.25)],[h*.80,r,jacket],[h,r,jacket],[h,0.0,jacket]]
		elif a.round_shape=="shell":rings=[[0.0,0.0,tip],[h*.10,r*.38,tip],[h*.35,r,jacket],[h*.76,r,jacket],
			[h*.77,r*1.02,Color("bb8e4e")],[h*.87,r*1.02,Color("dbb46d")],[h*.90,r,jacket],[h,r,jacket],[h,0.0,jacket]]
		meshes[key]=lathe(rings)
	return meshes[key]

static func round_material(a: Dictionary) -> StandardMaterial3D:
	var key="round_material/"+str(a.key)
	if not materials.has(key):
		var mat=outlined_material(Color.WHITE,true).duplicate()
		mat.emission_enabled=true;mat.emission=a.tip_color;mat.emission_energy_multiplier=.13 if a.round_shape=="pellet" else .24
		mat.next_pass=mat.next_pass.duplicate();mat.next_pass.set_shader_parameter("width_pixels",.40)
		materials[key]=mat
	return materials[key]

static func cone(parent: Node3D,radius: float,length: float,color: Color,at: Vector3,tip: float=0.0,glowing: bool=false) -> MeshInstance3D:
	var key=str(radius)+"/"+str(length)+"/"+str(tip)
	if not meshes.has(key):
		var mesh=CylinderMesh.new();mesh.bottom_radius=radius;mesh.top_radius=tip;mesh.height=length;mesh.radial_segments=8;meshes[key]=mesh
	var n=MeshInstance3D.new();n.mesh=meshes[key];n.material_override=material(color,glowing);parent.add_child(n);n.position=at;n.rotation.x=-PI*.5;return n
static func flash(parent: Node3D,w: Dictionary) -> Node3D:
	var p=Profile.get_profile(w);var root=Node3D.new();root.name="MuzzleFlash";parent.add_child(root)
	if p.flash_length<=0:root.hide();return root
	cone(root,p.flash_width,p.flash_length,Color("f5ad52"),Vector3(0,0,-p.flash_length*.5),0,true)
	cone(root,p.flash_width*.50,p.flash_length*.76,Color("fff4cb"),Vector3(0,0,-p.flash_length*.38-.004),0,true)
	# A single rotary bore has a narrow jet; rifle star-spurs crossed adjacent
	# barrels and obscured where this weapon was actually firing.
	if str(w.get("id",""))=="minigun":root.hide();return root
	for i in range(3):
		var spur=cone(root,p.flash_width*.23,p.flash_length*.50,Color("ffe3a0"),Vector3.ZERO,0,true)
		spur.rotation=Vector3(-PI*.5+.42,0,i*TAU/3);spur.position=-spur.basis.y*p.flash_length*.05
	root.hide();return root
static func projectile(parent: Node3D,w: Dictionary,compact: bool=false) -> Node3D:
	var p=Profile.get_profile(w);var root=Node3D.new();parent.add_child(root);root.name="PhysicalRound"
	var body=Node3D.new();body.name="VisibleBody";root.add_child(body)
	var compact_key="projectile/"+str(w.get("id",w.get("mounted_fire_key",w.kind)))+"/"+str(w.get("payload",""))+"/"+str(p.radius)+"/"+str(p.length)
	if compact and meshes.has(compact_key):
		var node=MeshInstance3D.new();node.mesh=meshes[compact_key];node.material_override=projectile_ink();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;body.add_child(node);return root
	if w.kind=="grenade":
		if w.get("payload","")=="smoke":
			Art.cylinder(body,Vector3.ZERO,.065,.19,Color("b3b9a7"));Art.cylinder(body,Vector3(0,.025,0),.067,.040,Color("809587"))
		else:Art.sphere(body,Vector3.ZERO,.085,Color("858967"));Art.cylinder(body,Vector3(0,.025,0),.079,.018,Color("c6b780"))
		Art.box(body,Vector3(.018,.09,0),Vector3(.024,.030,.085),Art.INK,not compact)
	else:
		# The node origin is the nose: the simulation and visible collision tip coincide.
		var round_bullet=w.kind in ["bullet","hitscan","autocannon","canister"]
		if w.kind in ["grenadeProjectile","vehicleGrenade","rocket","mortar","vehicleMortar","shell"]:
			var round_node=MeshInstance3D.new();round_node.mesh=ordnance_mesh(p,w.kind);round_node.material_override=projectile_ink();round_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;body.add_child(round_node)
		elif round_bullet:
			var round_node=MeshInstance3D.new();round_node.mesh=round_mesh(p);round_node.material_override=round_material(p.ammo_visual);round_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;body.add_child(round_node)
		else:
			cone(body,p.radius,p.length*.30,p.color.lightened(.17),Vector3(0,0,p.length*.15),0)
			cone(body,p.radius,p.length*.70,p.color,Vector3(0,0,p.length*.65),p.radius)
		if w.kind in ["rocket","mortar","vehicleMortar"]:
			for i in range(4):
				var fin=Art.box(body,Vector3(p.radius*.75,0,p.length*.88).rotated(Vector3.FORWARD,i*PI*.5),Vector3(p.radius*1.05,.009,p.length*.21),Color("687477"),false);fin.rotation.z=-i*PI*.5
		if w.kind=="rocket":
			var jet=Node3D.new();body.add_child(jet);jet.position.z=p.length;jet.rotation.y=PI
			cone(jet,p.radius*.36,.16,Color("e4aa63"),Vector3(0,0,-.08),0,true)
	if compact:
		# Fuse, colored bands and fins share one cached surface in both ranges.
		# The existing geometry atlas also batches it during campaign play.
		var merged=preload("res://scripts/mesh_batch.gd").collapse(body)
		if merged.size()==1:
			meshes[compact_key]=merged[0].mesh;merged[0].material_override=projectile_ink()
			merged[0].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	return root

static func projectile_ink() -> ShaderMaterial:
	if not materials.has("projectile_ink"):
		var material=Art.ink_material(Color.WHITE,true,0).duplicate()
		material.set_shader_parameter("paper_strength",0.0)
		materials.projectile_ink=material
	return materials.projectile_ink
