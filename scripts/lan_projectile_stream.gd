extends RefCounted
## Ordinary rounds replay only verified host segments, in the existing GPU batch.
const Flight=preload("res://scripts/bullet_flight_visual.gd")
const BUFFER_SECONDS=.04
const MAX_ROUNDS=1024
const MAX_FINISHES=256
const MAX_POINTS=16
var session
var finishes: Dictionary={}
var rounds: Dictionary={}
var completed: Dictionary={}
var received=0
var short_rounds=0
var played_finishes=0

func reset():
	finishes.clear();rounds.clear();completed.clear();received=0;short_rounds=0;played_finishes=0

func record(p: Dictionary,ended: bool) -> Array:
	if not Flight.supports(p.weapon):return []
	var origin=Flight.start(p);var point=Flight.at(p)
	var direction=Vector3(p.direction.x,float(p.get("slope",0)),p.direction.y)
	# A barrel obstruction may finish behind the muzzle; never replay a flight
	# through that obstruction from a socket which is outside the valid segment.
	if (point-origin).dot(direction)<-.001:return []
	var weapon: Dictionary=p.weapon
	return [int(p.id),int(p.source),str(weapon.get("id","")),str(weapon.get("mounted_fire_key","")),origin,point,direction,float(p.age),float(p.speed),ended,int(p.get("source_epoch",0)),int(p.team)]

func capture_finish(p: Dictionary,clock: float):
	var row=record(p,true)
	if row.is_empty():return
	if finishes.size()>=MAX_FINISHES and not finishes.has(int(p.id)):finishes.erase(finishes.keys()[0])
	finishes[int(p.id)]={"row":row,"until":clock+.18}

func packets(projectiles: Array,clock: float,observer: Dictionary) -> Array:
	for id in finishes.keys():
		if clock>float(finishes[id].until):finishes.erase(id)
	var records: Array=[]
	# Preserve the observer's own fire before background rounds. Finishes remain
	# available for five sends, including shots born and ended between snapshots.
	for priority in range(2):
		for p in projectiles:
			if (int(p.source)==int(observer.id))!=(priority==0):continue
			if priority==1 and p.position.distance_squared_to(observer.position)>65*65:continue
			var row=record(p,false)
			if not row.is_empty():records.append(row)
		for entry in finishes.values():
			var row: Array=entry.row
			if (int(row[1])==int(observer.id))!=(priority==0):continue
			var point: Vector3=row[5]
			if priority==1 and Vector2(point.x,point.z).distance_squared_to(observer.position)>65*65:continue
			records.append(row)
	var result: Array=[]
	var packet={"type":"rounds","time":clock,"rounds":[]}
	for row in records:
		packet.rounds.append(row)
		if var_to_bytes(packet).size()>1050:
			packet.rounds.pop_back()
			if not packet.rounds.is_empty():result.append(packet)
			packet={"type":"rounds","time":clock,"rounds":[row]}
			if var_to_bytes(packet).size()>1050:packet.rounds.clear()
	if not packet.rounds.is_empty():result.append(packet)
	return result

func accept(packet: Dictionary,now_usec: int=-1):
	if now_usec<0:now_usec=Time.get_ticks_usec()
	for id in completed.keys():
		if now_usec>int(completed[id]):completed.erase(id)
	var rows: Array=packet.get("rounds",[])
	for row in rows:
		if not row is Array or row.size()!=12:continue
		var id=int(row[0]);var age=float(row[7]);var ended=bool(row[9])
		if completed.has(id):continue
		var origin: Vector3=row[4];var point: Vector3=row[5];var direction: Vector3=row[6]
		if not origin.is_finite() or not point.is_finite() or not direction.is_finite() or not is_finite(age) or age<0 or age>8.1:continue
		var entry: Dictionary=rounds.get(id,{})
		if entry.is_empty():
			if rounds.size()>=MAX_ROUNDS:continue
			var weapon: Dictionary=session.resolve_weapon(str(row[2]),str(row[3]))
			if weapon.is_empty() or not Flight.supports(weapon):continue
			var p={"id":id,"source":int(row[1]),"weapon":weapon,"origin":Vector2(origin.x,origin.z),"start_height":origin.y,"position":Vector2(point.x,point.z),"height":point.y,"direction":Vector2(direction.x,direction.z).normalized(),"slope":direction.y,"speed":float(row[8]),"source_epoch":int(row[10]),"team":int(row[11])}
			entry={"round":p,"points":[{"age":0.0,"at":origin}],"cursor":0.0 if ended else maxf(0,age-BUFFER_SECONDS),"after_usec":now_usec if ended else now_usec+int(maxf(0,BUFFER_SECONDS-age)*1000000),"last_usec":now_usec,"seen_usec":now_usec,"ended":false,"fade_usec":-1}
			rounds[id]=entry
			if ended and age<.1:short_rounds+=1
		var last: Dictionary=entry.points.back()
		if age<float(last.age)-.00001 or (entry.ended and not ended):continue
		entry.seen_usec=now_usec
		# Even a birth-tick barrel stop has an endpoint, but zero duration cannot
		# support interpolation. Bound this presentation to one physics tick.
		var sample_age=maxf(age,1.0/60) if ended else age
		if sample_age>float(last.age)+.00001:entry.points.append({"age":sample_age,"at":point})
		elif ended:last.at=point
		while entry.points.size()>MAX_POINTS:entry.points.remove_at(1)
		if ended:entry.ended=true
		received+=1

func sample(now_usec: int=-1) -> Array:
	if now_usec<0:now_usec=Time.get_ticks_usec()
	var result: Array=[]
	for id in rounds.keys():
		var entry: Dictionary=rounds[id];var points: Array=entry.points
		if not entry.ended and now_usec-int(entry.seen_usec)>250000:rounds.erase(id);continue
		var elapsed=maxf(0,(now_usec-maxi(int(entry.last_usec),int(entry.after_usec)))/1000000.0)
		entry.last_usec=now_usec
		entry.cursor=minf(float(points.back().age),float(entry.cursor)+elapsed)
		while points.size()>2 and float(points[1].age)<float(entry.cursor):points.pop_front()
		var at: Vector3=points[0].at
		for index in range(1,points.size()):
			var before: Dictionary=points[index-1];var next: Dictionary=points[index]
			at=Vector3(before.at).lerp(next.at,clampf((float(entry.cursor)-float(before.age))/maxf(.00001,float(next.age)-float(before.age)),0,1))
			if float(entry.cursor)<=float(next.age):break
		var p: Dictionary=entry.round
		p.net_render_head=at;p.net_opacity=1.0
		if entry.ended and float(entry.cursor)>=float(points.back().age)-.00001:
			if int(entry.fade_usec)<0:entry.fade_usec=now_usec;played_finishes+=1
			var fade=(now_usec-int(entry.fade_usec))/1000000.0/maxf(.001,float(Flight.profile(p.weapon).fade))
			if fade>=1:
				completed[id]=now_usec+1000000
				if completed.size()>MAX_ROUNDS:completed.erase(completed.keys()[0])
				rounds.erase(id);continue
			p.net_opacity=1-fade
		result.append(p)
	return result
