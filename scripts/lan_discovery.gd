extends Node
## Small, bounded UDP room discovery. Gameplay still uses ENet on PORT 27829.
const DISCOVERY_PORT=27830
const MAGIC="little-battlefield-room-v1"
const QUERY_INTERVAL=2.5
const ROOM_TTL_MS=7500
const MAX_PACKETS_PER_FRAME=16
const KNOWN_HOSTS_FILE="user://lan-known-hosts.txt"
signal rooms_changed(rooms: Array)
signal scan_failed(reason: String)
var session
var host_id="%d-%d-%d"%[Time.get_ticks_usec(),OS.get_process_id(),randi()]
var host_socket: PacketPeerUDP
var scan_socket: PacketPeerUDP
var interface_sockets: Dictionary={}
var rooms: Dictionary={}
var query_clock=0.0
var scan_age=0.0
var empty_notified=false
var known_hosts=PackedStringArray()

func setup(owner):
	session=owner
	load_known_hosts()

func load_known_hosts():
	# The portable Windows package keeps the last address next to the EXE.
	var package_file=OS.get_executable_path().get_base_dir().path_join("host-address.txt")
	for path in [package_file,KNOWN_HOSTS_FILE]:
		if not FileAccess.file_exists(path):continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			remember_host(line,false)

func remember_host(raw_address: String,persist: bool=true) -> bool:
	var address=raw_address.strip_edges().get_slice(":",0)
	var octets=address.split(".")
	if octets.size()!=4:return false
	for octet in octets:
		if not octet.is_valid_int() or int(octet)<0 or int(octet)>255:return false
	if known_hosts.has(address):
		if not persist:return true
		known_hosts.remove_at(known_hosts.find(address))
	known_hosts.append(address)
	if known_hosts.size()>16:known_hosts.remove_at(0)
	if persist:
		var file=FileAccess.open(KNOWN_HOSTS_FILE,FileAccess.WRITE)
		if file!=null:file.store_string("\n".join(known_hosts)+"\n")
	return true

func start_host() -> bool:
	if host_socket!=null:return true
	var socket=PacketPeerUDP.new()
	if socket.bind(DISCOVERY_PORT,"0.0.0.0")!=OK:return false
	host_socket=socket
	return true

func stop_host():
	if host_socket!=null:host_socket.close();host_socket=null
	rooms.clear();rooms_changed.emit([])

func start_scan() -> bool:
	if scan_socket!=null:
		request_scan();return true
	var socket=PacketPeerUDP.new()
	if socket.bind(0,"0.0.0.0")!=OK:
		scan_failed.emit("无法开启局域网搜索；仍可输入房主 IP 加入")
		return false
	socket.set_broadcast_enabled(true)
	scan_socket=socket
	for address in local_private_addresses():
		var interface_socket=PacketPeerUDP.new()
		if interface_socket.bind(0,address)!=OK:continue
		interface_socket.set_broadcast_enabled(true)
		interface_sockets[address]=interface_socket
	query_clock=0.0
	scan_age=0.0;empty_notified=false
	request_scan()
	return true

func stop_scan():
	if scan_socket!=null:scan_socket.close();scan_socket=null
	for socket in interface_sockets.values():socket.close()
	interface_sockets.clear()
	rooms.clear();rooms_changed.emit([])
	scan_age=0.0;empty_notified=false

func refresh_scan():
	if scan_socket==null:
		start_scan()
		return
	scan_age=0.0;empty_notified=false
	request_scan()

func local_private_addresses() -> PackedStringArray:
	var addresses=PackedStringArray()
	for address in IP.get_local_addresses():
		var octets=address.split(".")
		if octets.size()!=4:continue
		var numbers=[]
		var valid=true
		for octet in octets:
			if not octet.is_valid_int():valid=false;break
			var number=int(octet)
			if number<0 or number>255:valid=false;break
			numbers.append(number)
		if not valid:continue
		var private_address=numbers[0]==10 or numbers[0]==192 and numbers[1]==168 or numbers[0]==172 and numbers[1]>=16 and numbers[1]<=31 or numbers[0]==100 and numbers[1]>=64 and numbers[1]<=127
		if not private_address:continue
		if not addresses.has(address):addresses.append(address)
	return addresses

func broadcast_targets() -> PackedStringArray:
	var targets=PackedStringArray()
	# Godot does not expose adapter netmasks. The interface-bound limited
	# broadcast reaches the real subnet; /24 destinations cover common LANs.
	for address in local_private_addresses():
		var octets=address.split(".")
		var broadcast="%s.%s.%s.255"%[octets[0],octets[1],octets[2]]
		if not targets.has(broadcast):targets.append(broadcast)
	targets.append("255.255.255.255")
	targets.append("127.0.0.1")
	return targets

