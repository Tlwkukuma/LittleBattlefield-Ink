extends RefCounted
## Source-only offline layout. OrchardLevel remains the separate LAN/training map.
const RULES_PATH="res://data/campaign/level01_rules.json"

static func plan(catalog,entry: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for source in catalog.scenes:
		if str(source.id)==str(entry.sourceSceneId):result=source.duplicate(true);break
	if result.is_empty():return {}
	result.id="campaign-chapter-%02d"%int(entry.id)
	result.godot3d={"campaign":true,"range":false,"sourceSceneId":entry.sourceSceneId,"source_scale":40,"source_layout":true}
	for mount in result.get("emplacements",[]):mount.aiControlled=true
	result.campaignRules={"captureTime":7,"replacementWaveSeconds":.5,"replacementWaveSize":5,"handoffSeconds":1.18}
	if int(entry.id)==1:
		# The verified export supplies equipment/rules only. Its source geometry,
		# identities, coordinates, facing and all ten anchors per side stay intact.
		var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
		result.campaignRules=baseline.rules.duplicate(true)
		result.campaignSource=baseline.source.duplicate(true)
		result.campaignSource.runtimeExportAvailable=true
		result.campaignSource.sourceDeploymentPreserved=true
		result.deployment.player.loadout=baseline.deployment.player.loadout.duplicate()
		for side in ["blue","red"]:
			var equipment={}
			for unit in baseline.units[side]:equipment[str(unit.id)]=unit.loadout
			for unit in result.units[side]:
				if equipment.has(str(unit.id)):unit.loadout=equipment[str(unit.id)].duplicate()
			result.deployment[side].replacementLoadouts=baseline.deployment[side].replacementLoadouts.duplicate(true)
		# Chapter one previously had no source stage because it reused OrchardLevel.
		# Build its public routes from the actual source anchors and control point.
		var point: Dictionary=result.controlPoints[0].duplicate(true)
		point.captureTime=float(result.campaignRules.get("captureTime",7));point.captureHeight=1.8
		var routes={"blue":[],"red":[]}
		for side in ["blue","red"]:
			for anchor in result.deployment[side].spawnPoints:
				routes[side].append([[anchor.x,anchor.y],[point.x,point.y]])
		result.campaignMission={"stages":[{"point":point,"mode":"capture","holdSeconds":0,"briefing":"占领原版果园据点，或耗尽敌方兵力","aiRoutes":routes,"tactics":{}}],"eliminationCompletes":true}
	else:
		preload("res://scripts/campaign_source_adapter.gd").apply_loadouts(result)
		result.campaignMission={"stages":entry.stages.duplicate(true),"eliminationCompletes":true}
	return result
