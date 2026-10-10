extends RefCounted
## Nonblocking, globally serialized transport to the already-running local Laya sidecar.
const TIMEOUT_MS=12000
const CONNECT_TIMEOUT_MS=5000
const GAP_MS=200
const RETRY_MS=30000
const MAX_AGE=10.0
const MAX_RESPONSE_BYTES=1048576
var world_ref: WeakRef
var endpoint="http://127.0.0.1:8765"
var pending=0
var _host="127.0.0.1"
var _port=8765
var _generation=0
var _sequence=0
var _queue: Array=[]
var _results: Array=[]
var _active: Dictionary={}
var _client
var _body=PackedByteArray()
var _sent=false
var _started_ms=0
var _next_ms=0
var _retry_ms=0
var _response_code=0
var _expected_bytes=-1
var _requests=0
var _responses=0
var _errors=0
var _last_error=""
var _configured=false

func configure(world,endpoint_override: String=""):
	cancel("reconfigured");world_ref=weakref(world)
	endpoint=endpoint_override if not endpoint_override.is_empty() else OS.get_environment("LAYA_AI_URL")
	if endpoint.is_empty():endpoint="http://127.0.0.1:8765"
	endpoint=endpoint.trim_suffix("/")
	var address=endpoint.trim_prefix("http://");var parts=address.split(":")
	_host=parts[0];_port=int(parts[1]) if parts.size()==2 and parts[1].is_valid_int() else 8765
	_configured=endpoint.begins_with("http://") and _host in ["127.0.0.1","localhost"] and parts.size()<=2 and _port>0 and _port<=65535 and not address.contains("/")
	_last_error="" if _configured else "invalid-local-endpoint"
	_retry_ms=0;_next_ms=0;_requests=0;_responses=0;_errors=0

func world():return world_ref.get_ref() if world_ref!=null else null

func running() -> bool:
	var current=world()
	return current!=null and current.campaign_active() and current.campaign.phase=="playing"

func is_busy(team: int) -> bool:
	if not _active.is_empty() and int(_active.team)==team:return true
	for entry in _queue:
		if int(entry.team)==team:return true
	return false

func submit(team: int,state: Dictionary,questions: Array,metadata: Dictionary={}) -> bool:
	_sequence+=1
	var current=world()
	var entry={"team":team,"state":state.duplicate(true),"questions":questions.duplicate(true),"metadata":metadata.duplicate(true),"request_id":_sequence,"observed_at":float(current.time) if current!=null else 0.0,"generation":_generation}
	var reason=""
	if not _configured:reason="invalid-local-endpoint"
	elif not running():reason="match-closed"
	elif team not in [0,1]:reason="invalid-team"
	elif is_busy(team):reason="team-already-pending"
	elif Time.get_ticks_msec()<_retry_ms:reason="transport-backoff"
	else:reason=validate_questions(questions)
	if not reason.is_empty():
		deliver(entry,{},reason,"bridge");return false
	_queue.append(entry);pending=_queue.size()+(0 if _active.is_empty() else 1)
	return true

static func validate_questions(questions: Array) -> String:
	if questions.is_empty() or questions.size()>32:return "invalid-question-count"
	var names={}
	for question in questions:
		if not question is Dictionary:return "invalid-question"
		var name=question.get("name","");var options=question.get("options",[])
		if not name is String or name.is_empty() or names.has(name):return "invalid-question-name"
		names[name]=true
		if not options is Array or options.size()<2 or options.size()>64:return "invalid-options"
		var seen={}
		for option in options:
			if not option is String or option.is_empty() or seen.has(option):return "invalid-options"
			seen[option]=true
	return ""

