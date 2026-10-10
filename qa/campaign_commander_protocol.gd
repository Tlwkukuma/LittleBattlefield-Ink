extends SceneTree
## Pure HTTP mock and protocol fixtures. No sockets, model requests or battle steps.
const Bridge=preload("res://scripts/campaign_commander.gd")
class WorldFixture extends RefCounted:
	signal event(data: Dictionary)
	var time=0.0
	var campaign={"phase":"playing"}
	func campaign_active():return true
class ClientFixture extends RefCounted:
	var blocking_mode_enabled=false
	var status=HTTPClient.STATUS_CONNECTED
	var body=PackedByteArray()
	var delivered=false
	var closed=false
	var requests=0
	var response_code=200
	var declared_length=-2
	func connect_to_host(_host,_port):return OK
	func poll():
		if status==HTTPClient.STATUS_REQUESTING:status=HTTPClient.STATUS_BODY
		return OK
	func get_status():return status
	func request(_method,_path,_headers,_payload):requests+=1;status=HTTPClient.STATUS_REQUESTING;return OK
	func get_response_code():return response_code
	func get_response_body_length():return body.size() if declared_length==-2 else declared_length
	func read_response_body_chunk():
		if delivered:return PackedByteArray()
		delivered=true;status=HTTPClient.STATUS_DISCONNECTED
		return body
	func close():closed=true;status=HTTPClient.STATUS_DISCONNECTED
class BridgeFixture extends "res://scripts/campaign_commander.gd":
	var clients: Array=[]
	var declared_length=-2
	var connection_status=HTTPClient.STATUS_CONNECTED
	var body_override=""
	var response={"answers":{"mission":{"choice":"attack:0","confidence":.99,"probabilities":{"attack:0":.8,"hold:0":.2}}},"runtime":{"device":"mock","model":"protocol-fixture"},"contextUsage":{"stateTokens":10}}
	func create_client():
		var client=ClientFixture.new();client.body=(JSON.stringify(response) if body_override.is_empty() else body_override).to_utf8_buffer();client.declared_length=declared_length;client.status=connection_status;clients.append(client);return client
var count=0
var failures=[]
var options=["attack:0","hold:0"]
func check(value: bool,label: String):
	count+=1
	if not value:failures.append(label);push_error(label)
