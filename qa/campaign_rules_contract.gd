extends SceneTree
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Rules=preload("res://scripts/campaign_rules.gd")
var checks=0
var failures=0

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize() -> void:
	var catalog=Catalog.new();var plan: Dictionary={}
	for scene in catalog.scenes:
		if scene.id=="level-01":plan=scene.duplicate(true);break
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign/level01_rules.json"))
	plan.godot3d={"campaign":true};plan.campaignRules=source.rules;plan.units=source.units;plan.deployment=source.deployment;plan.controlPoints=source.controlPoints
	var world=World.new();world.setup(plan,catalog)
	check(world.campaign_active(),"campaign enabled")
	check(not world.invulnerable and not world.auto_targets and world.ai_enabled,"campaign safety toggles")
	check(world.units.size()==60 and world.campaign.active_counts()==[30,30],"30 vs 30 includes player")
	check(world.campaign.reserves==[90,90],"120 total less 30 active")
	check(world.units.filter(func(u):return u.player).size()==1,"single player")
	check(world.units.filter(func(u):return u.weapon_id!="m416").size()>20,"original varied loadouts")
	check(world.player.loadout==["m416","p92","army-knife","he-grenade"],"four source slots")
	world.equip("awm");check(world.player.weapon_id=="m416","armory restricted")
	world.player.ammo=11;world.equip_slot(1);world.equip_slot(0)
	check(world.player.ammo==11,"slots preserve ammo")
	var point={"capture_time":7.0,"progress":0.0}
	Rules.advance_point(point,1,0,3.5);check(is_equal_approx(point.progress,.5),"solo seven second capture")
	Rules.advance_point(point,1,1,1);check(point.progress<.5 and point.progress>0 and point.contested,"contest decays")
	point.progress=0.0;Rules.advance_point(point,2,0,7.0/1.18);check(point.owner==0,"two capture 1.18")
	point.progress=-1.0;Rules.advance_point(point,1,0,7);check(is_zero_approx(point.progress) and point.owner==-1,"neutralize before capturing")
	Rules.advance_point(point,1,0,7);check(point.owner==0,"capture after neutralize")
	# Direct rule state tests, not an automated playthrough.
	for unit in world.units:
		if unit.team==1:unit.alive=false;unit.death_age=1
	world.campaign.tick(.49)
	check(world.campaign.active_counts()[1]==0 and world.campaign.phase=="playing","no victory while reserves remain")
	world.campaign.tick(.02)
	check(world.campaign.active_counts()[1]==5 and world.campaign.reserves[1]==85,"half second five-person wave")
	check(world.units.size()==60,"stable actor slots")
	var seen_mortars=[0,0]
	# Exhaust each side's 90 authored replacements, counting equipment without simulation.
	for team in range(2):
		if team==1:
			for unit in world.units:
				if unit.team==1 and unit.alive and "portable-mortar" in unit.loadout:seen_mortars[1]+=1
		while world.campaign.reserves[team]>0:
			for unit in world.units:
				if unit.team==team and not unit.player:unit.alive=false;unit.death_age=1
			var before: int=world.campaign.reserves[team]
			world.campaign.reinforce(world,team,5)
			check(world.campaign.reserves[team]<before,"reinforcement makes progress")
			if world.campaign.reserves[team]==before:break
			for unit in world.units:
				if unit.team==team and unit.alive and not unit.player and "portable-mortar" in unit.loadout:seen_mortars[team]+=1
	check(seen_mortars==[3,2],"authored finite mortar allocation 3/2")
	check(world.campaign.deployed==[120,120] and world.units.size()==60,"finite 120 stable pool")
	# Ensure multiple living allies so nearest takeover has a deterministic answer.
	for unit in world.units:
		if unit.team==0 and not unit.player:unit.alive=true;unit.position=world.player.position+Vector2(10+unit.id,0)
	var previous: Dictionary=world.player;var next: Dictionary=world.units[1]
	next.position=previous.position+Vector2(1,0);previous.alive=false;previous.death_age=1.2
	world.campaign.tick(.01)
	check(world.player.id==next.id and world.player.player and not previous.player,"nearest living ally handoff")
	# A fresh match cannot use undeployed reserve troops to bypass no-living-ally defeat.
	world.setup(plan,catalog)
	for unit in world.units:
		if unit.team==0:unit.alive=false
	world.campaign.tick(.5)
	check(world.campaign.phase=="lost" and world.campaign.reserves[0]==90,"no ally defeat precedes replenishment")
	world.setup(plan,catalog)
	for unit in world.units:
		if unit.team==1:unit.alive=false
	world.campaign.reserves[1]=0;world.campaign.tick(.01)
	check(world.campaign.phase=="won","exhausted enemy victory")
	world.setup(plan,catalog)
	world.campaign.points[0].progress=-1;world.campaign.points[0].owner=1;world.campaign.tick(.01)
	check(world.campaign.phase=="playing","red flag ownership not instant defeat")
	world.setup(catalog.range_plan(),catalog)
	check(not world.campaign_active() and world.invulnerable and world.auto_targets and not world.ai_enabled,"training defaults restored")
	print("campaign_rules_contract: ",checks," checks, ",failures," failures")
	quit(1 if failures else 0)
