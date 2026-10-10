extends Node3D
## Bounded world-space boot impressions with raised powder/sand edges.
const Geometry=preload("res://scripts/terrain_art.gd")
const Ink=preload("res://scripts/ink_art.gd")
const MAX_STAMPS=180
var world
var stamps: Array=[]
var drawing: MeshInstance3D
var dirty=false
var expiry=0.0

func _ready():
	drawing=MeshInstance3D.new();drawing.material_override=Ink.ink_material(Color.WHITE,true,.03);add_child(drawing)
	drawing.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func add_step(at: Vector2,direction: Vector2):
	var profile=world.terrain.profile_at(at)
	if profile.id not in ["terrain.snow","terrain.desert"] or profile.cover<.08:return
	stamps.append({"at":at,"forward":direction.normalized(),"snow":profile.id=="terrain.snow","soft":profile.softness,"time":world.time})
	if stamps.size()>MAX_STAMPS:stamps.pop_front()
	dirty=true

func _process(delta: float):
	expiry-=delta
	if expiry<=0:
		expiry=1.0
		while not stamps.is_empty() and world.time-float(stamps[0].time)>100:stamps.pop_front();dirty=true
	if dirty:rebuild();dirty=false

func rebuild():
	var v=PackedVector3Array();var n=PackedVector3Array();var c=PackedColorArray()
	for stamp in stamps:
		var forward: Vector2=stamp.forward;var side=Vector2(-forward.y,forward.x)
		var outline=[Vector2(-.075,-.17),Vector2(.075,-.17),Vector2(.09,-.09),Vector2(.09,.12),Vector2(.065,.19),Vector2(-.065,.19),Vector2(-.09,.12),Vector2(-.09,-.09)]
		var dark=Color("809da9") if stamp.snow else Color("9e825d")
		var edge=Color("e5e9df") if stamp.snow else Color("dfc89b")
		var inner=[];var outer=[]
		for p in outline:
			var at: Vector2=stamp.at+side*p.x+forward*p.y
			var rim: Vector2=stamp.at+side*p.x*1.32+forward*p.y*1.13
			inner.append(Vector3(at.x,world.terrain.height(at)+.006,at.y))
			outer.append(Vector3(rim.x,world.terrain.height(rim)+lerpf(.011,.040 if stamp.snow else .022,stamp.soft),rim.y))
		var center=Vector3(stamp.at.x,world.terrain.height(stamp.at)+.007,stamp.at.y)
		for i in range(outline.size()):
			var j=(i+1)%outline.size()
			for p in [center,inner[i],inner[j]]:v.append(p);n.append(Vector3.UP);c.append(dark)
			for p in [inner[i],outer[i],outer[j],inner[i],outer[j],inner[j]]:v.append(p);n.append(Vector3.UP);c.append(edge)
	drawing.mesh=Geometry.mesh_from(v,n,c)
