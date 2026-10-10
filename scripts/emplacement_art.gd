extends RefCounted
const Art=preload("res://scripts/ink_art.gd")
const Kit=preload("res://scripts/vehicle_art.gd")
const Profile=preload("res://scripts/emplacement_profile.gd")
const Style=preload("res://scripts/vehicle_style.gd")
const HULL=Style.HULL
const LIGHT=Style.LIGHT
const STEEL=Style.STEEL
const DARK=Style.DARK

static func marker(parent: Node3D, title: String, at: Vector3) -> Marker3D:
	var socket=Marker3D.new();socket.name=title;socket.position=at;parent.add_child(socket);return socket

static func build(parent: Node3D,v: Dictionary) -> Dictionary:
	if v.type=="portableMortar":return preload("res://scripts/portable_mortar_art.gd").build(parent,v)
	var team=Style.Livery.team_id(v.get("team",-1))
	var surface=Style.material(false,team)
	var edges=Style.material(true,team)
	var root=Kit.node(parent,"Emplacement_"+str(v.type))
	var body=Kit.node(root,"GroundMount")
	var turret=Kit.node(root,"TraverseCradle")
	var barrel=Kit.node(turret,"RecoilingAssembly")
	var view={"root":root,"body":body,"turret":turret,"barrel":barrel,"wheels":[],"emplacement":true}
	var grips: Array=[]
	var socket: Marker3D
	var mechanism: Node3D
	var loading_round: Node3D
	if v.type=="hmg":
		hmg(body,turret,barrel)
		Style.recognition(turret,Vector3(-.30,1.162,-.025),Vector2(.21,.25),team)
		grips=[marker(barrel,"LeftGrip",Vector3(-.14,1.12,.405)),marker(barrel,"RightGrip",Vector3(.14,1.12,.405))]
		socket=marker(barrel,"MuzzleSocket",Vector3(0,1.16,-1.04))
		mechanism=Kit.node(barrel,"FeedCover",Vector3(0,1.225,.13))
		Style.box(mechanism,Vector3(0,0,-.19),Vector3(.20,.025,.40),LIGHT)
		view.reload_left=marker(turret,"FeedContact",Vector3(-.22,1.12,.18))
		view.reload_right=marker(turret,"ChargeContact",Vector3(.19,1.16,.20))
		view.ejection_socket=marker(barrel,"EjectionSocket",Vector3(.13,1.12,-.02))
	else:
		field_gun(body,turret,barrel,view.wheels)
		# Match the sloping shield, clear of the barrel and the operator's sight slot.
		Style.recognition(turret,Vector3(.36,.93,-.286),Vector2(.24,.19),team,Vector3(0,.0913,-.9958).normalized())
		grips=[marker(turret,"LeftGrip",Vector3(-.90,1.04,.43)),marker(turret,"RightGrip",Vector3(-.59,1.10,.34))]
		socket=marker(barrel,"MuzzleSocket",Vector3(0,1.16,-1.91))
		mechanism=Kit.node(barrel,"BreechBlock",Vector3(0,1.16,.52))
		Style.box(mechanism,Vector3.ZERO,Vector3(.22,.22,.10),STEEL)
		loading_round=Kit.node(turret,"LoadingRound",Vector3(-.35,1.08,.64))
		Kit.beam(loading_round,Vector3(0,0,-.14),Vector3(0,0,.14),.051,Color("c2aa81"))
		Kit.beam(loading_round,Vector3(0,0,-.14),Vector3(0,0,-.25),.047,DARK)
		Style.finish_group(loading_round,[],surface,edges)
		loading_round.hide()
		view.loading_round=loading_round
		view.reload_left=marker(turret,"BreechContact",Vector3(-.29,1.11,.58))
		view.reload_right=marker(turret,"ShellContact",Vector3(-.42,1.09,.69))
		view.ejection_socket=marker(barrel,"EjectionSocket",Vector3(0,1.16,.57))
	view.operator_anchor=marker(turret,"Operator",Profile.operator_offset(v.type))
	view.grips=grips;view.mechanism=mechanism;view.muzzle_socket=socket
	view.muzzle=Art.sphere(socket,Vector3(0,0,-.12),.16 if v.type=="fieldGun" else .09,Color("ffe0a5"),Vector3(.7,.7,2.1))
	view.muzzle.hide()
	Style.finish_group(body,view.wheels,surface,edges)
	var keep: Array=[barrel,view.operator_anchor,view.reload_left,view.reload_right]
	if loading_round!=null:keep.append(loading_round)
	keep.append_array(grips)
	Style.finish_group(turret,keep,surface,edges)
	Style.finish_group(barrel,[socket,mechanism,view.ejection_socket]+grips,surface,edges)
	Style.finish_group(mechanism,[],surface,edges)
	for wheel in view.wheels:Style.finish_group(wheel,[],surface,edges)
	if v.type=="hmg":
		# Rotate the gun about its trunnion, not about the tripod's ground origin.
		var elevation=Kit.node(turret,"Elevation",Vector3(0,1.16,0))
		barrel.reparent(elevation,false);barrel.position.y=-1.16
		view.reload_left.reparent(barrel,true);view.reload_right.reparent(barrel,true)
		view.elevation=elevation
	return view

