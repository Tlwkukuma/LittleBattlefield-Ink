extends RefCounted
## Stylized portable rotary gun. Dimensions are game art, not engineering data.
const Art=preload("res://scripts/ink_art.gd")
const Batch=preload("res://scripts/mesh_batch.gd")
const Magazine=preload("res://scripts/weapon_magazine.gd")
const DARK=Color("303a40")
const STEEL=Color("78858a")
const EDGE=Color("abb6b6")
const RADIUS=.077
const FRONT=-.94
const GRIP=Vector3(.025,-.145,.285)
const SUPPORT=Vector3(-.06,.215,.055)

static func tube(parent: Node3D,at: Vector3,radius: float,length: float,color: Color):
	var part=Art.cylinder(parent,at,radius,length,color);part.rotation.x=PI*.5
	part.mesh.rings=0;part.mesh.radial_segments=12;return part

static func hollow(parent: Node3D,at: Vector3,outer: float,inner: float,length: float,color: Color,segments: int=12):
	# Actual open tube: outside, rear lip, inside and front lip; no solid end cap.
	var section=[Vector2(-length*.5,outer),Vector2(length*.5,outer),Vector2(length*.5,inner),Vector2(-length*.5,inner)]
	var vertices=PackedVector3Array();var normals=PackedVector3Array();var colors=PackedColorArray()
	for side in range(4):
		var a: Vector2=section[side];var b: Vector2=section[(side+1)%4];var slope=b-a
		for i in range(segments):
			var angles=[i*TAU/segments,(i+1)*TAU/segments]
			var points=[];var ns=[]
			for pair in [[a,angles[0]],[a,angles[1]],[b,angles[1]],[b,angles[0]]]:
				var radial=Vector3(cos(pair[1]),sin(pair[1]),0)
				points.append(at+radial*pair[0].y+Vector3(0,0,pair[0].x))
				ns.append((radial*slope.x-Vector3(0,0,slope.y)).normalized())
			for k in [0,2,1,0,3,2]:
				vertices.append(points[k]);normals.append(ns[k]);colors.append(color.darkened(.48) if side==2 else color)
	var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node=Art.mesh_node(parent,mesh,Vector3.ZERO,Color.WHITE);node.material_override=Art.ink_material(Color.WHITE,true,.10)

static func build(root: Node3D,w: Dictionary):
	# Large round breech with stepped end plates; no rifle stock, sight or bipod.
	tube(root,Vector3(0,0,.025),.128,.43,STEEL.darkened(.19))
	for z in [-.195,.215]:tube(root,Vector3(0,0,z),.139,.044,DARK)
	tube(root,Vector3(0,0,.246),.112,.035,STEEL)
	tube(root,Vector3(0,0,-.22),.108,.038,STEEL)
	for side in [-1,1]:
		for z in [-.12,.02,.16]:
			Art.box(root,Vector3(side*.127,.012,z),Vector3(.012,.048,.062),DARK,false)
	# Asymmetric drive motor and a short feed chute make the side view readable.
	tube(root,Vector3(.167,-.025,.045),.061,.32,DARK)
	for z in [-.09,.17]:tube(root,Vector3(.167,-.025,z),.067,.024,STEEL)
	Art.box(root,Vector3(-.16,-.025,-.005),Vector3(.16,.12,.16),DARK,false)
	var mag=Magazine.profile(w);var box=Magazine.build(root,w);box.position=mag.at
	for i in range(5):
		var x=-.105-i*.026
		Art.box(root,Vector3(x,.043,-.005),Vector3(.016,.018,.085),Color("a9986e"),false)
		Art.box(root,Vector3(x,.054,.001),Vector3(.009,.009,.035),DARK,false)
	# Raised bridge has a real gap above the receiver and an offset support grip.
	for z in [-.025,.155]:Art.box(root,Vector3(-.025,.159,z),Vector3(.046,.12,.042),STEEL,false)
	Art.box(root,Vector3(-.025,.215,.065),Vector3(.13,.05,.23),DARK,false)
	for z in [-.015,.015,.045,.075,.105,.135]:
		Art.box(root,Vector3(-.025,.243,z),Vector3(.126,.007,.009),STEEL,false)
	Art.box(root,Vector3(.025,-.067,.252),Vector3(.08,.12,.12),STEEL,false)
	var rear=Art.box(root,GRIP,Vector3(.068,.16,.087),DARK,false);rear.rotation.x=-.16
	for y in [-.19,-.16,-.13]:Art.box(root,Vector3(.025,y,.334),Vector3(.069,.010,.009),STEEL,false)
	Art.box(root,Vector3(.025,-.215,.237),Vector3(.07,.022,.09),STEEL,false)
	Art.box(root,Vector3(.025,-.159,.193),Vector3(.07,.13,.018),STEEL,false)
	# Dark ejection opening stays separate from the ammunition feed.
	Art.box(root,Vector3(.12,-.082,-.08),Vector3(.048,.031,.10),Color("202930"),false)
	root.set_meta("ejection_at",Vector3(.15,-.09,-.08));root.set_meta("magazine_at",mag.at)
	var parts=Node3D.new();root.add_child(parts)
	for i in range(6):
		var angle=PI*.5+i*TAU/6
		var center=Vector3(cos(angle)*RADIUS,sin(angle)*RADIUS,0)
		hollow(parts,center+Vector3(0,0,-.587),.024,.015,.706,STEEL)
		hollow(parts,center+Vector3(0,0,FRONT+.019),.027,.015,.038,EDGE)
		# Recessed dark backstop keeps each muzzle legible in the ink shader.
		tube(parts,center+Vector3(0,0,FRONT+.085),.014,.004,DARK)
	for z in [-.83,-.345]:
		hollow(parts,Vector3(0,0,z),.109,.092,.045,DARK,18)
		for i in range(6):
			var angle=PI*.5+i*TAU/6
			tube(parts,Vector3(cos(angle)*.097,sin(angle)*.097,z-.025),.009,.008,EDGE)
	var rotor=Batch.collapse(parts,[],"minigun_rotor")[0]
	rotor.reparent(root);rotor.name="BarrelRotor";parts.free()
	root.set_meta("primary_muzzle",Vector3(0,RADIUS,FRONT-.004))
	root.set_meta("barrel_count",6)

static func pose(root: Node3D,u: Dictionary,time: float):
	var rotor=root.get_node_or_null("BarrelRotor")
	if rotor==null:return
	# Six firing stations: each actual cartridge turns the cluster one sixth.
	# The existing shot callback evaluates pose at t=0, with a bore at the socket.
	var shots=int(u.get("shot_index",0));var age=maxf(0,time-float(u.get("last_shot",-100)))
	var fraction=smoothstep(0,.05,age) if shots>0 else 0.0
	rotor.rotation.z=fposmod((shots+fraction)*TAU/6,TAU)

static func align_flash(view: Dictionary,u: Dictionary):
	var rotor: Node3D=view.held.get_node("BarrelRotor")
	# The physical firing station is fixed, but the bore that just fired keeps
	# rotating during its short after-flash. Follow THAT bore, not the empty space
	# left at the station. The shot callback samples both at the same t=0 position.
	var barrel=posmod(-int(u.get("shot_index",0)),6)
	var angle=PI*.5+barrel*TAU/6
	var tip=Vector3(cos(angle)*RADIUS,sin(angle)*RADIUS,FRONT-.004)
	view.muzzle.global_position=rotor.to_global(tip)
