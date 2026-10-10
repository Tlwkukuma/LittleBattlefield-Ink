extends Node3D
## A fixed 8 / 12 / 4 voice pool, with reserved player cues and priority stealing.
const SourceAudio=preload("res://scripts/source_weapon_audio.gd")
const FreeAudio=preload("res://scripts/free_weapon_audio.gd")
const ContactAudio=preload("res://scripts/contact_audio.gd")
var world
var camera: Camera3D
var streams: Dictionary={}
var voices: Array=[]
var gates: Dictionary={}
var buses: Array[String]=[]
var frame=-1
var writes=0
var local_writes=0
var dropped=0
var played=0
var muted=false
var shot_gates: Dictionary={}
var sample_cursors: Dictionary={}
var occlusion: Dictionary={}
var occlusion_frame=-1
var occlusion_queries=0
var occlusion_revision=-1

func _ready():
	for key in FreeAudio.data.assets:
		streams[key]=load(FreeAudio.data.assets[key].path) as AudioStreamWAV
	streams.merge(ContactAudio.streams(),true)
	streams.merge(FreeAudio.Ordnance.streams(),true)
	for i in range(24):
		# One reusable filter per voice: changing guns never retunes another gun's tail.
		var name="Combat_%s_%s"%[get_instance_id(),i];AudioServer.add_bus();var index=AudioServer.bus_count-1
		AudioServer.set_bus_name(index,name);AudioServer.set_bus_send(index,"Master");buses.append(name)
		var filter=AudioEffectLowPassFilter.new();var pan=AudioEffectPanner.new()
		AudioServer.add_bus_effect(index,filter);AudioServer.add_bus_effect(index,pan)
		var voice=AudioStreamPlayer.new();voice.bus=name;voice.max_polyphony=1;add_child(voice)
		voices.append({"node":voice,"filter":filter,"pan":pan,"bus":index,"score":0.0,"end":0.0})
	set_process(false)
	if "--startup-watch" in OS.get_cmdline_user_args():
		print("FREE_WEAPON_AUDIO_READY banks=",FreeAudio.data.banks.size()," clips=",FreeAudio.data.assets.size()," weapons=",FreeAudio.data.weapons.size()," mounted=",FreeAudio.data.mounted.size()," restored_contacts=9 restored_ordnance=6 voices=",voices.size())

func _exit_tree():
	for v in voices:v.node.stop()
	for name in buses:
		var index=AudioServer.get_bus_index(name)
		if index>0:AudioServer.remove_bus(index)

func clear():
	gates.clear();shot_gates.clear();occlusion.clear();sample_cursors.clear()
	for v in voices:v.node.stop();v.end=0.0

func play_shot(e: Dictionary) -> void:
	if muted:return
	var w: Dictionary=e.weapon;var p=FreeAudio.profile(w)
	if str(p.sample).is_empty():return
	var local=bool(e.unit.player);var mount=int(e.get("mount",-1))
	# Original Game.js locates audio at the shooter/vehicle, not the animated muzzle.
	var position: Vector2=e.unit.position
	if mount>=0 and mount<world.vehicles.size():position=world.vehicles[mount].position
	var at=Vector3(position.x,float(e.height),position.y)
	var limits=SourceAudio.spatial_range(w);var offset: Vector2=position-world.player.position
	var distance=offset.length()
	if distance>=limits.x:return
	var t=clampf((distance-2.25)/maxf(.025,limits.x-2.25),0,1)
	var volume=limits.y*pow(1-t,1.42)
	if volume<=.018:return
	var transmission=1.0 if local or distance<=2.25 else sound_transmission(at,mount)
	volume*=pow(transmission,.46)
	if volume<=.018:return
	var muffle=clampf((1-transmission)*.94+t*.16,0,.96)
	var gap=.011 if volume>.72 else .018 if volume>.40 else .032 if volume>.18 else .058
	if str(p.group)=="flame":gap=maxf(gap,.085)
	# Retain original group throttling, with a separate local lane so AI cannot mute us.
	var group=("local/" if local else "world/")+str(p.group);var now=Time.get_ticks_msec()*.001
	if now-float(shot_gates.get(group,-100))<gap:return
	shot_gates[group]=now
	var mix={"volume":volume,"master":float(SourceAudio.data.master_gain),
		"cutoff":maxf(260,float(p.lowpass)*(1-muffle*.86)),"q":pow(10,(.45+muffle*.85)/20.0),
		"pan":clampf(offset.x/maxf(13,limits.x*.58),-.82,.82)}
	var samples: Array=FreeAudio.samples(p,distance,local)
	var sequence=str(samples[0])+("/local" if local else "/world")
	var cursor=int(sample_cursors.get(sequence,0));sample_cursors[sequence]=(cursor+1)%samples.size()
	play(str(samples[cursor]),at,3.0 if local else 1.0,1.0,float(p.gain),local,"",mix)

