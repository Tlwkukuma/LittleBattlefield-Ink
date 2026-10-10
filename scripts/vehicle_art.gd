extends RefCounted
## Original vehicle geometry for the existing joint proving ground.
## Local -Z is forward; hull and turret have independent yaw, guns independent recoil.
const Art = preload("res://scripts/ink_art.gd")
const Appearance = preload("res://scripts/vehicle_appearance_state.gd")
const Dimensions = preload("res://scripts/vehicle_dimensions.gd")
const Style = preload("res://scripts/vehicle_style.gd")
const Rig = preload("res://scripts/vehicle_weapon_rig.gd")
const TrackMesh = preload("res://scripts/vehicle_track_mesh.gd")
const HULL = Style.HULL
const LIGHT = Style.LIGHT
const DARK = Style.DARK
const STEEL = Style.STEEL
const RUBBER = Style.RUBBER
const GLASS = Style.GLASS
const CLOTH = Style.CLOTH

static func node(parent: Node3D, title: String, at: Vector3 = Vector3.ZERO) -> Node3D:
	var part = Node3D.new()
	part.name = title
	part.position = at
	parent.add_child(part)
	return part

static func build(parent: Node3D, v: Dictionary) -> Dictionary:
	var root = Appearance.new()
	root.name = "Vehicle_" + str(v.type)
	root.vehicle = v
	parent.add_child(root)
	root.prepare_materials()
	var body = node(root, "Hull")
	var yaw = node(root, "TurretPivot")
	var dimensions = Dimensions.for_vehicle(v)
	var turret = node(yaw, "TurretArt",-Dimensions.turret_offset(v)/dimensions.model_scale)
	var wheels: Array = []
	# Authoring radius stays stable; presentation and collision share the final dimensions.
	var r: float = float(v.profile.get("radius",35))/40.0
	var kind: String = v.type
	var turret_height: float = 1.18
	match kind:
		"truck":
			preload("res://scripts/hanlue_truck.gd").build(body,wheels)
		"armedJeep":
			jeep(body, turret, r, wheels)
			turret_height = 1.62
		"scoutCar":
			scout(body, turret, r, wheels)
			turret_height = 1.19
		"apc":
			carrier(body, turret, r, wheels, root)
			turret_height = 1.55
		"ifv":
			infantry_vehicle(body, turret, r, wheels, root)
			turret_height = 1.20
		_:
			tank(body, turret, r, kind, wheels, root)
			turret_height = 1.17 if kind == "lightTank" else 1.33 if kind == "tank" else 1.45
	var channels = weapons(turret, kind, r, turret_height, v.profile.weapons)
	if kind!="truck":identification(body,turret,kind,r,Style.Livery.team_id(v.get("team",-1)))
	wear_layers(body, r, kind, root)
	var keep: Array = wheels + root.wear + root.intact_tracks + root.broken_tracks
	root.finish_group(body, keep)
	var weapon_pivots: Array=[]
	for mode in channels:
		var c: Dictionary=channels[mode]
		if c.pivot in weapon_pivots:continue
		weapon_pivots.append(c.pivot)
		root.finish_group(c.slide,[c.muzzle,c.ejection])
	root.finish_group(turret,weapon_pivots)
	for wheel in wheels: root.finish_group(wheel)
	for layer in root.wear + root.intact_tracks + root.broken_tracks:
		root.finish_group(layer)
	body.scale = dimensions.model_scale
	yaw.scale = dimensions.model_scale
	Style.shadow(body,Vector2(dimensions.half.y*2/dimensions.model_scale.x,dimensions.half.x*2/dimensions.model_scale.z))
	var view={"root":root,"body":body,"turret":yaw,"channels":channels,"wheels":wheels,"appearance":root}
	Rig.update(view,v,0.0)
	return view