static func validate_answer(answer,options: Array,minimum: float=.3) -> Dictionary:
	var result={"accepted":false,"reason":"missing-answer","answer":{}}
	if options.size()<2:result.reason="invalid-options";return result
	if not answer is Dictionary:return result
	var choice=answer.get("choice",null)
	if not choice is String or choice not in options:result.reason="invalid-option";return result
	var probabilities=answer.get("probabilities",null)
	if not probabilities is Dictionary or probabilities.size()!=options.size():result.reason="invalid-probabilities";return result
	var total=0.0;var runner=0.0
	for option in options:
		var value=probabilities.get(option,null)
		if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0 or float(value)>1:result.reason="invalid-probabilities";return result
		total+=float(value)
		if option!=choice:runner=maxf(runner,float(value))
	if absf(total-1.0)>.025:result.reason="unnormalized-probabilities";return result
	var selected=float(probabilities[choice]);var count=float(options.size())
	var threshold=maxf(1.2/count,minimum*minf(1.0,4.0/count))
	result.reason="low-confidence-or-ambiguous"
	if selected<threshold or selected-runner<.1/count:return result
	result.accepted=true;result.reason="accepted"
	# Confidence belongs to the chosen option, never another candidate's maximum.
	result.answer={"choice":choice,"confidence":selected,"probabilities":probabilities.duplicate(true)}
	return result

func tick(_delta: float):
	if not running():
		if not _active.is_empty() or not _queue.is_empty():cancel("match-closed")
		return
	var now=Time.get_ticks_msec()
	if _active.is_empty():
		if _queue.is_empty() or now<_next_ms or now<_retry_ms:return
		_active=_queue.pop_front();pending=_queue.size()+1
		if stale(_active):finish({},"stale-observation","bridge");return
		_started_ms=now;_sent=false;_body=PackedByteArray();_response_code=0;_expected_bytes=-1
		_client=create_client();_client.blocking_mode_enabled=false
		var error=_client.connect_to_host(_host,_port)
		if error!=OK:transport_error("connect-error-"+str(error));return
	if _sent and now-int(_active.sent_at_ms)>=TIMEOUT_MS:transport_error("timeout");return
	if not _sent and now-_started_ms>=CONNECT_TIMEOUT_MS:transport_error("connect-timeout");return
	if int(_active.generation)!=_generation:finish({},"generation-changed","bridge");return
	var poll_error=_client.poll()
	if poll_error!=OK:
		if complete_closed_response():return
		transport_error("poll-error-"+str(poll_error));return
	var status=_client.get_status()
	if status in [HTTPClient.STATUS_CANT_RESOLVE,HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR,HTTPClient.STATUS_DISCONNECTED]:
		if complete_closed_response():return
		transport_error("connection-error-"+str(status));return
	if status==HTTPClient.STATUS_CONNECTED:
		if _sent:
			complete_response();return
		if stale(_active):finish({},"stale-observation","bridge");return
		var payload=JSON.stringify({"state":_active.state,"questions":_active.questions})
		if payload.to_utf8_buffer().size()>256*1024:finish({},"request-too-large","bridge");return
		var error=_client.request(HTTPClient.METHOD_POST,"/decision",["Content-Type: application/json"],payload)
		if error!=OK:transport_error("request-error-"+str(error));return
		_sent=true;_active.sent_at_ms=Time.get_ticks_msec();_requests+=1;emit_diagnostic(_active,"request",{},"","laya-request",{})
	elif status==HTTPClient.STATUS_BODY:
		_response_code=_client.get_response_code()
		_expected_bytes=_client.get_response_body_length()
		# Only consume currently available chunks; poll never blocks the simulation.
		for _chunk_index in range(8):
			var chunk: PackedByteArray=_client.read_response_body_chunk()
			if chunk.is_empty():break
			_body.append_array(chunk)
			if _body.size()>MAX_RESPONSE_BYTES:transport_error("response-too-large");return
			if _expected_bytes>=0 and _body.size()>=_expected_bytes:complete_response();return
		if _client.get_status()==HTTPClient.STATUS_CONNECTED:complete_response()

func create_client():return HTTPClient.new()

func complete_closed_response() -> bool:
	if not _sent or _response_code==0 or _body.is_empty():return false
	if _expected_bytes>=0 and _body.size()<_expected_bytes:return false
	# EOF can finish HTTP/1.0 or chunked responses; JSON/schema still must validate.
	complete_response();return true

func stale(entry: Dictionary) -> bool:
	var current=world()
	return current==null or int(entry.generation)!=_generation or float(current.time)-float(entry.observed_at)>MAX_AGE or float(current.time)<float(entry.observed_at)