func sound_transmission(at: Vector3,mount: int) -> float:
	# Native breakable 3D walls use a bounded acoustic approximation, not per-shot
	# full scene/material scans. No projectile or AI visibility reads this cache.
	var current=Engine.get_process_frames()
	if current!=occlusion_frame:occlusion_frame=current;occlusion_queries=0
	if occlusion_revision!=world.topology_revision:occlusion.clear();occlusion_revision=world.topology_revision
	var eye: Vector3=world.CombatPose.eye(world.player)
	var key=Vector4i(floori(at.x/4.5),floori(at.z/4.5),floori(eye.x/4.5),floori(eye.z/4.5))
	var previous: Dictionary=occlusion.get(key,{})
	var same_height=not previous.is_empty() and absf(at.y-float(previous.height))<.6 and absf(eye.y-float(previous.eye_height))<.6
	if same_height and world.time<float(previous.until):return previous.value
	if occlusion_queries>=2:return float(previous.value) if same_height else 1.0
	occlusion_queries+=1
	var line=eye-at;var hit: Dictionary=world.trace_3d(at,line.normalized(),line.length(),{"mount":mount},true)
	var transmission=1.0 if hit.is_empty() else .40
	# The listener's own vehicle is not a wall between them and the outside sound.
	if hit.get("type","")=="vehicle" and int(hit.target.id)==int(world.player.get("mounted",-1)):transmission=1.0
	if occlusion.size()>=256:occlusion.clear()
	occlusion[key]={"until":world.time+.125,"height":at.y,"eye_height":eye.y,"value":transmission}
	return transmission

func play(key: String,at: Vector3,priority: float=1.0,pitch: float=1.0,gain: float=1.0,local: bool=false,gate: String="",mix: Dictionary={}) -> void:
	if muted:return
	# Preserve semantic event identity (notably the reserved blast pool) while
	# selecting free foley variants. Shot calls already pass a concrete clip key.
	var stream_key=key
	if not streams.has(key) and FreeAudio.data.events.has(key):
		var event_bank: Dictionary=FreeAudio.data.banks[FreeAudio.data.events[key]]
		var choices: Array=event_bank.near;var sequence="event/"+key
		var cursor=int(sample_cursors.get(sequence,0));sample_cursors[sequence]=(cursor+1)%choices.size()
		stream_key=str(choices[cursor])
	if not streams.has(stream_key) or streams[stream_key]==null:return
	var distance: float=Vector2(at.x,at.z).distance_to(world.player.position)
	if mix.is_empty() and not local and distance>65:return
	var current=Engine.get_process_frames()
	if current!=frame:frame=current;writes=0;local_writes=0
	if (local and local_writes>=8) or (not local and writes>=8):dropped+=1;return
	var now=Time.get_ticks_msec()*.001
	if not gate.is_empty():
		if now-float(gates.get(gate,-100))<(.065 if key in ["flesh","metal","stone","wood","earth","glass"] else .022):return
		if gates.size()>=512:gates.clear()
		gates[gate]=now
	var tail=key=="blast";var begin=0 if local else 20 if tail else 8;var end=8 if local else 24 if tail else 20
	var attenuation=pow(clampf(1-distance/65.0,0,1),1.6)
	var loudness=gain*float(mix.get("volume",maxf(.22,attenuation) if local else attenuation))
	var score=priority+loudness;var slot=-1;var weakest=INF
	for i in range(begin,end):
		var v: Dictionary=voices[i]
		if not v.node.playing or now>=float(v.end):slot=i;break
		var remaining=clampf((float(v.end)-now)/.25,0,1);var live=float(v.score)*remaining
		if live<weakest:weakest=live;slot=i
	if slot<0 or (voices[slot].node.playing and now<float(voices[slot].end) and weakest>score):dropped+=1;return
	var selected: Dictionary=voices[slot];var voice: AudioStreamPlayer=selected.node
	voice.stop();voice.stream=streams[stream_key]
	var cutoff=float(mix.get("cutoff",20000 if local or distance<8 else 6500 if distance<26 else 2300))
	selected.filter.cutoff_hz=cutoff;selected.filter.resonance=float(mix.get("q",.5))
	# Godot FILTER_6DB is one biquad stage (confirmed in engine source), matching
	# Web Audio's one lowpass biquad. Web Audio lowpass Q is dB; Godot Q is linear.
	selected.filter.db=AudioEffectFilter.FILTER_6DB
	var bus_index=AudioServer.get_bus_index(voice.bus)
	AudioServer.set_bus_effect_enabled(bus_index,0,not mix.is_empty() or cutoff<20000)
	selected.pan.pan=float(mix.get("pan",clampf((at.x-world.player.position.x)/37.7,-.82,.82)))
	voice.pitch_scale=clampf(pitch,.55,1.5)
	voice.volume_db=linear_to_db(maxf(.00001,float(mix.get("master",db_to_linear(-17)))*loudness));voice.play()
	selected.score=score;selected.end=now+voice.stream.get_length()/voice.pitch_scale
	if local:local_writes+=1
	else:writes+=1
	played+=1

func stats() -> Dictionary:
	var active=0
	for v in voices:
		if v.node.playing:active+=1
	return {"voices":active,"capacity":24,"played":played,"dropped":dropped,"free_banks":FreeAudio.data.banks.size(),"free_weapons":FreeAudio.data.weapons.size()}