static func identification(body: Node3D, turret: Node3D, kind: String, r: float, team: int) -> void:
	match kind:
		"armedJeep":
			# Door plates lie on the exposed outer door skin, below the side windows.
			for side in [-1,1]:
				Style.recognition(body,Vector3(side*(r*.65+.037),.79,r*.36),Vector2(r*.56,.17),team,Vector3(side,0,0))
			Style.recognition(body,Vector3(0,1.436,r*.65),Vector2(r*.53,r*.22),team)
		"scoutCar":Style.recognition(turret,Vector3(0,1.316,-r*.17),Vector2(r*.48,r*.23),team)
		"apc":
			Style.recognition(body,Vector3(0,.85,r*1.31+.017),Vector2(r*.48,.25),team,Vector3.BACK)
			Style.recognition(body,Vector3(-r*.29,1.246,-r*.41),Vector2(r*.42,r*.24),team)
		"ifv":
			Style.recognition(body,Vector3(0,.75,r*1.265+.024),Vector2(r*.45,.22),team,Vector3.BACK)
			Style.recognition(turret,Vector3(-r*.14,1.346,-r*.25),Vector2(r*.39,r*.19),team)
		_:
			var top: float=1.30 if kind=="lightTank" else 1.56 if kind=="heavyTank" else 1.48
			Style.recognition(turret,Vector3(0,top-.004,-r*.32),Vector2(r*.40,r*.20),team)

static func beam(parent: Node3D, a: Vector3, b: Vector3, radius: float, color: Color = STEEL) -> Node3D:
	var tube = Art.cylinder(parent, (a+b)*.5, radius, a.distance_to(b), color)
	tube.quaternion = Quaternion(Vector3.UP, (b-a).normalized())
	return tube

static func plate(parent: Node3D, at: Vector3, lower: Vector3, upper: Vector3, offset: float, color: Color = HULL, bevel: float = .16) -> Node3D:
	return Style.plate(parent,at,lower,upper,offset,color,maxf(.18,bevel))

static func face(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, corners: Array, color: Color) -> void:
	var n: Vector3 = (corners[1]-corners[0]).cross(corners[2]-corners[0]).normalized()
	for k in ([0,2,1] if corners.size() == 3 else [0,2,1,0,3,2]):
		vertices.append(corners[k])
		normals.append(n)
		colors.append(color)

static func hatch(parent: Node3D, at: Vector3, radius: float, round_shape: bool = true) -> void:
	if round_shape:
		Art.cylinder(parent, at, radius, .045, DARK)
		Art.cylinder(parent, at+Vector3(0,.035,0), radius*.87, .035, LIGHT)
	else:
		Style.box(parent, at, Vector3(radius*2,.04,radius*2.4), DARK)
		Style.box(parent, at+Vector3(0,.028,0), Vector3(radius*1.84,.035,radius*2.22), LIGHT)
	beam(parent, at+Vector3(-.07,.083,0), at+Vector3(.07,.083,0), .015, Style.INK)
	for x in [-1,1]: Style.box(parent, at+Vector3(x*radius*.6,.04,radius*.7), Vector3(.075,.025,.055), STEEL, false)

static func grille(parent: Node3D, at: Vector3, width: float, depth: float) -> void:
	Style.box(parent, at, Vector3(width,.028,depth), DARK)
	for i in range(5):
		Style.box(parent, at+Vector3(0,.02,(float(i)/4-.5)*depth*.82), Vector3(width*.86,.024,.026), STEEL, false)

static func antenna(parent: Node3D, at: Vector3, length: float) -> void:
	Art.cylinder(parent, at, .032, .10, DARK)
	beam(parent, at, at+Vector3(-.035,length,.06), .007, Style.INK)

static func stowage(parent: Node3D, at: Vector3, size: Vector3, color: Color = CLOTH) -> void:
	plate(parent, at-size*Vector3(0,.5,0), size, Vector3(size.x*.94,size.y,size.z*.96), 0, color, .25)
	for side in [-1,1]:
		Style.box(parent, at+Vector3(side*size.x*.25,size.y*.5+.006,0), Vector3(.025,.012,size.z*.94), DARK, false)

