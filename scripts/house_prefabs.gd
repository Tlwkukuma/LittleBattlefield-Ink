extends RefCounted
const Furniture=preload("res://scripts/house_furniture.gd")
const ID="building.residence-two-storey"
const STOREY=3.4
const WALL_HEIGHT=3.18
const WALL_THICKNESS=.28
const GROUND_FLOOR=.04
const STAIR_RISE=(STOREY-GROUND_FLOOR)/20.0
const STAIR_TREAD=.30
const STAIR_WIDTH=1.7
const INNER_LOWER_X=-6.9
const INNER_UPPER_X=-5.0

static func register(catalog):
	Furniture.register(catalog)
	catalog.prefabs[ID]={"id":ID,"label":"宽敞两层住宅 · U 形内梯 / 平台外梯 / 全屋家具","footprint":[[-320,-240],[320,-240],[320,240],[-320,240]],"housing":true,"godot_height":6.8}
	catalog.templates[ID]={"walls":[],"trees":[],"world":{"groundFeatures":[]}}
	for spec in [["structure.floor","二楼楼板",2,2,.22],["structure.stair","实体楼梯踏步",STAIR_WIDTH,STAIR_TREAD,STAIR_RISE],["structure.rail","楼梯扶手",.09,STAIR_TREAD,1.0]]:
		catalog.components[spec[0]]={"id":spec[0],"label":spec[1],"primitive":"area","material":"wood" if spec[0]=="structure.rail" else "concrete","defaults":{"length":spec[2]*40,"thickness":spec[3]*40},"runtime":{"kind":"barrier" if spec[0]=="structure.rail" else "concrete","output":"structure","collision":true,"blocksProjectiles":true,"damageable":true}}

static func emit_box(catalog,plan,out,instance,id: String,component: String,at: Vector2,size: Vector2,height: float,base: float,level: int,extra: Dictionary={}):
	var scale=Vector2(float(instance.get("scaleX",instance.get("scale",1))),float(instance.get("scaleY",instance.get("scale",1))))
	var angle=float(instance.get("rotation",0));var center=catalog.v(instance)+(at*scale).rotated(angle)*40
	var axis=Vector2(size.x*scale.x*.5,0).rotated(angle)*40
	var details={"height":height,"elevation":base+float(instance.get("godot3d",{}).get("elevation",0)),"health_scale":float(instance.get("godot3d",{}).get("health_scale",1))}
	for key in ["destructible","material"]:
		if instance.get("godot3d",{}).has(key):details[key]=instance.godot3d[key]
	var o=catalog.object_from_segment(str(instance.id)+"."+id,component,center-axis,center+axis,size.y*scale.y*40,plan,details,str(instance.id))
	o.house=true;o.storey=level;o.house_local=at;o.merge(extra,true)
	if extra.has("health_scale"):o.health_scale*=float(details.health_scale)
	out.objects.append(o)
	return o

static func wall(catalog,plan,out,instance,id: String,a: Vector2,b: Vector2,level: int,windows: bool=true):
	var angle=(b-a).angle();var along=a.distance_to(b)
	# Compiler instance rotation is applied after local walls; swap axis for cross-walls.
	var o=emit_box(catalog,plan,out,instance,id,"wall.brick",(a+b)*.5,Vector2(along,WALL_THICKNESS),WALL_HEIGHT,level*STOREY,level,{"windows":windows and bool(instance.get("godot3d",{}).get("windows",true)),"house_role":"wall"})
	o.angle+=angle
	if absf(sin(angle))>.5:
		var sx=float(instance.get("scaleX",instance.get("scale",1)));var sy=float(instance.get("scaleY",instance.get("scale",1)))
		o.size=Vector2(along*sy,WALL_THICKNESS*sx)
	return o

static func furnish(catalog,plan,out,instance,id: String,kind: String,at: Vector2,level: int,angle: float=0):
	var size: Vector3=Furniture.SIZES[kind]
	var o=emit_box(catalog,plan,out,instance,id,"furniture."+kind,at,Vector2(size.x,size.z),size.y,.04 if level==0 else level*STOREY,level,{"house_role":"furniture"})
	o.angle+=angle

