extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const Chapters=preload("res://scripts/campaign_catalog.gd")
var checks=0
var failures=0
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():
	var catalog=Catalog.new();var original=JSON.stringify(catalog.scenes)
	for number in range(2,11):
		var source: Dictionary=catalog.scenes[number-1];var plan=Chapters.plan(catalog,number)
		check(plan.campaignMission.stages.size()==1 and plan.campaignMission.stages[0].mode=="capture","chapter %d single source objective"%number)
		check(float(plan.controlPoints[0].captureTime)==7 and plan.controlPoints[0].initialOwner=="neutral","chapter %d source capture rules"%number)
		check(plan.controlPoints[0].x==source.controlPoints[0].x and plan.controlPoints[0].y==source.controlPoints[0].y,"chapter %d exact original gameplay center"%number)
		check(plan.campaignSource.sceneId==source.id,"chapter %d original source identity"%number)
		check(plan.controlPoints[0].id==source.controlPoints[0].id and plan.controlPoints[0].r==source.controlPoints[0].r,"chapter %d original objective identity/radius"%number)
		check(plan.world==source.world and plan.looseSegments==source.looseSegments and plan.trees==source.trees and plan.instances==source.instances,"chapter %d original layout"%number)
		check(plan.vehicles==source.vehicles,"chapter %d original mobile vehicles"%number)
		check(plan.emplacements.size()==source.emplacements.size(),"chapter %d original mount count"%number)
		for team in ["blue","red"]:
			for key in ["initialCount","maxActive","totalForce","spawnPoints"]:check(plan.deployment[team][key]==source.deployment[team][key],"chapter %d %s source %s"%[number,team,key])
			for index in range(plan.units[team].size()):
				check(plan.units[team][index].x==source.units[team][index].x and plan.units[team][index].y==source.units[team][index].y,"chapter %d unit position retained"%number)
			for index in range(plan.units[team].size()):
				check(plan.units[team][index].get("angle",0)==source.units[team][index].get("angle",0),"chapter %d source facing retained"%number)
			var loadouts=[]
			for unit in plan.units[team]:loadouts.append(unit.loadout)
			if team=="blue":loadouts.append(plan.deployment.player.loadout)
			loadouts.append_array(plan.deployment[team].replacementLoadouts)
			check(loadouts.size()==int(plan.deployment[team].totalForce),"chapter %d %s finite force equipment"%[number,team])
			var mortar_count=0
			for loadout in loadouts:
				for weapon in loadout:
					check(catalog.weapons.has(weapon) or catalog.weapons.values().any(func(w):return w.name==weapon),"chapter %d weapon resolves: %s"%[number,weapon])
				if "Portable Mortar" in loadout:mortar_count+=1
			var expected=0
			for special in source.deployment[team].get("specialWeaponPlans",[]):
				if special.weapon=="Portable Mortar":expected=int(special.count)
			check(mortar_count==expected,"chapter %d %s source finite mortar count"%[number,team])
		check(plan.campaignSource.runtimeExportAvailable==false,"chapter %d fallback honestly identified"%number)
	check(JSON.stringify(catalog.scenes)==original,"immutable imported scene data unchanged")
	print("campaign_source_data_contract: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