static func lamps(parent: Node3D, r: float, height: float, nose: float) -> void:
	for side in [-1,1]:
		var at = Vector3(side*r*.49,height,nose)
		beam(parent,at+Vector3(0,0,.025),at-Vector3(0,0,.035),.082,DARK)
		beam(parent,at-Vector3(0,0,.04),at-Vector3(0,0,.05),.059,Color("ded3c6"))
		Style.box(parent,Vector3(side*r*.48,.54,r*1.29),Vector3(.08,.09,.032),Color("916776"),false)
	Style.box(parent,Vector3(0,height-.17,nose-.012),Vector3(r*1.22,.065,.07),STEEL)
	for side in [-1,1]:
		beam(parent,Vector3(side*r*.39,height-.21,nose),Vector3(side*r*.39,height-.29,nose-.055),.023,Style.INK)

static func tire(parent: Node3D, at: Vector3, radius: float, width: float, wheels: Array) -> Node3D:
	var wheel = node(parent, "Wheel", at)
	wheel.rotation.z = PI*.5
	Style.tire(wheel,radius,width,RUBBER)
	for side in [-1,1]:
		Art.cylinder(wheel,Vector3(0,side*(width*.5+.005),0),radius*.67,.025,Style.INK)
		Art.cylinder(wheel,Vector3(0,side*(width*.5+.022),0),radius*.49,.025,STEEL)
		Art.cylinder(wheel,Vector3(0,side*(width*.5+.041),0),radius*.18,.026,DARK)
	for i in range(12):
		var a = float(i)*TAU/12
		var tread = Style.box(wheel,Vector3(cos(a)*radius*.96,0,sin(a)*radius*.96),Vector3(radius*.27,width*.92,.028),DARK,false)
		tread.rotation.y = -a+PI*.5
	wheels.append(wheel)
	return wheel

static func road_gear(parent: Node3D, r: float, wheels: Array, root: Node3D, count: int, skirt: bool = false) -> void:
	var radius: float = .23
	var length: float = r*2.62
	for side in [-1,1]:
		var x: float = side*r*.74
		var track = node(parent,"Track")
		var half_width: float = r*.145
		# Both side rims have thickness; the center remains open around the road wheels.
		var skin=Art.mesh_node(track,TrackMesh.build(r),Vector3(x,0,0),Color.WHITE)
		skin.material_override=Art.ink_material(Color.WHITE,true)
		# A short forward section visibly drops when this vehicle loses its tracks.
		var segment = node(parent,"TrackFrontSection")
		for i in range(17):
			var z: float = -length*.39 + float(i)/16*length*.78
			var holder: Node3D = segment if i < 3 and side == -1 else track
			Style.box(holder,Vector3(x,.625,z),Vector3(r*.31,.028,.055),STEEL,false)
			# Small shoe ends keep the lower belt legible from either side.
			for edge in [-1,1]:Style.box(track,Vector3(x+edge*half_width,.069,z),Vector3(.010,.035,.025),STEEL,false)
		root.intact_tracks.append(segment)
		var broken = node(parent,"ThrownTrack")
		for i in range(5):
			var link=Style.box(broken,Vector3(x+side*i*.025,.10+absf(i-2)*.025,-length*.30-i*.10),Vector3(r*.30,.042,.086),RUBBER)
			link.rotation.x=(i-2)*.18
		root.broken_tracks.append(broken)
		for i in range(count):
			var z: float = lerpf(-length*.5+.30,length*.5-.30,float(i)/(count-1))
			var wheel=node(parent,"RoadWheel",Vector3(x+side*half_width*.72,.33,z))
			wheel.rotation.z=PI*.5
			Art.cylinder(wheel,Vector3.ZERO,radius,.068,RUBBER)
			Art.cylinder(wheel,Vector3(0,-side*.04,0),radius*.80,.025,HULL)
			Art.cylinder(wheel,Vector3(0,-side*.06,0),radius*.28,.028,DARK)
			for spoke in range(4):
				var a: float = spoke*PI*.5
				Art.line(wheel,Vector3(0,-side*.077,0),Vector3(cos(a)*radius*.61,-side*.077,sin(a)*radius*.61),STEEL)
			wheels.append(wheel)
		Style.box(parent,Vector3(x,.71,0),Vector3(r*.34,.062,length*1.01),Style.ACCENT)
		if skirt:
			for i in range(5):
				plate(parent,Vector3(x+side*r*.17,.42,-length*.35+i*length*.175),Vector3(.045,0,length*.16),Vector3(.045,.30,length*.16),0,LIGHT if i%2==0 else HULL,.05)

