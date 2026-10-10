extends SceneTree
var peer=ENetMultiplayerPeer.new()
func _initialize():call_deferred("run")
func run():
	var host="192.168.23.181";var port=27829
	var bind_ip="";var local_port=0
	var bridge=null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-address="):
			var value=arg.trim_prefix("--probe-address=");host=value.get_slice(":",0)
			if value.contains(":"):port=int(value.get_slice(":",1))
		if arg.begins_with("--bind-ip="):bind_ip=arg.trim_prefix("--bind-ip=");local_port=randi_range(49152,60000)
	if "--native-ipv4" in OS.get_cmdline_user_args():
		bridge=load("res://scripts/lan_ipv4_transport.gd").new()
		if bridge.open(host,port)!=OK:printerr("TRANSPORT_BRIDGE_FAILED");quit(2);return
		host="127.0.0.1";port=bridge.local_port()
	if not bind_ip.is_empty():peer.set_bind_ip(bind_ip)
	var error=peer.create_client(host,port,0,0,0,local_port)
	print("TRANSPORT_PROBE_START error=",error," address=",host,":",port)
	var until=Time.get_ticks_msec()+9000
	while Time.get_ticks_msec()<until:
		if bridge!=null:bridge.pump()
		peer.poll()
		if peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED:
			print("TRANSPORT_PROBE_CONNECTED");peer.close()
			if bridge!=null:bridge.flush_outbound();bridge.close()
			quit();return
		await create_timer(.02).timeout
	print("TRANSPORT_PROBE_NO_RESPONSE status=",peer.get_connection_status())
	if bridge!=null:print("BRIDGE sent=",bridge.sent," received=",bridge.received," wire=",bridge.wire_received," sender=",bridge.last_sender)
	peer.close();quit(2)