func request_scan():
	if scan_socket==null:return
	var packet=JSON.stringify({"magic":MAGIC,"kind":"query"}).to_utf8_buffer()
	var remote_sent=0
	for destination in ["255.255.255.255","127.0.0.1"]:
		if scan_socket.set_dest_address(destination,DISCOVERY_PORT)!=OK:continue
		if scan_socket.put_packet(packet)==OK and destination!="127.0.0.1":remote_sent+=1
	for address in interface_sockets:
		var interface_socket: PacketPeerUDP=interface_sockets[address]
		var octets=str(address).split(".")
		for destination in ["255.255.255.255","%s.%s.%s.255"%[octets[0],octets[1],octets[2]]]:
			if interface_socket.set_dest_address(destination,DISCOVERY_PORT)!=OK:continue
			if interface_socket.put_packet(packet)==OK:remote_sent+=1
	# Routed networks do not carry LAN broadcasts. Probe previously entered
	# hosts directly so their replies still populate the same room list.
	for address in known_hosts:
		if scan_socket.set_dest_address(address,DISCOVERY_PORT)!=OK:continue
		if scan_socket.put_packet(packet)==OK:remote_sent+=1
	if remote_sent==0:scan_failed.emit("局域网搜索广播发送失败；请检查网络连接，或输入房主 IP")
	query_clock=QUERY_INTERVAL

func _process(delta: float):
	if host_socket!=null:
		for index in range(mini(host_socket.get_available_packet_count(),MAX_PACKETS_PER_FRAME)):
			var data=host_socket.get_packet()
			var sender=host_socket.get_packet_ip()
			var sender_port=host_socket.get_packet_port()
			if data.size()>256:continue
			var request=JSON.parse_string(data.get_string_from_utf8())
			if not request is Dictionary or request.get("magic","")!=MAGIC or request.get("kind","")!="query":continue
			var reply={"magic":MAGIC,"kind":"room","id":host_id,"version":session.game.BUILD_VERSION,"name":"石墙果园 · 第一关","port":session.PORT,"players":session.peer_units.size()+1,"capacity":6}
			if host_socket.set_dest_address(sender,sender_port)==OK:host_socket.put_packet(JSON.stringify(reply).to_utf8_buffer())
	if scan_socket==null:return
	scan_age+=delta
	var sockets: Array=[scan_socket]
	sockets.append_array(interface_sockets.values())
	for active_socket in sockets:
		for index in range(mini(active_socket.get_available_packet_count(),MAX_PACKETS_PER_FRAME)):
			var data=active_socket.get_packet()
			var sender=active_socket.get_packet_ip()
			if data.size()>512 or sender.contains(":"):continue
			var reply=JSON.parse_string(data.get_string_from_utf8())
			if not reply is Dictionary or reply.get("magic","")!=MAGIC or reply.get("kind","")!="room":continue
			var port=int(reply.get("port",0))
			if port<1 or port>65535:continue
			var endpoint="%s:%d"%[sender,port]
			var room_id=str(reply.get("id",endpoint)).substr(0,80)
			if room_id.is_empty():room_id=endpoint
			if rooms.has(room_id) and sender=="127.0.0.1" and not str(rooms[room_id].endpoint).begins_with("127."):
				rooms[room_id].seen_ms=Time.get_ticks_msec()
				continue
			var entry={"endpoint":endpoint,"name":str(reply.get("name","局域网战役")).substr(0,40),"version":str(reply.get("version","")).substr(0,40),"players":clampi(int(reply.get("players",1)),1,6),"capacity":clampi(int(reply.get("capacity",6)),1,6),"seen_ms":Time.get_ticks_msec()}
			var changed=not rooms.has(room_id) or room_signature(rooms[room_id])!=room_signature(entry)
			rooms[room_id]=entry
			if changed:rooms_changed.emit(room_list())
	query_clock-=delta
	if query_clock<=0:request_scan()
	var expired=false
	for room_id in rooms.keys():
		if Time.get_ticks_msec()-int(rooms[room_id].seen_ms)>ROOM_TTL_MS:
			rooms.erase(room_id);expired=true
	if expired:rooms_changed.emit(room_list())
	if rooms.is_empty() and scan_age>=3.0 and not empty_notified:
		empty_notified=true
		rooms_changed.emit([])

func room_signature(room: Dictionary) -> String:
	return "%s|%s|%s|%s|%s"%[room.endpoint,room.name,room.version,room.players,room.capacity]

func room_list() -> Array:
	var entries=rooms.values()
	entries.sort_custom(func(a,b):return str(a.endpoint)<str(b.endpoint))
	return entries

func _exit_tree():
	if host_socket!=null:host_socket.close()
	if scan_socket!=null:scan_socket.close()
	for socket in interface_sockets.values():socket.close()