static func jeep(body: Node3D, turret: Node3D, r: float, wheels: Array) -> void:
	Style.box(body,Vector3(0,.38,0),Vector3(r*1.32,.12,r*2.55),DARK)
	Style.box(body,Vector3(0,.55,.20*r),Vector3(r*1.30,.22,r*1.96),HULL)
	plate(body,Vector3(0,.57,-.82*r),Vector3(r*1.22,0,r*.99),Vector3(r*1.08,.25,r*.90),.02,HULL,.13)
	# Covered cab supports the compact infantry-first scale without exposed empty seats.
	plate(body,Vector3(0,.79,.23*r),Vector3(r*1.27,0,r*1.42),Vector3(r*1.16,.61,r*1.42),0,CLOTH,.08)
	Style.box(body,Vector3(0,1.405,.23*r),Vector3(r*1.24,.055,r*1.49),CLOTH)
	for side in [-1,1]:
		for z in [-r*.84,r*.86]:
			tire(body,Vector3(side*r*.73,.29,z),.29,r*.26,wheels)
			Style.box(body,Vector3(side*r*.70,.66,z),Vector3(r*.37,.055,.72),Style.ACCENT)
		Style.box(body,Vector3(side*r*.65,.78,.36*r),Vector3(.065,.24,r*1.45),HULL)
		# Opaque, narrow windows imply an enclosed interior at this viewing distance.
		Style.box(body,Vector3(side*r*.614,1.18,.12*r),Vector3(.016,.21,r*.56),DARK,false)
		Style.box(body,Vector3(side*r*.627,1.18,.10*r),Vector3(.010,.15,r*.45),GLASS,false)
		Art.line(body,Vector3(side*r*.646,.84,-.28*r),Vector3(side*r*.594,1.34,-.28*r),DARK)
		Art.line(body,Vector3(side*r*.646,.84,.50*r),Vector3(side*r*.594,1.34,.50*r),DARK)
		beam(body,Vector3(side*r*.65,1.035,.33*r),Vector3(side*r*.65,1.035,.46*r),.014,Style.INK)
	Style.box(body,Vector3(0,.93,-.37*r),Vector3(r*1.12,.23,.09),DARK)
	for side in [-1,1]:
		Style.box(body,Vector3(side*r*.30,1.18,-.495*r),Vector3(r*.49,.25,.022),DARK,false)
		Style.box(body,Vector3(side*r*.30,1.19,-.511*r),Vector3(r*.43,.18,.009),GLASS,false)
		Art.line(body,Vector3(side*r*.18,1.15,-.522*r),Vector3(side*r*.38,1.23,-.522*r),LIGHT)
	beam(body,Vector3(-r*.59,1.39,-.47*r),Vector3(r*.59,1.39,-.47*r),.022)
	beam(body,Vector3(0,1.03,-.52*r),Vector3(0,1.36,-.52*r),.017)
	Style.box(body,Vector3(0,1.19,.945*r),Vector3(r*.66,.16,.022),DARK,false)
	# Vertical front radiator, spare wheel, strapped rear fuel can.
	Style.box(body,Vector3(0,.60,-r*1.31),Vector3(r*.77,.24,.028),DARK)
	for i in range(7):Style.box(body,Vector3((i-3)*r*.1,.60,-r*1.332),Vector3(.023,.20,.016),LIGHT,false)
	var spare: Array=[]
	var spare_wheel=tire(body,Vector3(.14,.89,r*1.28),.255,.15,spare)
	spare_wheel.rotation=Vector3(PI*.5,0,0)
	stowage(body,Vector3(-.36,.82,r*1.20),Vector3(.20,.35,.16),STEEL)
	lamps(body,r,.69,-r*1.33)
	antenna(body,Vector3(-r*.57,.99,r*.89),.64)
	Art.cylinder(turret,Vector3(0,1.445,0),.19,.045,DARK)
	beam(turret,Vector3(0,1.46,0),Vector3(0,1.58,0),.034,DARK)
	Style.box(turret,Vector3(.14,1.59,.08),Vector3(.10,.075,.10),GLASS)

