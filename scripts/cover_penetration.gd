extends RefCounted
## Shared material cost; parametric chord includes thickness, angle and actual solid voids.
const MAX_LAYERS=4
static func segment_limit(inside: Dictionary,traveled: float,budget: float) -> float:
	var result=budget
	for expires in inside.values():
		if float(expires)>traveled:result=minf(result,maxf(.00001,float(expires)-traveled))
	return result
static func key(hit: Dictionary) -> String:
	return "object:"+str(hit.get("target",{}).get("id",""))

static func response(weapon: Dictionary,hit: Dictionary,direction: Vector3,budget: float) -> Dictionary:
	var material: Dictionary=hit.get("target",{}).get("cover_material",{})
	var entry=float(hit.get("distance",0));var exit=float(hit.get("exit_distance",-1))
	if hit.get("type","")!="object" or material.is_empty() or not is_finite(exit) or exit<=entry+.00001:return {"pass":false}
	var ammo: Dictionary=weapon.get("cover_ammo",{})
	if ammo.get("lane","")!="kinetic" or budget<=0:return {"pass":false}
	var thickness=(exit-entry)*direction.length()
	var cost=float(material.resistance)*thickness/maxf(.001,float(material.thickness_m))
	if not is_finite(cost) or cost<=0 or cost>=budget:return {"pass":false,"cost":cost}
	return {"pass":true,"cost":cost,"remaining":budget-cost,"damage_scale":clampf(float(material.penetrated_damage_scale),0,1),"thickness":thickness}