func complete_response():
	if _response_code==0:_response_code=_client.get_response_code()
	if _response_code!=200:transport_error("http-"+str(_response_code));return
	var parser=JSON.new()
	if parser.parse(_body.get_string_from_utf8())!=OK:transport_error("invalid-json");return
	var parsed=parser.data
	if not parsed is Dictionary or not parsed.get("answers",null) is Dictionary:transport_error("invalid-response");return
	_responses+=1;_last_error=""
	if stale(_active):finish(parsed,"stale-observation","laya");return
	finish(parsed,"","laya")

func transport_error(reason: String):
	_errors+=1;_last_error=reason;_retry_ms=Time.get_ticks_msec()+RETRY_MS
	finish({},reason,"transport")
	# A queued team must receive completion too, so its director never waits forever.
	for entry in _queue:deliver(entry,{},"transport-backoff","bridge")
	_queue.clear();pending=0

func finish(raw: Dictionary,reason: String,source: String):
	var entry=_active
	if _client!=null:_client.close()
	_client=null;_active={};_body=PackedByteArray();_next_ms=Time.get_ticks_msec()+GAP_MS
	pending=_queue.size()
	if not entry.is_empty():deliver(entry,raw,reason,source)

func deliver(entry: Dictionary,raw: Dictionary,reason: String,source: String):
	var current=world();var received=float(current.time) if current!=null else float(entry.observed_at)
	var accepted={};var rejected={};var choices={}
	for question in entry.questions:
		if not question is Dictionary or not question.get("name",null) is String:continue
		var name: String=question.name
		var answer=raw.get("answers",{}).get(name,null)
		var checked=validate_answer(answer,question.get("options",[])) if reason.is_empty() else {"accepted":false,"reason":reason,"answer":{}}
		choices[name]={"choice":answer.get("choice",null) if answer is Dictionary else null,"accepted":checked.accepted,"reason":checked.reason}
		if checked.accepted:accepted[name]=checked.answer
		else:rejected[name]=checked.reason
	var packet={"team":int(entry.team),"metadata":entry.metadata.duplicate(true),"accepted":accepted,"raw":raw,"request_id":int(entry.request_id),"source":source,"observed_at":float(entry.observed_at),"received_at":received,"rejected":rejected,"reason":reason,"error":reason if source=="transport" else ""}
	_results.append(packet)
	var phase="error" if source=="transport" else "result" if reason.is_empty() and not accepted.is_empty() else "rejected"
	emit_diagnostic(entry,phase,raw,reason if not reason.is_empty() else "accepted" if not accepted.is_empty() else "no-accepted-answer",source,choices)

func emit_diagnostic(entry: Dictionary,phase: String,raw: Dictionary,reason: String,source: String,choices: Dictionary):
	var current=world()
	if current==null:return
	current.event.emit({"type":"ai_decision","phase":phase,"team":int(entry.team),"request_id":int(entry.request_id),"observed_at":float(entry.observed_at),"received_at":float(current.time),"source":source,"latency_ms":maxi(0,Time.get_ticks_msec()-int(entry.sent_at_ms)) if entry.has("sent_at_ms") else 0,"runtime":raw.get("runtime",{}),"contextUsage":raw.get("contextUsage",{}),"modelContext":raw.get("modelContext",null),"raw_answers":raw.get("answers",{}),"input":entry.state if phase=="request" else {},"questions":entry.questions if phase=="request" else [],"choices":choices,"reason":reason,"metadata":entry.metadata.duplicate(true)})

func drain_results() -> Array:
	var result=_results;_results=[];return result

func cancel(_reason: String="cancelled"):
	_generation+=1
	if _client!=null:_client.close()
	_client=null;_active={};_queue.clear();_results.clear();_body=PackedByteArray();pending=0;_sent=false

func diagnostics() -> Dictionary:
	return {"endpoint":endpoint,"configured":_configured,"generation":_generation,"requests":_requests,"responses":_responses,"errors":_errors,"pending":pending,"busy":not _active.is_empty(),"queued":_queue.size(),"last_error":_last_error,"retry_wait_ms":maxi(0,_retry_ms-Time.get_ticks_msec())}