static func scout(body: Node3D, turret: Node3D, r: float, wheels: Array) -> void:
	plate(body,Vector3(0,.36,0),Vector3(r*1.44,0,r*2.64),Vector3(r*1.23,.37,r*2.30),.08*r,HULL)
	plate(body,Vector3(0,.73,-.13*r),Vector3(r*1.24,0,r*1.98),Vector3(r*.92,.27,r*1.38),.13*r,LIGHT)
	for side in [-1,1]:
		for z in [-r*.86,r*.85]:
			tire(body,Vector3(side*r*.74,.31,z),.31,r*.26,wheels)
			Style.box(body,Vector3(side*r*.73,.70,z),Vector3(r*.37,.055,.71),Style.ACCENT)
		Style.box(body,Vector3(side*r*.34,.92,-r*.78),Vector3(.22,.072,.036),Style.INK)
		stowage(body,Vector3(side*r*.62,.70,.1*r),Vector3(.12,.22,.41),STEEL)
	grille(body,Vector3(0,.755,r*.92),r*.75,r*.39)
	Art.cylinder(turret,Vector3(0,1.015,0),r*.43,.07,DARK)
	plate(turret,Vector3(0,1.04,0),Vector3(r*.97,0,r*1.03),Vector3(r*.75,.27,r*.80),r*.06,HULL,.37)
	hatch(turret,Vector3(0,1.33,r*.12),r*.20)
	antenna(turret,Vector3(-r*.32,1.30,r*.28),.69)
	lamps(body,r,.66,-r*1.31)

static func carrier(body: Node3D, turret: Node3D, r: float, wheels: Array, root: Node3D) -> void:
	road_gear(body,r,wheels,root,5)
	plate(body,Vector3(0,.39,0),Vector3(r*1.38,0,r*2.62),Vector3(r*1.28,.81,r*2.22),r*.15,HULL,.06)
	Style.box(body,Vector3(0,1.215,r*.29),Vector3(r*1.20,.052,r*1.62),LIGHT)
	for side in [-1,1]:
		hatch(body,Vector3(side*r*.31,1.258,r*.32),r*.23,false)
		Style.box(body,Vector3(side*r*.635,.88,r*.55),Vector3(.025,.35,r*.50),STEEL)
		for i in range(3):Style.box(body,Vector3(side*r*.65,.96,-r*.2+i*r*.41),Vector3(.029,.065,.13),Style.INK)
		stowage(body,Vector3(side*r*.61,.88,-r*.20),Vector3(.13,.27,.33))
	# Rear troop ramp and hinges are visible when driving away.
	Style.box(body,Vector3(0,.82,r*1.286),Vector3(r*1.05,.76,.035),DARK)
	Style.box(body,Vector3(0,.83,r*1.31),Vector3(r*.96,.66,.025),LIGHT)
	for side in [-1,1]:Style.box(body,Vector3(side*r*.32,.50,r*1.337),Vector3(.16,.08,.06),STEEL)
	beam(body,Vector3(-.12,.97,r*1.35),Vector3(.12,.97,r*1.35),.018)
	grille(body,Vector3(r*.31,1.245,-r*.53),r*.34,r*.38)
	Art.cylinder(turret,Vector3(0,1.25,0),r*.30,.07,DARK)
	# Pedestal remains at the yaw origin; offset crew hatch belongs to the hull.
	beam(turret,Vector3.ZERO+Vector3(0,1.2,0),Vector3(0,1.48,0),.044)
	plate(turret,Vector3(0,1.36,-r*.20),Vector3(r*.74,0,.065),Vector3(r*.60,.33,.065),.025,LIGHT,.2)
	antenna(body,Vector3(-r*.52,1.27,r*.95),.65)
	lamps(body,r,.74,-r*1.26)

