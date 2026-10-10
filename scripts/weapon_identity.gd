extends RefCounted
## Preserve the original side silhouettes; add readable volume and distinct proportions.
const Art=preload("res://scripts/ink_art.gd")
const Profile=preload("res://scripts/weapon_profile.gd")
const Magazine=preload("res://scripts/weapon_magazine.gd")
const LENGTHS={"m416":.88,"m16a4":1.02,"scar-l":.91,"g36c":.78,"aug":.79,"famas":.77,"qbz":.82,
	"akm":1.02,"ak-47":1.01,"beryl-m762":.99,"ace32":.96,"groza":.77,"mk47-mutant":1.05,
	"vector":.55,"micro-uzi":.43,"mp5k":.55,"ump":.68,"ump-45":.69,"p90":.63,"mp9":.49,"tommy-gun":.85,
	"mini14":1.03,"sks":1.13,"slr":1.12,"mk14":1.12,"vss":.99,"dragunov":1.20,
	"kar98k":1.16,"m24":1.20,"awm":1.32,"awp":1.30,"ssg-08":1.10,"lynx-amr":1.48,
	"m249":1.13,"mg3":1.26,"rpd":1.12,"negev":1.11,"minigun":1.32,
	"s1897":1.11,"s686":1.13,"sawed-off":.59,"dbs":.80,"s12k":.95,"nova":1.09,
	"p92":.31,"glock-18":.29,"p18c":.30,"deagle":.40,"r1895":.37,"r8-revolver":.40,
	"rpg":1.35,"anti-tank-launcher":1.13,"k2":.98,"mk12":1.10,"js9":.66,"win94":1.09,
	"o12":.97,"skorpion":.44,"galil-ar":.99,"m4a4":.86,"m4a1-s":1.02,"sg-553":.89,"g3sg1":1.18,
	"scar-20":1.16,"mac-10":.40,"mp7":.53,"mp5-sd":.80,"pp-bizon":.69,"xm1014":1.05,"mag-7":.64,
	"p2000":.29,"usp-s":.42,"p250":.30,"five-seven":.33,"tec-9":.43,"cz75-auto":.31,"dual-berettas":.34}

static func pigment(w: Dictionary,key: String,fallback: Color) -> Color:
	var model: Dictionary=w.get("mechanics",{}).get("model",{});var id=str(w.id)
	var wood=Color("986442") if id not in ["kar98k","s686","sawed-off"] else Color("86523c")
	var furniture=Color("424d52");var metal=Color("65727a")
	if id in ["scar-l","scar-20","o12"]:furniture=Color("b49b70");metal=Color("ae9875")
	elif id in ["awm","awp","aug","rpg","m24"]:furniture=Color("788460")
	elif id=="vector":furniture=Color("ad9973");metal=Color("59636a")
	elif id in ["akm","ak-47","s1897","kar98k","sks","s686","sawed-off","dragunov","tommy-gun"]:furniture=wood;metal=Color("596269")
	elif id in ["dbs","s12k","famas","g36c","p90"]:furniture=Color("444e55");metal=Color("56636d")
	if id in ["deagle","r8-revolver"]:metal=Color("b5bec1")
	match key:
		"wood":return wood if model.get("stock","") in ["wood","sawn","skeletonwood"] or model.get("guard","")=="wood" else furniture
		"metal":return metal
		"cloth","accent":return furniture
		"dark":return Color("363e45")
		"paper":return metal.lightened(.26)
		"ink":return Color("29333c")
		"glass":return Color("567e83")
	return fallback

static func width(w: Dictionary) -> float:
	var family=Profile.get_profile(w).family
	if family=="pistol":return .086 if w.id!="dual-berettas" else .24
	if w.id=="dbs":return .205
	if w.id in ["s686","sawed-off"]:return .145
	if family=="smg":return .125 if w.id not in ["p90","vector"] else .16
	if family=="heavy":return .23
	if family=="sniper":return .17 if w.id!="lynx-amr" else .22
	return .155

