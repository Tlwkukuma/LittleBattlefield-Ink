extends SceneTree
## Frozen registration/lifecycle fixture; no world ticks, firing, or gameplay input.
const Flash=preload("res://scripts/flash_batches.gd")
const Effects=preload("res://scripts/weapon_effects.gd")
var checks=0
var failures=0
var report=[]
func check(value: bool,label: String):
	checks+=1
	if not value:failures+=1;printerr("FAIL "+label)
func _initialize():call_deferred("run")
func muzzle(stage: Node3D,weapon: Dictionary) -> Node3D:
	var socket=Node3D.new();stage.add_child(socket)
	return Effects.flash(socket,weapon)
func run():
	var catalog=preload("res://scripts/source_catalog.gd").new()
	var rifle: Dictionary=catalog.weapons["m416"]
	check(preload("res://scripts/fx_instance_batches.gd").CAPACITY==360,"other FX capacity unchanged")
	for number in range(1,11):
		var source: Dictionary=catalog.scenes[number-1]
		var stage=Node3D.new();root.add_child(stage)
		var batches=Flash.new();stage.add_child(batches);batches.set_process(false)
		var roots=[];var infantry=0;var mounted=0
		for side in ["blue","red"]:infantry+=int(source.deployment[side].maxActive)
		for index in range(infantry):roots.append(muzzle(stage,rifle))
		for spec in source.get("vehicles",[]):
			var profile: Dictionary=catalog.data.vehicles[spec.type]
			for mode in profile.weaponOrder:
				roots.append(muzzle(stage,profile.weapons[mode]));mounted+=1
		for spec in source.get("emplacements",[]):
			roots.append(muzzle(stage,catalog.data.emplacements[spec.type]));mounted+=1
		var pieces=0
		for flash in roots:pieces+=flash.get_child_count();batches.register_tree(flash)
		check(infantry<=Flash.MAX_INFANTRY and mounted<=Flash.MAX_MOUNTED_MUZZLES,"source bounded %02d"%number)
		check(batches.pool.stats().instances==pieces,"all actual pieces registered %02d"%number)
		check(batches.entries.size()==roots.size(),"all roots retained %02d"%number)
		check(pieces<=Flash.REGISTRATION_CAPACITY,"source fits fixed capacity %02d"%number)
		batches.refresh();check(batches.active==0,"initially hidden %02d"%number)
		roots[0].show();batches.refresh();check(batches.active==1,"one visible muzzle %02d"%number)
		roots[0].hide();batches.refresh();check(batches.active==0,"hidden again %02d"%number)
		# Swap-delete must update handles held by other muzzles. Reuse repeatedly
		# without accumulating old registrations across replacement generations.
		for generation in range(20):
			var old=roots[0];batches.unregister_tree(old);old.free()
			roots[0]=muzzle(stage,rifle);batches.register_tree(roots[0])
			check(batches.pool.stats().instances==pieces,"replacement count %02d/%d"%[number,generation])
		var removed=roots[1].get_child_count();roots[1].free();batches.refresh()
		check(batches.pool.stats().instances==pieces-removed,"freed tombstone reclaimed %02d"%number)
		roots[1]=muzzle(stage,rifle);batches.register_tree(roots[1])
		check(batches.pool.stats().instances==pieces,"tombstone slot reused %02d"%number)
		for group in batches.pool.groups.values():
			check(group.instances.instance_count==Flash.REGISTRATION_CAPACITY,"allocation stays fixed %02d"%number)
			check(group.instances.visible_instance_count==group.entries.size(),"dense draw count %02d"%number)
			for slot in range(group.entries.size()):
				check(group.entries[slot].slot==slot and slot<group.instances.instance_count,"valid dense slot %02d/%d"%[number,slot])
		report.append({"chapter":number,"infantry":infantry,"mounted_channels":mounted,"actual_registered_pieces":pieces,"five_piece_bound":(infantry+mounted)*5})
		batches.unregister_tree(stage)
		check(batches.entries.is_empty() and batches.pool.stats().instances==0,"complete unregister %02d"%number)
		stage.free()
	# Worst authored population/mount combination plus all 16 deployable mortars.
	var stage=Node3D.new();root.add_child(stage)
	var batches=Flash.new();stage.add_child(batches);batches.set_process(false)
	for index in range(Flash.REGISTRATION_CAPACITY/5):batches.register_tree(muzzle(stage,rifle))
	check(batches.pool.stats().instances==880,"all 880 pieces fit with no truncation")
	check(batches.pool.stats().batches==1,"one shared muzzle batch retained")
	batches.unregister_tree(stage);check(batches.pool.stats().instances==0,"capacity fixture fully released")
	stage.free()
	var fresh=Flash.new();root.add_child(fresh);fresh.set_process(false)
	check(fresh.entries.is_empty() and fresh.pool.stats().instances==0,"scene reset has no registrations")
	fresh.free()
	var output={"checks":checks,"failures":failures,"capacity":Flash.REGISTRATION_CAPACITY,"chapters":report}
	var file=FileAccess.open("res://qa/flash_registration_contract.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("FLASH_REGISTRATION "+JSON.stringify(output));quit(1 if failures else 0)
