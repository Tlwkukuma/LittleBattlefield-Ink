extends RefCounted
## One attack owns its timing, aim and hit set; render and damage share its phase.
static func profile(w: Dictionary) -> Dictionary:
	var kind="stab" if w.id=="army-knife" else "chop" if w.id=="fire-axe" else "slash"
	return {"kind":kind,"duration":60.0/maxf(1,w.rpm),"start":.34 if kind=="stab" else .39 if kind=="chop" else .35,"end":.58 if kind=="stab" else .61 if kind=="chop" else .64}
static func begin(u: Dictionary,w: Dictionary,target: Vector2):
	var p=profile(w);var toward=target-u.position
	u.melee={"weapon":w.id,"age":0.0,"previous":0.0,"duration":p.duration,"angle":toward.angle() if toward.length()>.1 else u.facing.angle(),"height":float(u.aim_height),"hit":[],"swish":false}
static func cancel(u: Dictionary):u.melee={}
static func advance(u: Dictionary,w: Dictionary,delta: float,allowed: bool) -> bool:
	var a: Dictionary=u.get("melee",{})
	if a.is_empty():return false
	if not allowed or w.id!=a.weapon or w.kind!="melee":cancel(u);return false
	a.previous=a.age;a.age+=delta
	if a.previous>=a.duration:cancel(u);return false
	var p=profile(w)
	return a.previous<a.duration*p.end and a.age>=a.duration*p.start
static func sample(w: Dictionary,age: float) -> Dictionary:
	var p=profile(w);var t=clampf(age/p.duration,0,1)
	var wind=smoothstep(0,p.start,t);var strike=smoothstep(p.start,p.end,t);var recover=smoothstep(p.end,1,t)
	return {"phase":t,"wind":wind,"strike":strike,"recover":recover,"weight":smoothstep(0,.13,t)*(1-recover)}
static func within(u: Dictionary,v: Dictionary,w: Dictionary) -> bool:
	var a: Dictionary=u.melee;var d: Vector2=v.position-u.position
	if d.length()>float(w.range)/40.0:return false
	if absf(wrapf(d.angle()-a.angle,-PI,PI))>float(w.get("hitAngle",.6)):return false
	return true
