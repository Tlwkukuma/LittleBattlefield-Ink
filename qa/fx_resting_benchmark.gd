extends SceneTree
## Frozen scene and cosmetic workload only: no world.step(), shooting or model.
const Catalog=preload("res://scripts/source_catalog.gd")
const World=preload("res://scripts/proving_world.gd")
const Orchard=preload("res://scripts/orchard_level.gd")
const FX=preload("res://scripts/proving_fx.gd")
const Ammo=preload("res://scripts/ammo_presentation.gd")
const Magazine=preload("res://scripts/weapon_magazine.gd")
var label="before"
func _initialize():run.call_deferred()
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):label=arg.trim_prefix("--label=")
	var catalog=Catalog.new();var world=World.new();world.setup(Orchard.plan(catalog),catalog)
	var fx=FX.new();fx.world=world;fx.catalog=catalog;fx.silent=true;fx.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(fx)
	for i in range(160):
		var unit: Dictionary=world.units[i%60];var at=unit.position+Vector2((i%5)*.12,(i%7)*.14)
		var a=Ammo.profile(catalog.weapons[["m416","akm","s1897","p92"][i%4]])
		var p=fx.piece(Vector3(at.x,world.terrain.height(at)+.08,at.y),a.case_size,a.case_color,Vector3.ZERO,100,false,0,"case",a)
		p.settled=true;p.rolling=true;p.bounces=2;p.support_age=0.0;p.floor=world.terrain.height(at);p.softness=1.0
	for i in range(32):
		var u=world.units[i].duplicate();u.alive=true;u.reload=1;u.weapon_id="m416"
		fx.drop_magazine({"unit":u,"weapon":catalog.weapons.m416,"position":Vector3(u.position.x,u.elevation+.1,u.position.y),"angle":0})
	for i in range(120):fx._process(1.0/60)
	var times=[]
	for i in range(180):
		var started=Time.get_ticks_usec();fx._process(1.0/60);times.append((Time.get_ticks_usec()-started)/1000.0)
	times.sort()
	var result={"label":label,"cases":160,"magazines":32,"samples":times.size(),"p50_ms":times[times.size()/2],"p95_ms":times[int(times.size()*.95)],"max_ms":times[-1],"simulation_time":world.time,"shots":world.shots,"ai_mode":world.campaign_director.diagnostics().mode}
	if fx.has_method("batching_stats"):result.batching=fx.batching_stats()
	var file=FileAccess.open("res://qa/performance/fx-resting-"+label+".json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"\t"));file.close()
	print("FX_RESTING_BENCHMARK "+JSON.stringify(result));fx.free();quit()
