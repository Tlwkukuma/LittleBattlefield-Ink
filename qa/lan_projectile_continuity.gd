extends SceneTree
const Stream=preload("res://scripts/lan_projectile_stream.gd")
const Flight=preload("res://scripts/bullet_flight_visual.gd")
var weapon={"id":"fixture","kind":"bullet","name":"fixture","presentation":{},"projectileSpeed":5600,"damage":10,"range":4000}
func resolve_weapon(_id: String,_key: String) -> Dictionary:return weapon
func _initialize():call_deferred("run")
func fixture(id: int,age: float,ended: bool=false) -> Dictionary:
	return {"id":id,"source":1,"weapon":weapon,"origin":Vector2.ZERO,"start_height":1.0,"position":Vector2(age*140,0),"height":1.0,"direction":Vector2.RIGHT,"slope":0.0,"age":age,"speed":140.0,"team":0,"alive":not ended}
func fail(message: String):printerr("PROJECTILE_CONTRACT ",message);quit(2)
func run():
	var sender=Stream.new();var receiver=Stream.new();receiver.session=self
	# A 5 m round starts and ends in 36 ms: no live round at either 100 ms snapshot.
	var short_round=fixture(1,5.0/140,true)
	sender.capture_finish(short_round,.05)
	var packets=sender.packets([], .06,{"id":1,"position":Vector2.ZERO})
	if packets.is_empty():fail("short round missing from independent stream");return
	for packet in packets:
		if var_to_bytes(packet).size()>1100:fail("oversized datagram");return
		receiver.accept(packet,1000000)
	var positions: Array=[]
	for frame in range(8):
		var presentations=receiver.sample(1000000+roundi(frame*1000000.0/75))
		if not presentations.is_empty():positions.append(float(Flight.head(presentations[0],1).x))
	if positions.size()<3 or absf(float(positions.back())-5.0)>.0001 or receiver.played_finishes!=1:fail("short path not continuously played to verified endpoint");return
	for index in range(1,positions.size()):
		if float(positions[index])<float(positions[index-1]) or float(positions[index])>5.0001:fail("short path backtracked or crossed endpoint");return
	# Five loss-tolerant terminal repeats must not create five new shots.
	for repeat_index in range(5):
		for packet in packets:receiver.accept(packet,1120000+repeat_index*33333)
		if not receiver.sample(1120000+repeat_index*33333).is_empty():fail("duplicate finish resurrected a shot");return
	print("LAN_SHORT_BULLET_OK baseline_10hz_visible=0 streamed=1 frames=",positions.size()," positions=",positions," finish_replays=",receiver.played_finishes)
	# Deterministic 30 Hz arrivals with jitter. Sample on the 75 Hz render clock.
	var arrivals: Array=[]
	for tick in range(16):
		var age=tick/30.0
		var arrival=2000000+roundi(age*1000000)+20000+([-8000,9000,0,5000,-4000][tick%5])
		arrivals.append({"at":arrival,"packet":{"type":"rounds","time":age,"rounds":[sender.record(fixture(2,age,tick==15),tick==15)]}})
	var cursor=0;var before=-1.0;var max_step=0.0;var samples=0
	for frame in range(55):
		var now=2000000+roundi(frame*1000000.0/75)
		while cursor<arrivals.size() and int(arrivals[cursor].at)<=now:
			receiver.accept(arrivals[cursor].packet,now);cursor+=1
		var presentations=receiver.sample(now)
		if presentations.is_empty():continue
		var head=float(Flight.head(presentations[0],1).x)
		if before>=0:
			if head<before-.0001:fail("jittered path moved backwards");return
			max_step=maxf(max_step,head-before)
		before=head;samples+=1
	if max_step>140.0/75+.002 or samples<30:fail("arrival jitter caused a jump larger than one render frame");return
	# Reordered old live packets cannot reopen a terminated round.
	receiver.accept(arrivals[2].packet,2800000)
	if not receiver.sample(2800000).is_empty():fail("stale live state reopened completed round");return
	print("LAN_BULLET_JITTER_OK samples=",samples," maximum_step_m=",max_step," frame_distance_m=",140.0/75," bounded_endpoint=true")
	for id in range(2,90):sender.capture_finish(fixture(id,.025,true),.1)
	for packet in sender.packets([], .15,{"id":1,"position":Vector2.ZERO}):
		if var_to_bytes(packet).size()>1100:fail("burst exceeded datagram budget");return
	print("LAN_BULLET_BURST_OK short_rounds=",sender.finishes.size()," all_datagrams_under_1100=true")
	quit()