static func hmg(body: Node3D,turret: Node3D,barrel: Node3D) -> void:
	# Three splayed legs, broad spades, column lock and traverse bearing.
	for foot in [Vector3(-.46,.055,.39),Vector3(.46,.055,.39),Vector3(0,.055,-.53)]:
		Kit.beam(body,Vector3(0,.83,0),foot,.037,STEEL)
		Kit.beam(body,Vector3(0,.41,0),foot.lerp(Vector3(0,.83,0),.35),.018,DARK)
		Style.box(body,foot,Vector3(.15,.045,.17),DARK)
	Kit.beam(body,Vector3(0,.38,0),Vector3(0,1.05,0),.055,HULL)
	Art.cylinder(body,Vector3(0,.89,0),.095,.075,DARK)
	Kit.beam(body,Vector3(.04,.88,0),Vector3(.16,.88,.07),.02)
	Art.cylinder(turret,Vector3(0,1.025,0),.13,.075,STEEL)
	for side in [-1,1]:Style.box(turret,Vector3(side*.13,1.09,-.02),Vector3(.036,.19,.18),LIGHT)
	Style.box(barrel,Vector3(0,1.14,-.04),Vector3(.22,.17,.56),HULL)
	Style.box(barrel,Vector3(0,1.10,.255),Vector3(.18,.13,.075),DARK)
	Kit.beam(barrel,Vector3(-.17,1.11,.29),Vector3(.17,1.11,.29),.022)
	for side in [-1,1]:
		Kit.beam(barrel,Vector3(side*.14,1.11,.29),Vector3(side*.14,1.12,.405),.019)
		Kit.beam(barrel,Vector3(side*.14,1.055,.405),Vector3(side*.14,1.185,.405),.024,DARK)
	Kit.beam(barrel,Vector3(0,1.16,-.30),Vector3(0,1.16,-.76),.055,STEEL)
	Kit.beam(barrel,Vector3(0,1.16,-.72),Vector3(0,1.16,-1.035),.025,Style.INK)
	for i in range(7):
		for side in [-1,1]:Style.box(barrel,Vector3(side*.054,1.16,-.34-i*.055),Vector3(.007,.04,.024),Style.INK,false)
	Style.box(barrel,Vector3(0,1.225,-.30),Vector3(.025,.065,.04),DARK)
	Style.box(barrel,Vector3(0,1.21,-.86),Vector3(.024,.10,.035),DARK)
	Style.box(turret,Vector3(-.30,1.0,-.025),Vector3(.25,.25,.36),STEEL)
	Style.box(turret,Vector3(-.30,1.14,-.025),Vector3(.27,.035,.38),LIGHT)
	for i in range(7):
		var t=float(i)/6
		Kit.beam(barrel,Vector3(-.12-t*.23,1.145-sin(t*PI)*.07,-.02),Vector3(-.12-t*.23,1.145-sin(t*PI)*.07,-.105),.014,Color("b8a68c"))
	Style.box(barrel,Vector3(.135,1.14,.09),Vector3(.055,.035,.065),DARK)

