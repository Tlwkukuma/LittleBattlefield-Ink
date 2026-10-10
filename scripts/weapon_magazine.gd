extends RefCounted
## Shared held/dropped geometry: feed shape and finish belong to the weapon.
const Art=preload("res://scripts/ink_art.gd")
const Batch=preload("res://scripts/mesh_batch.gd")

static func profile(w: Dictionary) -> Dictionary:
	var id=str(w.get("id",w.get("kind","unknown")));var m: Dictionary=w.get("mechanics",{});var model: Dictionary=m.get("model",{});var feed=str(m.get("feed","none"))
	var kind=str(model.get("mag","box"));var size=Vector3(.095,.205,.105);var color=Color("51575c")
	var at=Vector3(0,-.11,-(float(model.get("magX",49))-36)*.013)
	if bool(m.get("bullpup",false)):at=Vector3(0,-.12,.10)
	if bool(m.get("pistol",false)) or model.get("type","") in ["pistol","dual"]:kind="stick";size=Vector3(.065,.15,.075);at=Vector3(0,-.145,.015)
	elif w.get("archetype","")=="smg":size=Vector3(.08,.205,.078)
	if kind=="curve":size=Vector3(.095,.235,.09)
	if kind=="short":size.y=.12
	if id in ["s12k","mag-7"]:size=Vector3(.108,.20,.145)
	if id in ["akm","ak-47"]:color=Color("66564a")
	if id in ["beryl-m762","ace32","groza"]:color=Color("39454b")
	if feed=="topMagazine":kind="top";size=Vector3(.13,.055,.36);at=Vector3(0,.10,-.03);color=Color("9b8964")
	elif feed=="helical":kind="helical";size=Vector3(.11,.11,.38);at=Vector3(0,-.095,-.32);color=Color("655f4b")
	elif feed=="belt":kind="drum" if kind in ["drum","beltdrum"] else "beltbox";size=Vector3(.18,.19,.20);at=Vector3(0,-.16,-.13);color=Color("747f58")
	elif kind=="drum":size=Vector3(.18,.21,.20);at.y=-.15
	if id=="minigun":kind="beltbox";size=Vector3(.16,.22,.24);at=Vector3(-.245,-.072,.015);color=Color("78846b")
	return {"kind":kind,"size":size,"color":color,"at":at,"detachable":feed in ["magazine","topMagazine","helical","belt"]}

static func build(parent: Node3D,w: Dictionary) -> Node3D:
	var p=profile(w);var root=Node3D.new();root.name="MagazineBody";parent.add_child(root)
	var size: Vector3=p.size;var color: Color=p.color;var dark=color.darkened(.32);var edge=color.lightened(.19)
	if p.kind in ["drum","helical"]:
		var tube=Art.cylinder(root,Vector3.ZERO,size.y*.5,size.x if p.kind=="drum" else size.z,color)
		tube.rotation.z=PI*.5 if p.kind=="drum" else 0.0;tube.rotation.x=PI*.5 if p.kind=="helical" else 0.0
		for side in [-1,1]:
			var cap=Art.cylinder(root,Vector3(side*size.x*.49,0,0) if p.kind=="drum" else Vector3(0,0,side*size.z*.49),size.y*.38,.012,edge)
			cap.rotation.z=PI*.5 if p.kind=="drum" else 0.0;cap.rotation.x=PI*.5 if p.kind=="helical" else 0.0
	elif p.kind=="curve":
		for i in range(5):
			var t=(i+.5)/5.0
			var part=Art.box(root,Vector3(0,(.5-t)*size.y,-t*t*.065),Vector3(size.x,size.y*.23,size.z),color,false);part.rotation.x=-t*.38
	else:Art.box(root,Vector3.ZERO,size,color,false)
	if p.kind not in ["drum","helical"]:
		for side in [-1,1]:
			for i in range(3):
				var at=Vector3(side*(size.x*.5+.001),0,(-.26+i*.26)*size.z)
				if p.kind=="curve":at.z-=.025
				Art.box(root,at,Vector3(.004,size.y*.76,.006),dark,false)
		Art.box(root,Vector3(0,-size.y*.5,-.065 if p.kind=="curve" else 0),Vector3(size.x*1.07,.018,size.z*1.04),edge,false)
		if p.kind=="top":
			for i in range(7):Art.box(root,Vector3(0,size.y*.51,-size.z*.39+i*size.z*.13),Vector3(size.x*.72,.004,.016),Color("bfaa70"),false)
		else:Art.box(root,Vector3(0,size.y*.5,0),Vector3(size.x*.7,.018,size.z*.8),dark,false)
	Batch.collapse(root,[],"magazine_detail_"+str(w.get("id",w.get("kind","unknown"))));root.set_meta("profile",p);return root
