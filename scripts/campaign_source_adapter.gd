extends RefCounted
## Explicit compatibility fallback, not an export of the missing Pixi runtime.
const BASE_PATH="res://data/campaign/level01_rules.json"

static func apply_loadouts(plan: Dictionary) -> void:
	var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(BASE_PATH))
	var fallback_used=false
	if not has_loadout(plan.deployment.player):
		plan.deployment.player.loadout=baseline.deployment.player.get("loadout",["M416","P92","Army Knife","HE Grenade"]).duplicate();fallback_used=true
	for side in ["blue","red"]:
		var pool: Array=baseline.units[side]
		for index in range(plan.units[side].size()):
			if has_loadout(plan.units[side][index]):continue
			plan.units[side][index].loadout=ordinary(pool[index%pool.size()].loadout);fallback_used=true
		var force: Dictionary=plan.deployment[side]
		if force.get("replacementLoadouts",[]).is_empty():
			var count=maxi(0,int(force.totalForce)-int(force.initialCount));var replacements=[]
			var original: Array=baseline.deployment[side].replacementLoadouts
			for index in range(count):replacements.append(ordinary(original[index%original.size()]))
			# Preserve authored finite special-weapon counts, without claiming the
			# unavailable runtime's exact scheduling. Spread them through reserves.
			for special in force.get("specialWeaponPlans",[]):
				var amount=mini(count,maxi(0,int(special.get("count",0))))
				for index in range(amount):
					var slot=clampi(int(float(index+1)*count/float(amount+1)),0,maxi(0,count-1))
					if replacements[slot].size()<4:replacements[slot].append(str(special.weapon))
					else:replacements[slot][3]=str(special.weapon)
			force.replacementLoadouts=replacements;fallback_used=true
	plan.campaignSource={"sceneId":plan.get("godot3d",{}).get("sourceSceneId",plan.get("id","")),"runtimeExportAvailable":false,"compatibilityLoadouts":fallback_used,
		"fallbackSource":BASE_PATH,"sourceDeploymentPreserved":true,"specialAllocation":"finite source counts, evenly scheduled through reserves; exact original sequence unavailable"}

static func has_loadout(spec: Dictionary) -> bool:
	var values=spec.get("loadout",[])
	return values is Array and not values.is_empty() and values.all(func(value):return value is String and not value.is_empty())

static func ordinary(source: Array) -> Array:
	var result=source.duplicate()
	for index in range(result.size()):
		if result[index]=="Portable Mortar":result[index]="HE Grenade"
	return result
