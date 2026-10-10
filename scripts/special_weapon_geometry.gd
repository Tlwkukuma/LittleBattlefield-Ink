extends RefCounted
const Art=preload("res://scripts/ink_art.gd")
static func tube(root: Node3D,at: Vector3,radius: float,length: float,color: Color):
	var mesh=Art.cylinder(root,at,radius,length,color);mesh.rotation.x=PI*.5;return mesh
static func tip(root: Node3D,at: Vector3,radius: float,length: float,color: Color):
	var node=MeshInstance3D.new();var mesh=CylinderMesh.new();mesh.top_radius=0;mesh.bottom_radius=radius;mesh.height=length;mesh.radial_segments=12
	node.mesh=mesh;node.material_override=Art.ink_material(color);root.add_child(node);node.position=at;node.rotation.x=-PI*.5
static func build(root: Node3D,w: Dictionary) -> bool:
	if str(w.id)=="minigun":
		preload("res://scripts/minigun_visual.gd").build(root,w);return true
	var dark=Color("424451");var steel=Color("b4bac0");var olive=Color("889171")
	match str(w.kind):
		"melee":
			if w.id=="fire-axe":
				Art.box(root,Vector3(0,0,-.20),Vector3(.047,.048,.80),Color("92715c"))
				Art.box(root,Vector3(.09,0,-.54),Vector3(.28,.055,.19),Color("969da6"))
				Art.box(root,Vector3(.23,0,-.54),Vector3(.035,.018,.21),steel)
				Art.box(root,Vector3(-.065,0,-.54),Vector3(.09,.070,.12),dark)
			else:
				var knife=w.id=="army-knife";var length=.28 if knife else .76
				Art.box(root,Vector3(0,0,.045),Vector3(.055,.055,.17 if knife else .26),dark)
				Art.box(root,Vector3(0,0,-.09),Vector3(.135,.035,.035),Color("a89e88"))
				Art.box(root,Vector3(0,0,-.11-length*.45),Vector3(.014,.065,length*.90),steel)
				Art.box(root,Vector3(.009,-.025,-.11-length*.45),Vector3(.005,.013,length*.90),Color("e0e1dc"))
				var blade_tip=Art.loft(root,Vector3(0,0,-.11-length*.90),[Vector4(0,.008,.032,0),Vector4(length*.10,.001,.001,0)],steel,8);blade_tip.rotation.x=-PI*.5
				for z in [.0,.045,.09]:Art.box(root,Vector3(0,0,z),Vector3(.058,.058,.012),Color("6a6470"))
			root.set_meta("primary_muzzle",Vector3(0,0,-.30 if w.id=="army-knife" else -.60 if w.id=="fire-axe" else -.88));return true
		"rocket":
			var rpg=w.id=="rpg"
			tube(root,Vector3(0,0,-.06),.065 if rpg else .092,.96,olive if rpg else Color("b0a183"))
			for z in [-.45,.08,.37]:tube(root,Vector3(0,0,z),.075 if rpg else .105,.035,dark)
			tube(root,Vector3(0,0,.42),.09 if rpg else .112,.08,steel.darkened(.30))
			tube(root,Vector3(0,0,.465),.066 if rpg else .088,.008,dark)
			Art.box(root,Vector3(.025,-.13,.035),Vector3(.060,.21,.085),dark)
			Art.box(root,Vector3(-.035,-.09,-.20),Vector3(.07,.09,.19),Color("806c53") if rpg else dark)
			Art.box(root,Vector3(0,-.075,.22),Vector3(.15,.055,.23),dark)
			tube(root,Vector3(-.10,.11,-.13),.029,.24,dark)
			Art.box(root,Vector3(-.065,.07,-.06),Vector3(.08,.12,.05),dark)
			if rpg:
				tube(root,Vector3(0,0,-.53),.092,.17,Color("9a9c73"));tip(root,Vector3(0,0,-.68),.092,.16,Color("c2baa1"))
			else:
				tube(root,Vector3(0,0,-.545),.107,.055,steel.darkened(.25));tube(root,Vector3(0,0,-.578),.078,.006,dark)
			root.set_meta("primary_muzzle",Vector3(0,0,-.765 if rpg else -.59));root.set_meta("backblast_at",Vector3(0,0,.47));return true
		"grenadeProjectile":
			tube(root,Vector3(0,0,-.28),.072,.48,Color("69796e"));tube(root,Vector3(0,0,-.525),.080,.025,dark);tube(root,Vector3(0,0,-.543),.057,.008,Art.INK)
			Art.box(root,Vector3(0,-.005,.02),Vector3(.11,.12,.20),dark)
			Art.box(root,Vector3(0,-.10,.04),Vector3(.065,.17,.10),Color("917156"))
			Art.box(root,Vector3(0,-.03,.22),Vector3(.075,.14,.27),Color("917156"))
			Art.box(root,Vector3(0,-.055,-.21),Vector3(.10,.07,.20),Color("917156"))
			Art.box(root,Vector3(0,.09,-.09),Vector3(.065,.09,.06),dark)
			root.set_meta("primary_muzzle",Vector3(0,0,-.55));return true
		"mortar":
			Art.box(root,Vector3(0,-.21,.02),Vector3(.44,.04,.38),dark)
			var barrel=Art.cylinder(root,Vector3(0,.27,-.23),.070,1.12,olive);barrel.rotation.x=-.65
			var mouth=Art.cylinder(root,Vector3(0,.72,-.572),.083,.04,steel);mouth.rotation.x=-.65
			var bore=Art.cylinder(root,Vector3(0,.744,-.591),.054,.006,dark);bore.rotation.x=-.65
			for sign_value in [-1,1]:Art.line(root,Vector3(sign_value*.06,.35,-.28),Vector3(sign_value*.26,-.20,-.36),dark)
			root.set_meta("primary_muzzle",Vector3(0,.75,-.596));return true
	return false
static func reload_round(root: Node3D,w: Dictionary):
	if w.kind not in ["rocket","grenadeProjectile","mortar"]:return
	var round=Node3D.new();round.name="ReloadRound";root.add_child(round)
	var radius=.047 if w.kind=="grenadeProjectile" else .065
	tube(round,Vector3.ZERO,radius,.15 if w.kind=="grenadeProjectile" else .25,Color("92977a"))
	tip(round,Vector3(0,0,-.10 if w.kind=="grenadeProjectile" else -.19),radius,.06 if w.kind=="grenadeProjectile" else .13,Color("c5b78b"))
	round.hide()
