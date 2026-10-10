extends RefCounted
## One shared physical height for the hull, collision, weapons and occupants.
const Ground=preload("res://scripts/vehicle_grounding.gd")
const Collision=preload("res://scripts/vehicle_collision.gd")

static func settle(world,v: Dictionary,support: Dictionary,delta: float) -> Dictionary:
	if v.get("descending",false):support=Ground.descent_support(support)
	var floor_height=float(support.height);var before=float(v.elevation)
	if before<=floor_height+.001:
		v.elevation=floor_height;v.fall_speed=0.0;v.airborne=false
		return support
	v.fall_speed=maxf(-12,float(v.get("fall_speed",0))-18*delta)
	var target=maxf(floor_height,before+float(v.fall_speed)*delta)
	# A wall under the descending car remains solid. Bound all vertical sweeps.
	var count=clampi(ceili((before-target)/.06),1,12)
	var probe=v.duplicate();var blocked=false
	for i in range(1,count+1):
		probe.elevation=lerpf(before,target,float(i)/count)
		if Collision.blocked(world,probe):blocked=true;break
		v.elevation=probe.elevation
	var landing=blocked or float(v.elevation)<=floor_height+.001
	if landing:
		var impact=absf(float(v.fall_speed))
		v.drive_pitch=clampf(float(v.drive_pitch)+impact*.003,-.06,.06)
		v.drive_roll=clampf(float(v.drive_roll)+minf(.015,impact*.002),-.06,.06)
		v.fall_speed=0.0
	v.airborne=not landing and float(v.elevation)-floor_height>.08
	return support