static func stair_flight(catalog,plan,out,instance,prefix: String,x: float,start_z: float,direction: float,first_step: int):
	for i in range(10):
		var height=GROUND_FLOOR+STAIR_RISE*(first_step+i+1)
		var at=Vector2(x,start_z+direction*(i+.5)*STAIR_TREAD)
		var id=prefix+"-step-"+str(first_step+i)
		emit_box(catalog,plan,out,instance,id,"structure.stair",at,Vector2(STAIR_WIDTH,STAIR_TREAD),height,0,0,{"house_role":"stairs","health_scale":4.0,"walk_step":true,"stair_nose":-direction})
		for side in [-1,1]:
			emit_box(catalog,plan,out,instance,id+"-rail-"+str(side),"structure.rail",at+Vector2(side*.88,0),Vector2(.075,STAIR_TREAD),1.02,height,0,{"house_role":"stair_rail","support_parent":str(instance.id)+"."+id})

static func stairs(catalog,plan,out,instance,floor_ids):
	# Two short flights and a full turn platform keep the foyer clear of the first riser.
	stair_flight(catalog,plan,out,instance,"inner",INNER_LOWER_X,1.0,-1,0)
	stair_flight(catalog,plan,out,instance,"inner",INNER_UPPER_X,-2.0,1,10)
	var middle=GROUND_FLOOR+STAIR_RISE*10
	emit_box(catalog,plan,out,instance,"inner-mid-landing","structure.stair",Vector2(-5.95,-3),Vector2(3.8,2.0),middle,0,0,{"house_role":"stairs","health_scale":4.0,"walk_step":true,"stair_landing":true})
	var landing=emit_box(catalog,plan,out,instance,"inner-top-landing","structure.floor",Vector2(-5,1.5),Vector2(2,1),.22,STOREY-.22,1,{"house_role":"floor","health_scale":7.0,"floor_neighbors":[floor_ids[Vector2i(1,4)].id]})
	floor_ids[Vector2i(1,4)].floor_neighbors.append(landing.id)
	# Exterior straight stair also has a rest landing and a level approach.
	stair_flight(catalog,plan,out,instance,"outer",9.0,4.8,-1,0)
	stair_flight(catalog,plan,out,instance,"outer",9.0,0.0,-1,10)
	emit_box(catalog,plan,out,instance,"outer-mid-landing","structure.stair",Vector2(9,.9),Vector2(STAIR_WIDTH,1.8),middle,0,0,{"house_role":"stairs","health_scale":4.0,"walk_step":true,"stair_landing":true})
	emit_box(catalog,plan,out,instance,"outer-approach","structure.floor",Vector2(9,5.8),Vector2(2,2),GROUND_FLOOR,0,0,{"house_role":"floor","health_scale":7.0,"floor_finish":"entry-stone","entry_edge":"north"})
	for spec in [
		["inner-mid-west",Vector2(-7.82,-3),Vector2(.075,2),"inner-mid-landing"],
		["inner-mid-north",Vector2(-5.95,-3.96),Vector2(3.8,.075),"inner-mid-landing"],
		["inner-mid-east",Vector2(-4.08,-3),Vector2(.075,2),"inner-mid-landing"],
		["outer-mid-west",Vector2(8.12,.9),Vector2(.075,1.8),"outer-mid-landing"],
		["outer-mid-east",Vector2(9.88,.9),Vector2(.075,1.8),"outer-mid-landing"]]:
		emit_box(catalog,plan,out,instance,spec[0],"structure.rail",spec[1],spec[2],1.02,middle,0,{"house_role":"stair_rail","support_parent":str(instance.id)+"."+spec[3]})
	# Rail the actual stairwell void; the upper return exits south onto a wide hall.
	for spec in [[Vector2(-6,-4),Vector2(4,.10)],[Vector2(-4,-1),Vector2(.10,6)],[Vector2(-7,2),Vector2(2,.10)],[Vector2(-6,1.5),Vector2(.10,1)],[Vector2(10,-4.3),Vector2(.10,2.6)],[Vector2(9,-5.6),Vector2(2,.10)]]:
		emit_box(catalog,plan,out,instance,"guard-"+str(out.objects.size()),"structure.rail",spec[0],spec[1],1.05,STOREY,1,{"house_role":"guard"})