static func infantry_vehicle(body: Node3D, turret: Node3D, r: float, wheels: Array, root: Node3D) -> void:
	road_gear(body,r,wheels,root,6)
	plate(body,Vector3(0,.38,0),Vector3(r*1.48,0,r*2.65),Vector3(r*1.24,.55,r*1.93),r*.25,HULL,.15)
	for side in [-1,1]:
		for i in range(3):
			Style.box(body,Vector3(side*r*.64,.86,r*.18+i*r*.32),Vector3(.033,.085,.16),Style.INK)
			Style.box(body,Vector3(side*r*.70,.65,r*.18+i*r*.32),Vector3(.055,.21,r*.25),LIGHT)
		hatch(body,Vector3(side*r*.31,.955,r*.70),r*.19,false)
		antenna(body,Vector3(side*r*.54,.99,r*.99),.65 if side < 0 else .46)
	grille(body,Vector3(-r*.38,.96,-r*.31),r*.28,r*.54)
	Art.cylinder(turret,Vector3(0,.955,-r*.13),r*.43,.075,DARK)
	plate(turret,Vector3(0,.99,-r*.13),Vector3(r*1.02,0,r*1.05),Vector3(r*.72,.35,r*.81),r*.09,LIGHT,.36)
	hatch(turret,Vector3(r*.13,1.36,r*.08),r*.19)
	smoke_launchers(turret,r,1.17,-r*.02)
	Style.box(body,Vector3(0,.72,r*1.265),Vector3(r*.92,.52,.04),STEEL)
	lamps(body,r,.64,-r*1.31)

static func tank(body: Node3D, turret: Node3D, r: float, kind: String, wheels: Array, root: Node3D) -> void:
	var heavy: bool = kind == "heavyTank"
	var light: bool = kind == "lightTank"
	var deck: float = .84 if light else .95 if heavy else .90
	road_gear(body,r,wheels,root,5 if light else 7 if heavy else 6,heavy)
	plate(body,Vector3(0,.38,0),Vector3(r*1.45,0,r*2.62),Vector3(r*1.22,deck-.38,r*2.14),r*.10,HULL,.18)
	for side in [-1,1]:
		grille(body,Vector3(side*r*.31,deck+.014,r*.85),r*.46,r*.46)
		stowage(body,Vector3(side*r*.67,deck+.018,r*.42),Vector3(r*.23,.19,r*.54))
		beam(body,Vector3(side*r*.60,deck+.04,-r*.05),Vector3(side*r*.60,deck+.04,-r*.63),.018,STEEL)
		Style.box(body,Vector3(side*r*.60,deck+.045,-r*.61),Vector3(.10,.025,.15),DARK,false)
		beam(body,Vector3(side*r*.43,.55,r*1.25),Vector3(side*r*.43,.73,r*1.30),.053,DARK)
	Art.cylinder(turret,Vector3(0,deck+.05,-r*.16),r*.49,.10,DARK)
	var top: float
	if heavy:
		plate(turret,Vector3(0,deck+.10,-r*.10),Vector3(r*1.18,0,r*1.37),Vector3(r*.98,.50,r*1.18),r*.08,HULL,.24)
		top=deck+.61
		Style.box(turret,Vector3(0,1.44,-r*.77),Vector3(r*.66,.29,.18),LIGHT)
		for i in range(5):
			var link=Style.box(body,Vector3((i-2)*r*.17,deck*.75,-r*1.13),Vector3(r*.14,.14,.045),DARK)
			link.rotation.x=-.48
			Style.box(turret,Vector3(-r*.59,1.24,-r*.34+i*r*.16),Vector3(.044,.19,r*.11),STEEL)
		smoke_launchers(turret,r,1.46,r*.27)
	elif light:
		Style.cast_turret(turret,Vector3(0,deck+.11,-r*.17),[Vector4(0,r*.42,r*.48,0),Vector4(.07,r*.46,r*.52,0),Vector4(.24,r*.40,r*.44,.015),Vector4(.34,r*.29,r*.34,.02)],HULL)
		top=deck+.46
		Style.box(turret,Vector3(0,1.16,-r*.63),Vector3(.38,.22,.17),LIGHT)
	else:
		Style.cast_turret(turret,Vector3(0,deck+.10,-r*.12),[Vector4(0,r*.53,r*.61,0),Vector4(.08,r*.57,r*.65,.015),Vector4(.30,r*.55,r*.60,.05),Vector4(.47,r*.40,r*.46,.09)],HULL)
		top=deck+.58
		plate(turret,Vector3(0,1.04,r*.45),Vector3(r*.80,0,r*.38),Vector3(r*.68,.30,r*.38),0,STEEL)
		Style.box(turret,Vector3(0,1.31,-r*.70),Vector3(.57,.28,.18),LIGHT)
	hatch(turret,Vector3(r*.19,top,r*.08),r*(.19 if light else .22))
	if not light: hatch(turret,Vector3(-r*.24,top-.01,-r*.17),r*.16)
	for side in [-1,1]:Style.box(turret,Vector3(side*r*.20,top+.03,-r*.37),Vector3(.16,.055,.09),GLASS)
	antenna(turret,Vector3(-r*.32,top,r*.25),.60)
	lamps(body,r,.67,-r*1.29)