static func field_gun(body: Node3D,turret: Node3D,barrel: Node3D,wheels: Array) -> void:
	Kit.beam(body,Vector3(-.75,.43,.02),Vector3(.75,.43,.02),.065,DARK)
	for side in [-1,1]:
		var wheel=Kit.node(body,"CarriageWheel",Vector3(side*.68,.43,.02));wheel.rotation.z=PI*.5
		Art.cylinder(wheel,Vector3.ZERO,.42,.17,Style.RUBBER)
		Art.cylinder(wheel,Vector3(0,-side*.095,0),.34,.025,STEEL)
		Art.cylinder(wheel,Vector3(0,-side*.115,0),.09,.055,LIGHT)
		for i in range(8):
			var a=i*TAU/8
			Kit.beam(wheel,Vector3(cos(a)*.10,-side*.135,sin(a)*.10),Vector3(cos(a)*.29,-side*.135,sin(a)*.29),.023,DARK)
		wheels.append(wheel)
		Kit.beam(body,Vector3(side*.22,.34,.16),Vector3(side*.51,.12,1.45),.074,HULL)
		Style.box(body,Vector3(side*.51,.10,1.50),Vector3(.30,.17,.24),STEEL)
		Style.box(body,Vector3(side*.51,.17,1.58),Vector3(.23,.045,.15),DARK)
		Style.box(body,Vector3(side*.23,.35,.17),Vector3(.20,.22,.23),DARK)
	Art.cylinder(turret,Vector3(0,.54,0),.26,.20,STEEL)
	Kit.plate(turret,Vector3(0,.61,0),Vector3(.54,0,.54),Vector3(.39,.30,.52),0,HULL)
	# Split shield with a real central barrel opening and sight slot above the left panel.
	for side in [-1,1]:
		Kit.plate(turret,Vector3(side*.36,.64,-.27),Vector3(.48,0,.075),Vector3(.40,.60,.075),.055,LIGHT,.16)
		Style.box(turret,Vector3(side*.36,.59,-.24),Vector3(.46,.11,.065),HULL)
		for y in [.73,1.12]:Art.sphere(turret,Vector3(side*.50,y,-.318),.022,DARK)
	Style.box(turret,Vector3(0,.86,-.27),Vector3(.26,.23,.075),HULL)
	Style.box(turret,Vector3(-.36,1.26,-.25),Vector3(.20,.045,.085),DARK)
	for side in [-1,1]:Style.box(turret,Vector3(side*.18,1.01,.03),Vector3(.075,.32,.47),HULL)
	Kit.beam(turret,Vector3(-.24,1.08,.06),Vector3(.24,1.08,.06),.11,STEEL)
	# Hydraulic cylinder and sliding breech are independent of the fixed controls.
	Kit.beam(turret,Vector3(0,1.0,.28),Vector3(0,1.0,-.77),.082,DARK)
	Kit.beam(barrel,Vector3(0,1.0,.30),Vector3(0,1.0,-.97),.043,LIGHT)
	Style.box(barrel,Vector3(0,1.16,.285),Vector3(.30,.26,.47),HULL)
	Kit.beam(barrel,Vector3(0,1.16,.08),Vector3(0,1.16,-.65),.106,STEEL)
	Kit.beam(barrel,Vector3(0,1.16,-.59),Vector3(0,1.16,-1.76),.060,HULL)
	Style.box(barrel,Vector3(0,1.16,-1.80),Vector3(.19,.16,.21),STEEL)
	for side in [-1,1]:Style.box(barrel,Vector3(side*.096,1.16,-1.80),Vector3(.008,.078,.11),Style.INK,false)
	Kit.beam(barrel,Vector3(0,1.16,-1.896),Vector3(0,1.16,-1.91),.042,Style.INK)
	Kit.beam(turret,Vector3(-.17,.86,.30),Vector3(-.66,.94,.30),.038,STEEL)
	var wheel=Kit.node(turret,"ElevationHandwheel",Vector3(-.69,1.04,.30));wheel.rotation.z=PI*.5
	Art.ring(wheel,Vector3.ZERO,.135,DARK,.025,24)
	for i in range(4):Kit.beam(wheel,Vector3.ZERO,Vector3(cos(i*PI*.5)*.135,0,sin(i*PI*.5)*.135),.015)
	Kit.beam(turret,Vector3(-.69,1.04,.43),Vector3(-.90,1.04,.43),.021,DARK)
	Kit.beam(turret,Vector3(-.18,1.02,.34),Vector3(-.59,1.02,.34),.022)
	Kit.beam(turret,Vector3(-.59,1.02,.34),Vector3(-.59,1.16,.34),.024,DARK)
	Style.box(turret,Vector3(-.40,1.16,.05),Vector3(.11,.06,.20),DARK)
	Kit.beam(turret,Vector3(-.40,.94,.05),Vector3(-.40,1.16,.05),.02)