static func compile(catalog,plan,out,instance):
	var offset=float(instance.get("godot3d",{}).get("elevation",0))
	for level in range(2):
		wall(catalog,plan,out,instance,"north-"+str(level),Vector2(-8,-6),Vector2(8,-6),level)
		wall(catalog,plan,out,instance,"west-"+str(level),Vector2(-8,-6),Vector2(-8,6),level)
		if level==0:
			wall(catalog,plan,out,instance,"south-left-0",Vector2(-8,6),Vector2(-1.2,6),level).door_jambs=[1]
			wall(catalog,plan,out,instance,"south-right-0",Vector2(1.2,6),Vector2(8,6),level).door_jambs=[-1]
			wall(catalog,plan,out,instance,"east-0",Vector2(8,-6),Vector2(8,6),level)
			wall(catalog,plan,out,instance,"partition-a-0",Vector2(1.7,-6),Vector2(1.7,-1.5),level,false).door_jambs=[1]
			wall(catalog,plan,out,instance,"partition-b-0",Vector2(1.7,.6),Vector2(1.7,2.1),level,false).door_jambs=[-1]
		else:
			wall(catalog,plan,out,instance,"south-1",Vector2(-8,6),Vector2(8,6),level)
			wall(catalog,plan,out,instance,"east-north-1",Vector2(8,-6),Vector2(8,-5.2),level,false).door_jambs=[1]
			wall(catalog,plan,out,instance,"east-south-1",Vector2(8,-3.0),Vector2(8,6),level).door_jambs=[-1]
			wall(catalog,plan,out,instance,"partition-a-1",Vector2(.8,-6),Vector2(.8,-1.7),level,false).door_jambs=[1]
			wall(catalog,plan,out,instance,"partition-b-1",Vector2(.8,.5),Vector2(.8,6),level,false).door_jambs=[-1]
	# Every two-metre slab is a genuine destructible horizontal solid, with a stairwell void.
	for z in range(6):
		for x in range(8):
			emit_box(catalog,plan,out,instance,"ground-floor-%d-%d"%[x,z],"structure.floor",Vector2(-7+x*2,-5+z*2),Vector2(2,2),.04,0,0,{"house_role":"floor","health_scale":7.0,"floor_finish":"tile" if x>=5 else "wood"})
	emit_box(catalog,plan,out,instance,"front-approach","structure.floor",Vector2(0,6.7),Vector2(2.4,1.4),.04,0,0,{"house_role":"floor","health_scale":7.0,"floor_finish":"entry-stone","entry_edge":"north"})
	var floor_ids={}
	for z in range(6):
		for x in range(8):
			if x in [0,1] and z in [1,2,3]:continue
			var key=Vector2i(x,z);var id="floor-%d-%d"%[x,z]
			var o=emit_box(catalog,plan,out,instance,id,"structure.floor",Vector2(-7+x*2,-5+z*2),Vector2(2,2),.22,STOREY-.22,1,{"house_role":"floor","health_scale":7.0,"floor_key":key,"floor_neighbors":[]})
			floor_ids[key]=o
	for key in floor_ids:
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if floor_ids.has(key+d):floor_ids[key].floor_neighbors.append(floor_ids[key+d].id)
	var roof_ids={}
	for z in range(6):
		for x in range(8):
			var key=Vector2i(x,z)
			roof_ids[key]=emit_box(catalog,plan,out,instance,"roof-%d-%d"%[x,z],"structure.floor",Vector2(-7+x*2,-5+z*2),Vector2(2,2),.22,STOREY+WALL_HEIGHT,2,{"house_role":"roof","health_scale":5.0,"floor_neighbors":[]})
	for key in roof_ids:
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if roof_ids.has(key+d):roof_ids[key].floor_neighbors.append(roof_ids[key+d].id)
	var balcony=emit_box(catalog,plan,out,instance,"balcony","structure.floor",Vector2(9,-4.3),Vector2(2,2.6),.22,STOREY-.22,1,{"house_role":"floor","health_scale":7.0,"floor_finish":"entry-stone","entry_edge":"west","entry_start":.4/2.6,"floor_neighbors":[floor_ids[Vector2i(7,0)].id,floor_ids[Vector2i(7,1)].id]})
	for key in [Vector2i(7,0),Vector2i(7,1)]:floor_ids[key].floor_neighbors.append(balcony.id)
	stairs(catalog,plan,out,instance,floor_ids)
	for spec in [["sofa",Vector2(-1.8,1.0),0,0],["coffee-table",Vector2(-1.8,2.5),0,0],["shelf",Vector2(-2.5,-5.65),0,0],["plant",Vector2(6.8,4.8),0,0],["table",Vector2(4.8,2.6),0,0],["chair",Vector2(4.2,3.8),0,PI],["chair",Vector2(5.3,3.8),0,PI],["chair",Vector2(4.2,1.35),0,0],["chair",Vector2(5.3,1.35),0,0],["counter",Vector2(4.4,-5.4),0,0],["fridge",Vector2(7,-5.25),0,0],["dresser",Vector2(7.5,-1.7),0,PI*.5],["desk",Vector2(-1.3,-3.6),0,0],["chair",Vector2(-1.3,-2.6),0,PI],["bed",Vector2(4.5,3.65),1,PI],["wardrobe",Vector2(6.7,.6),1,PI*.5],["dresser",Vector2(6.8,4.8),1,PI*.5],["desk",Vector2(3.3,-5.1),1,0],["chair",Vector2(3.3,-4),1,PI],["bed",Vector2(-1.7,3.6),1,PI],["shelf",Vector2(-2,-5.7),1,0],["plant",Vector2(6.9,-2.5),1,0]]:
		furnish(catalog,plan,out,instance,"furniture-"+str(out.objects.size()),spec[0],spec[1],spec[2],spec[3])
	var scale=Vector2(float(instance.get("scaleX",instance.get("scale",1))),float(instance.get("scaleY",instance.get("scale",1))))
	var angle=float(instance.get("rotation",0));var points=[];var zone=[]
	for p in [Vector2(-8,-6),Vector2(8,-6),Vector2(8,6),Vector2(-8,6)]:points.append(catalog.position_point(catalog.v(instance)+(p*scale).rotated(angle)*40,plan))
	for p in [Vector2(-8,-6),Vector2(10,-6),Vector2(10,6),Vector2(-8,6)]:zone.append(catalog.position_point(catalog.v(instance)+(p*scale).rotated(angle)*40,plan))
	# Only the volume behind the interior wall faces grants the indoor cutaway.
	# The wider zone includes exterior access and must never reveal the rooms.
	var interior=PackedVector2Array();var half=Vector2(8,6)-Vector2.ONE*WALL_THICKNESS*.5
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:interior.append(catalog.position_point(catalog.v(instance)+(corner*half*scale).rotated(angle)*40,plan))
	out.roofs.append({"id":instance.id,"points":points,"zone":zone,"interior_points":interior,"interior_height":STOREY+WALL_HEIGHT,"height":offset+STOREY+WALL_HEIGHT+.22,"elevation":offset,"style":ID,"enabled":bool(instance.get("godot3d",{}).get("roof",true)),"house":true,"storey_height":STOREY})
	out.houses.append({"id":instance.id,"points":points,"zone":zone,"base":offset,"storey_height":STOREY})