static func smoke_launchers(turret: Node3D, r: float, height: float, z: float) -> void:
	for side in [-1,1]:
		for i in range(3):
			var a = Vector3(side*r*.49,height+i*.015,z+i*.105)
			beam(turret,a,a+Vector3(side*.10,.10,-.11),.033,DARK)

static func gun(parent: Node3D, at: Vector3, length: float, radius: float, cannon: bool = false, brake: bool = false) -> Transform3D:
	var end = at+Vector3(0,0,-length)
	beam(parent,at,at+Vector3(0,0,-length*.27),radius*1.70,STEEL)
	beam(parent,at+Vector3(0,0,-length*.18),end,radius,HULL if cannon else Style.INK)
	if brake:
		Style.box(parent,end+Vector3(0,0,.025),Vector3(radius*3.6,radius*2.9,.15),STEEL)
		for side in [-1,1]:Style.box(parent,end+Vector3(side*radius*1.83,0,.025),Vector3(.008,radius*1.5,.087),Style.INK,false)
		end.z-=.055
	beam(parent,end+Vector3(0,0,.015),end+Vector3(0,0,-.009),radius*.70,Style.INK)
	return Transform3D(Basis.IDENTITY,end+Vector3(0,0,-.012))

static func machine_gun(parent: Node3D, at: Vector3, length: float) -> Transform3D:
	Style.box(parent,at+Vector3(0,0,.10),Vector3(.12,.14,.32),DARK)
	Style.box(parent,at+Vector3(-.16,-.025,.09),Vector3(.16,.18,.22),STEEL)
	for i in range(4):Style.box(parent,at+Vector3(.045,-.013,-.05-i*.052),Vector3(.013,.034,.025),LIGHT,false)
	return gun(parent,at+Vector3(0,0,-.035),length,.022)

static func weapon_channel(parent: Node3D,mode: String,at: Vector3,w: Dictionary,length: float,radius: float,cannon: bool=false,brake: bool=false,external: bool=false,machine: bool=false) -> Dictionary:
	var c=Rig.channel(parent,mode,at,w,external)
	var tip=machine_gun(c.slide,Vector3.ZERO,length) if machine else gun(c.slide,Vector3.ZERO,length,radius,cannon,brake)
	# An external receiver has a visible port; enclosed turret weapons retain cases inside.
	var port=Vector3(.067,.005,.09) if machine else Vector3(.09,0,.045)
	if external:
		Style.box(c.slide,port,Vector3(.006,.042,.078),Style.INK,false)
	else:
		Style.box(c.slide,Vector3(0,0,.015),Vector3(radius*4.3,radius*3.6,.095),DARK)
	Rig.finish(c,tip,port)
	return c