static func surface_details(root: Node3D,w: Dictionary,muzzle: Vector3):
	var p=Profile.get_profile(w);var m: Dictionary=w.get("mechanics",{});var model: Dictionary=m.get("model",{})
	var metal=pigment(w,"metal",Color.GRAY);var dark=pigment(w,"dark",Color.BLACK);var trim=metal.lightened(.23)
	var front=muzzle.z;var y=muzzle.y;var receiver=.08 if m.get("bullpup",false) else -.06
	# Port, bolt handle, receiver pins and selector: three-quarter readable details.
	Art.box(root,Vector3(.069,y,receiver),Vector3(.009,.028,.095),dark,false)
	Art.box(root,Vector3(.075,y-.005,receiver+.015),Vector3(.012,.012,.051),trim,false)
	if model.get("bolt",false):
		Art.box(root,Vector3(.094,y-.02,.025),Vector3(.065,.016,.025),dark,false)
		Art.sphere(root,Vector3(.126,y-.052,.025),.022,dark)
	else:Art.box(root,Vector3(.082,y+.003,receiver+.043),Vector3(.032,.013,.024),trim,false)
	for side in [-1,1]:
		for z in [receiver-.067,receiver+.067]:
			var pin=Art.cylinder(root,Vector3(side*.072,y-.035,z),.008,.006,trim);pin.rotation.z=PI*.5
		Art.box(root,Vector3(side*.073,y-.055,receiver+.074),Vector3(.007,.009,.023),dark,false)
	var barrel_radius=.030 if p.family=="shotgun" else .018
	# A dark inset surrounded by a lip reads as an open barrel rather than a solid rod.
	if p.family!="shotgun":
		axial(root,Vector3(0,y,front+.012),barrel_radius*1.36,.024,metal)
		axial(root,Vector3(0,y,front-.001),barrel_radius*.77,.003,dark)
	var sight_z=front+.055
	if p.family not in ["sniper","pistol"]:
		Art.box(root,Vector3(0,y+.05,sight_z),Vector3(.022,.08,.025),dark,false)
		Art.box(root,Vector3(0,y+.095,receiver+.09),Vector3(.052,.022,.024),dark,false)
	if int(model.get("suppressor",0))>0 or p.suppressed:
		var length=.23 if p.family!="pistol" else .17
		axial(root,Vector3(0,y,front+length*.5),.042,length,Color("555e63"))
		for z in [front+.015,front+length-.015]:axial(root,Vector3(0,y,z),.045,.014,dark)
		axial(root,Vector3(0,y,front-.002),.027,.003,dark)
	if model.get("brake",false):
		Art.box(root,Vector3(0,y,front+.04),Vector3(.09,.066,.085),metal,false)
		for side in [-1,1]:
			for z in [front+.02,front+.058]:Art.box(root,Vector3(side*.046,y,z),Vector3(.003,.027,.017),dark,false)
	var fore=clampf(-(float(model.get("fore",65))-36)*.013,front+.10,-.20)
	var guard=str(model.get("guard",""))
	if guard in ["rail","longrail","vent","perforated","scar","rib"]:
		for side in [-1,1]:
			for i in range(5):
				var z=lerpf(-.20,fore,float(i)/4)
				Art.box(root,Vector3(side*.058,y+.01,z),Vector3(.004,.024,.028 if guard!="rib" else .008),dark,false)
		for i in range(7):Art.box(root,Vector3(0,y+.065,lerpf(-.12,fore,float(i)/6)),Vector3(.085,.014,.012),dark,false)
	# A few material seams survive the gameplay zoom; avoid dense decorative noise.
	if model.get("stock","") in ["wood","sawn","skeletonwood"]:
		for side in [-1,1]:
			Art.box(root,Vector3(side*.047,y-.055,.22),Vector3(.003,.008,.12),pigment(w,"wood",metal).lightened(.18),false)
	if p.family=="pistol":
		for i in range(4):
			for side in [-1,1]:Art.box(root,Vector3(side*.05,y+.025,.04-i*.023),Vector3(.004,.038,.008),dark,false)
	var mag=Magazine.profile(w)
	if mag.detachable:
		var body=Magazine.build(root,w);body.position=mag.at
	root.set_meta("magazine_at",mag.at);root.set_meta("ejection_at",Vector3(.080,y+.01,receiver))