func question():return [{"name":"mission","options":options,"description":"fixture"}]
func _initialize():
	var good={"choice":"attack:0","confidence":.99,"probabilities":{"attack:0":.8,"hold:0":.2}}
	var checked=Bridge.validate_answer(good,options)
	check(checked.accepted and checked.answer.confidence==.8,"Confidence is the selected option probability")
	check(not Bridge.validate_answer({"choice":"attack:0","confidence":.99,"probabilities":{"attack:0":.1,"hold:0":.9}},options).accepted,"Another candidate's confidence never validates this choice")
	check(not Bridge.validate_answer({"choice":"attack:0","probabilities":{"attack:0":.5,"hold:0":.5}},options).accepted,"Uniform probability is rejected")
	check(not Bridge.validate_answer({"choice":"teleport","probabilities":{"attack:0":.8,"hold:0":.2}},options).accepted,"Out-of-vocabulary command is rejected")
	check(not Bridge.validate_answer({"choice":"attack:0","confidence":1},options).accepted,"Missing probabilities cannot invent a ranking")
	check(not Bridge.validate_answer({"choice":"attack:0","probabilities":{"attack:0":1.1,"hold:0":-.1}},options).accepted,"Out-of-range probabilities are rejected")
	check(not Bridge.validate_answer({"choice":"attack:0","probabilities":{"attack:0":.8,"hold:0":.1}},options).accepted,"Unnormalized probabilities are rejected")
	check(not Bridge.validate_answer({"choice":"attack:0","probabilities":{"attack:0":.8,"hold:0":.2,"extra":0}},options).accepted,"Candidate probability keys must match exactly")
	check(not Bridge.validate_questions(question()).length() and not Bridge.validate_questions([{"name":"x","options":["x","x"]}]).is_empty(),"Question vocabulary is nonempty and unique")
	var world=WorldFixture.new();var bridge=BridgeFixture.new();bridge.configure(world)
	var events=[];world.event.connect(func(e):events.append(e))
	check(bridge.submit(0,{"briefing":["fixture"]},question(),{"phase":"policy"}) and bridge.submit(1,{},question(),{"phase":"mission"}),"Both teams may enter the serialized queue")
	check(bridge.pending==2 and bridge.is_busy(0) and bridge.is_busy(1),"Queue includes one pending request per team")
	check(not bridge.submit(0,{},question(),{"phase":"duplicate"}),"Duplicate team request is rejected")
	var rejected=bridge.drain_results();check(rejected.size()==1 and rejected[0].reason=="team-already-pending" and rejected[0].accepted.is_empty(),"Submission rejection returns completion to the director")
	bridge.tick(0);check(bridge.clients.size()==1 and bridge.clients[0].requests==1,"Only the first global request sends")
	bridge.tick(0)
	var results=bridge.drain_results()
	check(results.size()==1 and results[0].source=="laya" and results[0].accepted.mission.choice=="attack:0" and results[0].metadata.phase=="policy","Mock reply validates and retains metadata")
	check(bridge.clients[0].closed and bridge.pending==1,"HTTP/1.0 close after complete body still completes and releases connection")
	bridge.tick(0);check(bridge.clients.size()==1,"Serial gap prevents immediate next request")
	bridge._next_ms=0;bridge.tick(0);bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and results[0].team==1 and bridge.pending==0,"Second team runs only after first completion and gap")
	check(events.filter(func(e):return e.phase=="request").size()==2 and events.filter(func(e):return e.phase=="result").size()==2,"Diagnostics distinguish actual mock sends and accepted replies")
	bridge.configure(world);bridge.submit(0,{},question(),{"phase":"stale-queued"});world.time=11;bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and results[0].reason=="stale-observation" and bridge.diagnostics().requests==0,"Queued observation expires before any HTTP request")
	bridge.configure(world);bridge.submit(0,{},question(),{});bridge.tick(0);world.time+=11;bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and results[0].accepted.is_empty() and results[0].reason=="stale-observation" and results[0].raw.has("runtime"),"Late model response is logged but not applied")
	bridge.configure(world);bridge.submit(0,{},question(),{});bridge.submit(1,{},question(),{});bridge.tick(0);bridge._active.sent_at_ms-=Bridge.TIMEOUT_MS+1;bridge.tick(0)
	results=bridge.drain_results();check(results.size()==2 and results[0].reason=="timeout" and results[1].reason=="transport-backoff" and bridge.pending==0,"Timeout completes active and queued directors without blocking")
	check(not bridge.submit(0,{},question(),{}) and bridge.drain_results()[0].reason=="transport-backoff","Transport failures back off rather than hammering the service")
	bridge.configure(world);bridge.declared_length=-1;bridge.submit(0,{},question(),{});bridge.tick(0);bridge.tick(0);bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and not results[0].accepted.is_empty(),"Unknown-length HTTP response completes on EOF")
	bridge.configure(world);bridge.declared_length=999999;bridge.submit(0,{},question(),{});bridge.tick(0);bridge.tick(0);bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and results[0].accepted.is_empty() and results[0].source=="transport","Truncated declared body is never accepted")
	bridge.configure(world);bridge.declared_length=-2;bridge.body_override="{invalid";bridge.submit(0,{},question(),{});bridge.tick(0);bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and results[0].reason=="invalid-json","Malformed model JSON produces explicit transport completion")
	bridge.configure(world);bridge.body_override="";bridge.connection_status=HTTPClient.STATUS_CONNECTING;bridge.submit(0,{},question(),{});bridge.tick(0);bridge._started_ms-=Bridge.CONNECT_TIMEOUT_MS+1;bridge.tick(0)
	results=bridge.drain_results();check(results.size()==1 and results[0].reason=="connect-timeout" and bridge.diagnostics().requests==0,"Connection timeout is separate from the POST inference timeout")
	bridge.connection_status=HTTPClient.STATUS_CONNECTED
	bridge.configure(world);bridge.submit(0,{},question(),{});bridge.tick(0);var generation=bridge.diagnostics().generation
	bridge.cancel();check(bridge.pending==0 and bridge.drain_results().is_empty() and bridge.diagnostics().generation>generation and bridge.clients.back().closed,"Cancel closes transport, invalidates generation and clears results")
	bridge.configure(world);bridge.submit(0,{},question(),{});world.campaign.phase="won";bridge.tick(0)
	check(bridge.pending==0 and bridge.drain_results().is_empty(),"Terminal campaign cancels pending work")
	print("CAMPAIGN_COMMANDER_PROTOCOL ",count-failures.size(),"/",count," passed; failures=",failures)
	quit(0 if failures.is_empty() else 1)
