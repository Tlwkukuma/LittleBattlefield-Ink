extends RefCounted
## AI aims into an observed direction, never searches live target body parts.
## One imperfect mark per sensory report; interpolation does no ray/pose query.
const MAX_REPORT_AGE=.75
const TURN_RATE=3.2
const PITCH_RATE=1.5
const AIM_HEIGHT=[.96,.68,.30]
const MUZZLE_HEIGHT=[1.33,1.00,.425]

static func fresh(contact: Dictionary,now: float) -> bool:
	var age=now-float(contact.get("observed_at",-100))
	return contact.get("source","")=="vision" and age>=0 and age<=MAX_REPORT_AGE

static func error_degrees(unit: Dictionary,weapon: Dictionary) -> float:
	var family=str(weapon.get("archetype","assault"))
	var cone=1.1 if family in ["sniper","antimaterial"] else 1.7 if family in ["rifle","boltRifle","battleRifle"] else 2.6
	return cone+minf(1,Vector2(unit.get("velocity",Vector2.ZERO)).length()/2.8)*2.2+clampf(float(unit.get("ai_stress",0)),0,1)*3.0

static func observe(unit: Dictionary,contact: Dictionary,weapon: Dictionary,noise: Vector2):
	# Copy value types only: no target/capsule reference and no predictive velocity.
	var position: Vector2=contact.position;var stance=clampi(int(contact.get("stance",0)),0,2)
	unit.ai_aim_mark=Vector3(position.x,float(contact.get("elevation",0))+AIM_HEIGHT[stance],position.y)
	unit.ai_aim_observed_at=float(contact.observed_at)
	unit.ai_aim_contact_id=int(contact.get("id",unit.get("ai_target",-1)))
	unit.ai_aim_contact_epoch=int(contact.get("spawn_epoch",0))
	var cone=deg_to_rad(error_degrees(unit,weapon))
	unit.ai_yaw_error=clampf(noise.x,-1,1)*cone
	unit.ai_pitch_error=clampf(noise.y,-1,1)*cone*.45

static func track(unit: Dictionary,delta: float) -> bool:
	if not unit.has("ai_aim_mark"):return false
	var mark: Vector3=unit.ai_aim_mark;var planar=Vector2(mark.x,mark.z)-Vector2(unit.position)
	var distance=maxf(.5,planar.length())
	var origin_y=float(unit.elevation)+MUZZLE_HEIGHT[clampi(int(unit.stance),0,2)]
	var yaw=planar.angle()+float(unit.ai_yaw_error)
	var pitch=clampf(atan2(mark.y-origin_y,distance)+float(unit.ai_pitch_error),-.85,.85)
	unit.facing=Vector2.from_angle(rotate_toward(unit.facing.angle(),yaw,maxf(0,delta)*TURN_RATE))
	unit.ai_aim_pitch=move_toward(float(unit.get("ai_aim_pitch",0)),pitch,maxf(0,delta)*PITCH_RATE)
	unit.aim_point=unit.position+unit.facing*distance
	unit.aim_height=origin_y+tan(float(unit.ai_aim_pitch))*distance
	return absf(wrapf(yaw-unit.facing.angle(),-PI,PI))<.18 and absf(pitch-float(unit.ai_aim_pitch))<.12

# A clear lane is bound to observed target life and weapon, not the report clock.
# Renewing vision of the same target must not suppress every firing opportunity.
# These scalar checks deliberately do not query a live enemy or add a ray.
static func cache_fire_context(unit: Dictionary,contact: Dictionary,weapon: Dictionary):
	unit.ai_fire_contact_id=int(contact.get("id",unit.get("ai_target",-1)))
	unit.ai_fire_contact_epoch=int(contact.get("spawn_epoch",0))
	unit.ai_fire_observed_at=float(contact.get("observed_at",-100))
	unit.ai_fire_weapon_id=str(weapon.get("id",""))

static func fire_context_matches(unit: Dictionary,contact: Dictionary,weapon: Dictionary) -> bool:
	return not contact.is_empty() and int(unit.get("ai_fire_contact_id",-2))==int(contact.get("id",unit.get("ai_target",-1))) and int(unit.get("ai_fire_contact_epoch",-1))==int(contact.get("spawn_epoch",0)) and str(unit.get("ai_fire_weapon_id",""))==str(weapon.get("id",""))