static func shotgun_details(root: Node3D,w: Dictionary,muzzle: Vector3):
	var model: Dictionary=w.get("mechanics",{}).get("model",{});var dark=pigment(w,"dark",Color.BLACK);var metal=pigment(w,"metal",Color.GRAY)
	var wood=pigment(w,"wood",Color.GRAY);var front=muzzle.z;var y=.025;var breech=-.12
	var barrels=[Vector3(0,y,0)]
	if w.id=="s686":barrels.append(Vector3(0,y-.058,0))
	elif w.id in ["sawed-off","dbs"]:barrels=[Vector3(-.040,y,0),Vector3(.040,y,0)]
	for barrel in barrels:
		var length=breech-front
		axial(root,barrel+Vector3(0,0,(front+breech)*.5),.029,length,dark)
		axial(root,barrel+Vector3(0,0,front+.012),.033,.025,metal)
		axial(root,barrel+Vector3(0,0,front-.002),.023,.004,Color("202a31"))
	root.set_meta("primary_muzzle",Vector3(barrels[0].x,barrels[0].y,front-.006))
	if barrels.size()>1:root.set_meta("secondary_muzzle",Vector3(barrels[1].x,barrels[1].y,front-.006))
	if w.id in ["s1897","nova","xm1014"]:
		axial(root,Vector3(0,y-.058,(front+.06+breech)*.5),.026,breech-front-.06,metal)
		var pump_z=-.32;var pump_color=wood if w.id=="s1897" else Color("464e50")
		axial(root,Vector3(0,y-.06,pump_z),.054,.22,pump_color)
		for i in range(7):axial(root,Vector3(0,y-.06,pump_z-.09+i*.03),.055,.007,pump_color.darkened(.26))
	elif w.id=="dbs":
		for side in [-1,1]:axial(root,Vector3(side*.04,y-.069,-.32),.028,.40,metal)
		Art.box(root,Vector3(0,y-.10,-.30),Vector3(.14,.065,.27),dark,false)
		for i in range(6):Art.box(root,Vector3(0,y-.137,-.41+i*.04),Vector3(.145,.013,.008),metal,false)
	elif w.id in ["s686","sawed-off"]:
		Art.box(root,Vector3(0,y-.037,-.03),Vector3(.12,.09,.18),Color("89908b"),false)
		Art.box(root,Vector3(0,y+.031,.026),Vector3(.023,.015,.066),dark,false)
		Art.box(root,Vector3(0,y-.06,-.29),Vector3(.09,.06,.25),wood,false)
	else:
		Art.box(root,Vector3(0,y-.035,-.29),Vector3(.115,.105,.28),metal,false)
		for side in [-1,1]:
			for i in range(4):Art.box(root,Vector3(side*.059,y-.02,-.20-i*.057),Vector3(.004,.026,.025),dark,false)
	if model.get("stock","") in ["wood","sawn","sport"]:
		Art.box(root,Vector3(0,y-.076,.21),Vector3(.093,.12,.24),wood,false)
		Art.box(root,Vector3(0,y-.081,.33),Vector3(.10,.13,.026),dark,false)

static func axial(parent: Node3D,at: Vector3,radius: float,length: float,color: Color):
	var node=Art.cylinder(parent,at,radius,length,color);node.rotation.x=PI*.5
	return node

