extends RefCounted
## User-requested restoration of v.28 contacts only; gunshots remain free assets.
const FILES={"flesh":"shot_hit","stone":"wall_hit","wood":"wall_hit","earth":"wall_hit","metal":"deflect_shot","glass":"deflect_shot"}

static func streams() -> Dictionary:
	var result: Dictionary={};var files: Dictionary={}
	for key in FILES:
		var path="res://assets/audio/restored-contacts/"+FILES[key]+".wav"
		if not files.has(path):files[path]=load(path) as AudioStreamWAV
		result[key]=files[path]
	# Isolated RNG reproduces the former startup sequence without changing FX RNG.
	var rng=RandomNumberGenerator.new();rng.seed=937
	for i in range(int(22050*.12)+int(22050*.22)+int(22050*.60)):rng.randf_range(-1,1)
	for key in ["case","case_soft"]:
		var data=PackedByteArray();data.resize(int(22050*.045)*2)
		var filtered=0.0
		for i in range(data.size()/2):
			var t=float(i)/22050;filtered=lerpf(filtered,rng.randf_range(-1,1),.65)
			var value=(sin(t*TAU*2800)*.45+sin(t*TAU*4170)*.22+filtered*.10)*exp(-t*95) if key=="case" else (sin(t*TAU*620)*.35+filtered*.28)*exp(-t*115)
			data.encode_s16(i*2,int(clampf(value,-1,1)*23000))
		var wav=AudioStreamWAV.new();wav.format=AudioStreamWAV.FORMAT_16_BITS;wav.mix_rate=22050;wav.data=data
		result[key]=wav
	# The former throw cue preceded grenade contact in the deterministic sequence.
	for i in range(int(22050*.16)):rng.randf_range(-1,1)
	var contact=PackedByteArray();contact.resize(int(22050*.09)*2)
	var filtered=0.0
	for i in range(contact.size()/2):
		var t=float(i)/22050;filtered=lerpf(filtered,rng.randf_range(-1,1),.65)
		var value=(sin(t*TAU*390)*.42+filtered*.35)*exp(-t*57)
		contact.encode_s16(i*2,int(clampf(value,-1,1)*23000))
	var grenade=AudioStreamWAV.new();grenade.format=AudioStreamWAV.FORMAT_16_BITS;grenade.mix_rate=22050;grenade.data=contact
	result["grenade_contact"]=grenade
	return result
