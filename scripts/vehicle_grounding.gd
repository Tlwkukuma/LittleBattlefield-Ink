extends RefCounted
## Sample the same triangle heights used to draw the terrain, including negative elevations.
const Dimensions=preload("res://scripts/vehicle_dimensions.gd")
const Offroad=preload("res://scripts/vehicle_offroad.gd")
const Collision=preload("res://scripts/vehicle_collision.gd")
const Structure=preload("res://scripts/vehicle_structure_support.gd")

static func tracked(v: Dictionary) -> bool:
	return v.type not in ["armedJeep","scoutCar"]

static func surface(profile: Dictionary, tracks: bool) -> Dictionary:
	var id: String=profile.id;var soft=clampf(float(profile.get("softness",0)),0,1)
	var result={"name":"草地","grip":.91,"speed":.95,"drag":.40,"rough":.025}
	if "snow" in id:result={"name":"积雪","grip":lerpf(.82,.65 if tracks else .48,soft),"speed":lerpf(.94,.78 if tracks else .60,soft),"drag":lerpf(.48,1.15,soft),"rough":.07}
	elif "desert" in id or "sand" in id:result={"name":"沙地","grip":lerpf(.92,.80 if tracks else .64,maxf(.3,soft)),"speed":lerpf(.92,.80 if tracks else .65,maxf(.3,soft)),"drag":lerpf(.55,1.25,maxf(.3,soft)),"rough":.055}
	elif "mud" in id or "marsh" in id:result={"name":"泥地","grip":.73 if tracks else .54,"speed":.72 if tracks else .55,"drag":1.15,"rough":.085}
	elif "road" in id or "asphalt" in id or "concrete" in id or "yard" in id:result={"name":"硬路","grip":1.0,"speed":1.0,"drag":.25,"rough":.006}
	elif "mountain" in id or "hill" in id or "rock" in id:result={"name":"山坡","grip":.86,"speed":.87,"drag":.5,"rough":.065}
	elif "trench" in id or "red-earth" in id:result={"name":"土路","grip":.86,"speed":.90,"drag":.5,"rough":.04}
	elif "water" in id or "creek" in id:result={"name":"深水","grip":.3,"speed":.3,"drag":2.0,"rough":0.0,"blocked":true}
	return result

static func begin_step(v: Dictionary) -> void:
	v.support_step_cache={"poses":{},"revision":-1}

static func end_step(v: Dictionary) -> void:
	v.erase("support_step_cache")

static func sample(terrain,v: Dictionary,at: Vector2,angle: float,materials: bool=true,world=null) -> Dictionary:
	# Cache only within this vehicle's current physics update. Probe dictionaries share
	# this bounded cache; a destruction revision invalidates it before the next query.
	var cache: Dictionary=v.get("support_step_cache",{})
	if cache.is_empty():return sample_uncached(terrain,v,at,angle,materials,world)
	var revision=int(world.get("topology_revision")) if world!=null and world.get("topology_revision")!=null else 0
	if cache.revision!=revision or cache.get("elevation",INF)!=v.get("elevation",0):
		cache.poses.clear();cache.revision=revision;cache.elevation=v.get("elevation",0)
	var key=Vector4(at.x,at.y,angle,1.0 if materials else 0.0)
	if cache.poses.has(key):return cache.poses[key]
	var result=sample_uncached(terrain,v,at,angle,materials,world)
	if cache.poses.size()<96:cache.poses[key]=result
	return result