static func details(root: Node3D,w: Dictionary,muzzle: Vector3):
	var p=Profile.get_profile(w);var model: Dictionary=w.get("mechanics",{}).get("model",{})
	var dark=pigment(w,"dark",Color.BLACK);var steel=pigment(w,"metal",Color.GRAY);var wood=pigment(w,"wood",Color.WHITE)
	if w.kind=="rocket":
		axial(root,Vector3(0,0,-.10),.085,.84,Color("858d72") if w.id=="rpg" else Color("b1a486"))
		if w.id=="rpg":
			axial(root,Vector3(0,0,-.45),.12,.23,Color("a4a88a"))
		else:Art.box(root,Vector3(.07,.11,-.15),Vector3(.07,.10,.21),dark)
		return
	if w.kind not in ["bullet","hitscan"]:return
	surface_details(root,w,muzzle)
	if p.family=="shotgun":
		shotgun_details(root,w,muzzle)
		return
	var y=muzzle.y;var front=muzzle.z+.006
	if p.family=="pistol":
		Art.box(root,Vector3(0,y-.018,front*.35),Vector3(.095,.075,absf(front)*.95),steel)
		axial(root,Vector3(0,y,front+.08),.017,.15,dark)
		if "revolver" in str(w.id) or w.id=="r1895":axial(root,Vector3(0,y-.03,.015),.067,.12,steel)
		return
	var bullpup=bool(w.get("mechanics",{}).get("bullpup",false))
	var receiver_z=.075 if bullpup else -.04
	Art.box(root,Vector3(0,y-.032,receiver_z),Vector3(.09,.10,.25),dark)
	var fore=-(float(model.get("fore",65))-36)*.013
	fore=maxf(front+.11,minf(-.19,fore))
	axial(root,Vector3(0,y,(fore+front)*.5),.025 if p.family in ["shotgun","heavy"] else .017,absf(fore-front),dark)
	var guard_z=(fore-.12)*.5;var guard_length=absf(fore+.12)
	Art.box(root,Vector3(0,y-.018,guard_z),Vector3(.10,.09,guard_length),wood if model.get("guard","")=="wood" else steel)
	if model.get("guard","")=="rail":
		for i in range(6):Art.box(root,Vector3(0,y+.04,lerpf(-.13,fore,float(i)/5)),Vector3(.12,.012,.012),dark)
	if model.get("stock","")=="wood":Art.box(root,Vector3(0,y-.045,.19),Vector3(.085,.115,.24),wood)
	elif model.get("stock","")=="telescopic":
		axial(root,Vector3(0,y-.015,.17),.022,.23,steel)
		Art.box(root,Vector3(0,y-.055,.27),Vector3(.08,.145,.08),dark)
	if p.family=="sniper" or model.get("optic","")=="scope":
		axial(root,Vector3(0,y+.14,-.04),.038,.28,dark)
		axial(root,Vector3(0,y+.14,-.18),.050,.065,steel)
		axial(root,Vector3(0,y+.14,-.215),.037,.008,Color("708f9a"))
		for z in [-.10,.045]:Art.box(root,Vector3(0,y+.075,z),Vector3(.065,.12,.032),dark)
		Art.cylinder(root,Vector3(0,y+.19,-.025),.027,.038,steel)
	elif model.get("optic","")=="integral":axial(root,Vector3(0,y+.13,-.015),.034,.19,dark)
	if model.get("carry",false):
		for z in [-.12,.10]:Art.box(root,Vector3(0,y+.08,z),Vector3(.06,.13,.025),dark)
		Art.box(root,Vector3(0,y+.14,-.01),Vector3(.06,.025,.24),dark)
	if w.id=="p90":Art.box(root,Vector3(0,y-.03,.06),Vector3(.14,.15,.34),pigment(w,"cloth",dark))
	if w.id=="vector":Art.box(root,Vector3(0,y-.15,-.015),Vector3(.10,.25,.11),Color("a49b86"))
	if p.family=="heavy":
		Art.box(root,Vector3(0,y+.035,-.02),Vector3(.16,.035,.22),steel)
		for i in range(5):Art.box(root,Vector3(.10,y-.04-i*.015,-.025),Vector3(.08,.012,.032),Color("bca978"))
	if model.get("bipod",false) or p.family=="heavy":
		for side in [-1,1]:Art.cloth_limb(root,Vector3(side*.055,y-.04,fore),Vector3(side*.085,y-.075,fore+.22),.012,.010,dark)
