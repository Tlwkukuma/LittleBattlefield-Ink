extends RefCounted
## Hold to prepare, release to throw. Mouse distance sets force, not hold duration.
const RELEASE_TIME=.16
const RECOVER_TIME=.30
static func cancel(u: Dictionary,lock: bool=true) -> void:
	u.throw_state={}
	if lock:u.throw_lock=true

static func update(u: Dictionary,w: Dictionary,delta: float,held: bool,pressed: bool,target: Vector3,allowed: bool) -> bool:
	if not held and not pressed:u.throw_lock=false
	if not allowed or w.kind!="grenade":cancel(u);return false
	var state: Dictionary=u.get("throw_state",{})
	if not state.is_empty():
		state.age+=delta
		if state.phase=="recover":
			if state.age>=RECOVER_TIME:u.throw_state={}
			return false
		if u.reload>0 or u.ammo<=0:cancel(u);return false
		if state.phase=="aim":
			state.target=target;state.low=bool(u.get("throw_low",false)) or int(u.stance)==2
			if not held:state.phase="windup";state.age=0.0
		elif state.phase=="windup" and state.age>=RELEASE_TIME:return true
		return false
	if pressed and not bool(u.get("throw_lock",false)) and u.reload<=0 and u.cooldown<=0 and u.ammo>0:
		u.throw_state={"phase":"aim" if held else "windup","age":0.0,"target":target,"low":bool(u.get("throw_low",false)) or int(u.stance)==2}
	return false

static func released(u: Dictionary) -> void:
	if u.get("throw_state",{}).is_empty():return
	u.throw_state.phase="recover";u.throw_state.age=0.0

static func fuse(w: Dictionary) -> float:
	# Starts on release. No accidental cooking while measuring a lob.
	return 2.2 if w.get("payload","")=="smoke" else 2.8
