extends SceneTree
## Resource/routing checks only: never plays a sound, fires or advances AI.
const Original=preload("res://scripts/source_weapon_audio.gd")
const Free=preload("res://scripts/free_weapon_audio.gd")
const FireModes=preload("res://scripts/weapon_fire_control.gd")
var checks=0
var failures=0

func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)

func _initialize():run.call_deferred()

func run():
	var game=load("res://proving_ground.tscn").instantiate();game.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(game)
	var audio=game.fx.feedback.audio
	var before=JSON.stringify(Original.data)
	var matched=0
	for weapon in game.catalog.weapons.values():
		var p: Dictionary=Free.profile(weapon)
		if Free.Ordnance.applies(weapon):
			matched+=1
			check(p.get("restored_ordnance",false),"requested launcher uses restored source")
			check(p.gain==Original.profile(weapon).gain and p.lowpass==Original.profile(weapon).lowpass,"restored launch gain and filter")
			check(audio.streams.has(p.sample),"restored launcher preloaded")
			continue
		if Free.data.weapons.has(str(weapon.id)):
			matched+=1
			check(p.has("recording_bank"),"matched firearm uses recording bank: "+str(weapon.id))
			check(Free.samples(p,2,false)==Free.samples(p,30,true),"local shots always use near recording")
			if not str(weapon.id) in Free.data.event_only_weapons:
				check(Free.samples(p,2,false)!=Free.samples(p,30,false),"world distance chooses distinct recording")
			check(p.group==Original.profile(weapon).group,"source group throttles retained")
		else:check(false,"unmapped equipment: "+str(weapon.id))
	check(matched==84,"all handheld equipment covered")
	check(Free.data.fallback_weapons.is_empty(),"legacy fallback list is empty")
	check(Free.data.banks.size()==37,"bank count bounded")
	check(Free.data.assets.size()==171,"clip count bounded")
	check(audio.streams.size()==Free.data.assets.size()+15,"free palette plus requested contact and ordnance overrides only")
	check(audio.streams.grenade_contact.mix_rate==22050 and audio.streams.grenade_contact.data.size()==3968,"former 90 ms grenade contact restored")
	for key in Free.Ordnance.FILES:
		check(audio.streams[key].resource_path.begins_with("res://assets/audio/restored-ordnance/"),"restored blast/launch resource")
	for key in audio.ContactAudio.FILES:
		var restored: AudioStreamWAV=audio.streams[key]
		check(restored.resource_path.begins_with("res://assets/audio/restored-contacts/"),"requested contact override preloaded")
	for key in ["case","case_soft"]:
		var restored: AudioStreamWAV=audio.streams[key]
		check(restored.mix_rate==22050 and restored.data.size()==1984,"former short casing sound restored")
	var bytes=0
	for key in Free.data.assets:
		var info: Dictionary=Free.data.assets[key];var stream=audio.streams.get(key)
		check(stream is AudioStreamWAV,"sample resolves from preloaded pool: "+str(key))
		if not stream is AudioStreamWAV:continue
		bytes+=stream.data.size()
		check(stream.mix_rate==48000 and not stream.stereo and stream.format==AudioStreamWAV.FORMAT_16_BITS,"48k mono PCM16")
		check(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"one-shot clip never loops")
		check(absf(stream.get_length()-float(info.duration))<.001,"duration intact after Godot import")
		check(float(info.duration)<=2.61 and float(info.peak)<.83,"bounded duration and headroom")
		check(stream.resource_path.begins_with("res://assets/audio/free-firearms/"),"no legacy audio loaded")
		var hashed=HashingContext.new();hashed.start(HashingContext.HASH_SHA256);hashed.update(FileAccess.get_file_as_bytes(info.path))
		check(hashed.finish().hex_encode()==info.sha256,"derived file integrity")
	for bank in Free.data.banks.values():
		check(bank.near.size()>=2 and bank.mid.size()>=2,"at least two free variants per bank")
		for key in bank.near+bank.mid:check(audio.streams.has(key),"all variants loaded before firing")
	for key in FireModes.MOUNTED_MODES:
		check(Free.data.mounted.has(key),"mounted mode covered: "+str(key))
		var p: Dictionary=Free.profile({"id":"m416","kind":"bullet","sound":"vehicleMg","mounted_fire_key":key})
		check(p.recording_bank==Free.data.mounted[key],"mount mapping takes precedence over infantry ID")
		check(audio.streams.has(p.sample),"mounted sample is ready")
	check(Free.data.mounted.size()==18,"all mounted modes including deployable mortar")
	for kind in game.catalog.data.vehicles:
		for slot in game.catalog.data.vehicles[kind].weapons:
			var weapon: Dictionary=game.catalog.data.vehicles[kind].weapons[slot]
			if Free.Ordnance.applies(weapon):
				var p: Dictionary=Free.profile(weapon)
				check(p.get("restored_ordnance",false) and audio.streams.has(p.sample),"real mounted launcher restored")
				check(p.gain==Original.profile(weapon).gain and p.lowpass==Original.profile(weapon).lowpass,"mounted original launch parameters")
			else:check(Free.profile(weapon).recording_bank==Free.data.mounted[weapon.mounted_fire_key],"real vehicle catalog binding")
	for weapon in game.catalog.data.emplacements.values():
		if Free.Ordnance.applies(weapon):check(audio.streams.has(Free.profile(weapon).sample),"field gun launch restored")
		else:check(Free.profile(weapon).recording_bank==Free.data.mounted[weapon.mounted_fire_key],"real emplacement catalog binding")
	for event in ["blast","flesh","stone","wood","earth","metal","glass","melee","swing","case","case_soft","throw","grenade_contact"]:
		check(Free.data.events.has(event),"combat event covered: "+event)
		for key in Free.data.banks[Free.data.events[event]].near:check(audio.streams.has(key),"event sample preloaded")
	check(Free.profile({"id":"unknown","kind":"shell"}).recording_bank=="cannon_medium","unknown weapon defaults to free material")
	check(JSON.stringify(Original.data)==before,"legacy baseline is immutable")
	check(audio.voices.size()==24,"voice pool stays 8 / 12 / 4")
	check(bytes<17*1024*1024,"entire free palette below 17 MiB")
	check(audio.played==0 and audio.sample_cursors.is_empty(),"resource check did not play audio")
	check(game.world.time==0 and game.world.shots==0,"no gameplay simulation")
	print("FREE_WEAPON_AUDIO_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"matched":matched,"clips":Free.data.assets.size(),"pcm_bytes":bytes,"voice_limit":audio.voices.size(),"played":audio.played,"world_time":game.world.time,"shots":game.world.shots,"version":game.BUILD_VERSION}))
	game.free();quit(0 if failures==0 else 1)