static func sample_uncached(terrain,v: Dictionary,at: Vector2,angle: float,materials: bool=true,world=null) -> Dictionary:
	var d=Dimensions.for_vehicle(v);var tracks=tracked(v)
	var capability=Offroad.profile(v)
	var half: Vector2=d.half
	# Avoid a coplanar tread / ground surface while keeping one shared vehicle pose.
	var contact_offset=.04*d.model_scale.y-.012 if tracks else 0.0
	var axle=half.x*(.75 if tracks else .61)
	var gauge=half.y*.79
	var forward=Vector2.from_angle(angle);var side=Vector2(-forward.y,forward.x)
	var wheel_radius=(.31 if v.type=="scoutCar" else .29)*d.model_scale.y
	var rocks=Offroad.nearby(world,v,at,half.length()+wheel_radius)
	var structures=Structure.nearby(world,v,at,half.length()+wheel_radius)
	var sum=0.0;var along=0.0;var across=0.0;var xx=0.0;var zz=0.0
	var contacts=[];var grip=0.0;var speed=0.0;var drag=0.0;var rough=0.0;var names={};var flooded=false;var rock_contacts=0;var timber=false;var structure_contacts=0
	for x in ([-axle,0.0,axle] if tracks else [-axle,axle]):
		for z in [-gauge,gauge]:
			var point=at+forward*x+side*z;var contact=Structure.contact(Offroad.contact(terrain,rocks,point,wheel_radius,v),structures,point,wheel_radius)
			if contact.structure:structure_contacts+=1
			timber=timber or contact.timber
			var h: float=contact.height
			contacts.append({"at":point,"local":Vector2(x,z),"height":h,"rock":contact.rock})
			if contact.rock!="":rock_contacts+=1
			sum+=h;along+=h*x;across+=h*z;xx+=x*x;zz+=z*z
			if materials:
				var s=surface({"id":"concrete"} if contact.structure else terrain.profile_at(point),tracks)
				grip+=s.grip;speed+=s.speed;drag+=s.drag;rough+=s.rough;names[s.name]=int(names.get(s.name,0))+1;flooded=flooded or s.get("blocked",false)
			else:
				var id: String=terrain.material_at(point)
				flooded=flooded or (not contact.structure and ("water" in id or "creek" in id))
	var count=float(contacts.size());var height=sum/count
	var slope=Vector2(along/maxf(.001,xx),across/maxf(.001,zz))
	var residual=0.0;var raised=0.0
	for contact in contacts:
		var error: float=contact.height-height-slope.dot(contact.local)
		residual=maxf(residual,absf(error));raised=maxf(raised,error)
	# A narrow log can sit anywhere under a continuous belt, including between axles.
	# Extra belt contacts carry the rigid hull; empty space below it is not suspension strain.
	if tracks and (not rocks.is_empty() or not structures.is_empty()):
		for fraction in [-2.0/3,-1.0/3,1.0/3,2.0/3]:
			for z in [-gauge,gauge]:
				var x=axle*fraction;var point=at+forward*x+side*z
				var contact=Structure.contact(Offroad.contact(terrain,rocks,point,wheel_radius,v),structures,point,wheel_radius)
				if contact.structure:structure_contacts+=1
				elif contact.rock!="":rock_contacts+=1;timber=timber or contact.timber
				else:continue
				raised=maxf(raised,float(contact.height)-height-slope.dot(Vector2(x,z)))
	# A rigid belt bridges its support points; wheels absorb a limited difference in suspension.
	# A continuous belt is supported by high terrain contacts as well as rocks.
	# Averaging a dune crest with both lower ends incorrectly buried the chassis.
	if tracks or rock_contacts>0:height+=maxf(0,raised-float(capability.compression))
	# A crest between the wheels must not pass through the underside of the hull.
	var belly=0.0
	for x in [-half.x*.86,0.0,half.x*.86]:
		for z in [-half.y*.67,0.0,half.y*.67]:
			var point=at+forward*x+side*z
			var top=Structure.contact(Offroad.contact(terrain,rocks,point,0,v),structures,point,0).height
			var underside=(float(capability.clearance)+(.27 if absf(x)>half.x*.84 else .10 if absf(x)>half.x*.62 else 0.0))*sqrt(1.0+slope.length_squared())
			belly=maxf(belly,top-height-slope.dot(Vector2(x,z))-underside)
	var label="草地";var votes=0
	for name in names:
		if names[name]>votes:label=name;votes=names[name]
	var grade=forward*slope.x+side*slope.y
	var normal=Vector3(-grade.x,1,-grade.y).normalized()
	var support_lift=0.0
	if not rocks.is_empty():
		var probe=v.duplicate();probe.position=at;probe.angle=angle;probe.pose_basis=basis(angle,normal)
		probe.elevation=height-contact_offset
		# A small skid contact can extend the suspension; a high-centred hull stays blocked.
		support_lift=Collision.rock_support_lift(probe,rocks,float(capability.step)*.40)
		if is_finite(support_lift):height+=support_lift;belly=maxf(0,belly-support_lift)
	var structure_lift=0.0
	if not structures.is_empty():
		var probe=v.duplicate();probe.position=at;probe.angle=angle;probe.pose_basis=basis(angle,normal);probe.elevation=height-contact_offset
		structure_lift=Structure.gear_lift(probe,structures)
		if is_finite(structure_lift):height+=structure_lift;belly=maxf(0,belly-structure_lift)
	if structure_contacts>0:label="建筑地板"
	var passable=absf(slope.x)<capability.grade and absf(slope.y)<capability.cross and residual<capability.articulation and belly<.012 and is_finite(support_lift) and is_finite(structure_lift) and not flooded
	if rock_contacts>0 or support_lift>0:label="倒木越障" if timber else "低障碍越障";rock_contacts=maxi(1,rock_contacts)
	return {"height":height-contact_offset,"normal":normal,"slope":slope,"gradient":grade,"residual":residual,"belly":belly,"passable":passable,
		"contacts":contacts,"rocks":rocks,"structures":structures,"rock_contacts":rock_contacts,"flooded":flooded,"support_lift":support_lift,"grip":grip/count if materials else 1.0,"speed":minf(speed/count,capability.pace) if rock_contacts>0 and materials else speed/count if materials else 1.0,"drag":drag/count if materials else .4,"rough":rough/count,"label":label}

static func basis(angle: float,normal: Vector3) -> Basis:
	var f=Vector3(cos(angle),-(normal.x*cos(angle)+normal.z*sin(angle))/maxf(.1,normal.y),sin(angle)).normalized()
	return Basis(f.cross(normal).normalized(),normal,-f)

static func descending(v: Dictionary,support: Dictionary,point: Vector2) -> bool:
	if v.position.distance_squared_to(point)<.00000001 or support.get("flooded",false) or not is_finite(float(support.get("support_lift",0))):return false
	var previous: Array=v.get("ground",{}).get("contacts",[])
	if previous.size()!=support.contacts.size() or previous.is_empty():return false
	var drop=0.0
	for i in range(previous.size()):
		var change=float(support.contacts[i].height)-float(previous[i].height)
		if change>.012:return false # Never turn this into an uphill / obstacle bypass.
		drop-=change
	return (drop>.0001 or (v.get("descending",false) and drop>=-.0001)) and float(support.height)<=float(v.ground.height)+.015

static func descent_support(support: Dictionary) -> Dictionary:
	var result=support.duplicate()
	# A lip can carry the underbody briefly while wheels extend into the drop.
	# Keep the same sampled underside clearance rather than sinking into the rim.
	result.height+=maxf(0,float(result.belly));result.belly=0.0;result.descent=true
	return result

static func initialize(terrain,v: Dictionary,world=null) -> void:
	if v.emplacement:
		if v.get("deployed",false):return
		v.elevation=terrain.height(v.position);return
	v.ground=sample(terrain,v,v.position,v.angle,true,world)
	v.elevation=v.ground.height;v.pose_basis=basis(v.angle,v.ground.normal)