static func weapons(parent: Node3D,kind: String,r: float,height: float,profiles: Dictionary) -> Dictionary:
	var channels: Dictionary={}
	if kind=="truck":return channels
	var start=Vector3(0,height,-r*.53)
	match kind:
		"armedJeep":
			channels.mg=weapon_channel(parent,"mg",Vector3(0,height,-.14),profiles.mg,.50,.022,false,false,true,true)
		"apc":
			channels.mg=weapon_channel(parent,"mg",Vector3(-.11,height,-r*.23),profiles.mg,.53,.022,false,false,true,true)
			channels.grenade=weapon_channel(parent,"grenade",Vector3(.22,height-.02,-r*.27),profiles.grenade,.34,.047,false,false,true)
			Style.box(channels.grenade.slide,Vector3(.03,-.05,.20),Vector3(.22,.17,.31),DARK)
		"scoutCar", "ifv":
			channels.autocannon=weapon_channel(parent,"autocannon",start,profiles.autocannon,.91 if kind=="ifv" else .76,.030,false,true)
			if kind=="ifv":channels.grenade=weapon_channel(parent,"grenade",start+Vector3(.22,-.04,.11),profiles.grenade,.39,.047)
			else:channels.mg=weapon_channel(parent,"mg",start+Vector3(.18,-.06,.03),profiles.mg,.38,.018)
		_:
			var length: float=.99 if kind=="lightTank" else 1.34 if kind=="tank" else 1.55
			var radius: float=.042 if kind=="lightTank" else .057 if kind=="tank" else .071
			start.z=-r*(.65 if kind=="lightTank" else .75)
			channels.cannon=weapon_channel(parent,"cannon",start,profiles.cannon,length,radius,true,kind=="heavyTank")
			channels.mg=weapon_channel(parent,"mg",start+Vector3(.29,-.07,.065),profiles.mg,.38,.018)
			if kind=="heavyTank":channels.canister=channels.cannon
			if kind=="tank":
				var c=Rig.channel(parent,"mortar",Vector3(-r*.32,1.35,r*.26),profiles.mortar)
				var tip=gun(c.slide,Vector3.ZERO,.424,.048)
				Rig.finish(c,tip,Vector3.ZERO)
				channels.mortar=c
	return channels
static func wear_layers(body: Node3D, r: float, kind: String, root: Node3D) -> void:
	var upper: float = 1.03 if kind=="apc" else .67
	for level in range(3):
		var group = node(body,"Wear_"+str(level))
		for side in [-1,1]:
			for i in range(3+level*2):
				var z: float = -r*.78+fmod(i*.47+level*.23,r*1.60)
				var x: float = side*r*(.655 if kind=="apc" else .71)
				Art.line(group,Vector3(x,upper-.13+i%2*.07,z),Vector3(x,upper-.10+i%2*.07,z+.10),LIGHT if level==0 else Style.INK)
			if level>0:
				var dent=Art.sphere(group,Vector3(side*r*.68,upper-.06,r*.44),.14+level*.045,Style.INK,Vector3(.08,.62,1.0))
				dent.rotation.z=side*.12
		root.wear.append(group)
		if level==2:
			# Prebuilt torn engine covers stay inside the original hull footprint.
			var deck: float=Dimensions.for_vehicle(root.vehicle).deck/Dimensions.for_vehicle(root.vehicle).model_scale.y
			var engine_z=-r*.80 if kind=="armedJeep" else r*.80
			Style.box(group,Vector3(0,deck+.018,engine_z),Vector3(r*.72,.022,r*.51),Style.INK,false)
			for side in [-1,1]:
				var flap=Style.box(group,Vector3(side*r*.23,deck+.095,engine_z),Vector3(r*.28,.035,r*.43),STEEL,false)
				flap.rotation.z=side*.44;flap.rotation.y=side*.12
