extends SceneTree
func _initialize():call_deferred("run")
func run():
	var server=PacketPeerUDP.new();var reply=PacketPeerUDP.new();var client=PacketPeerUDP.new()
	if server.bind(0,"127.0.0.1")!=OK or reply.bind(0,"127.0.0.1")!=OK or client.bind(0,"127.0.0.1")!=OK:quit(2);return
	var bridge=load("res://scripts/lan_ipv4_transport.gd").new()
	if bridge.open("127.0.0.1",server.get_local_port())!=OK:quit(2);return
	client.set_dest_address("127.0.0.1",bridge.local_port());client.put_packet("request".to_utf8_buffer())
	var until=Time.get_ticks_msec()+1000
	while server.get_available_packet_count()==0 and Time.get_ticks_msec()<until:
		bridge.pump();await create_timer(.002).timeout
	if server.get_available_packet_count()==0:printerr("IPV4 no outbound packet");quit(2);return
	var request=server.get_packet();var back_ip=server.get_packet_ip();var back_port=server.get_packet_port()
	if request.get_string_from_utf8()!="request":quit(2);return
	reply.set_dest_address(back_ip,back_port);reply.put_packet("reply".to_utf8_buffer())
	until=Time.get_ticks_msec()+1000
	while client.get_available_packet_count()==0 and Time.get_ticks_msec()<until:
		bridge.pump();await create_timer(.002).timeout
	if client.get_available_packet_count()==0:printerr("IPV4 translated source port discarded");quit(2);return
	var answer=client.get_packet()
	if answer.get_string_from_utf8()!="reply" or client.get_packet_port()!=bridge.local_port():printerr("IPV4 endpoint not normalized");quit(2);return
	var front_port=bridge.local_port();bridge.close()
	var released=PacketPeerUDP.new()
	if released.bind(front_port,"127.0.0.1")!=OK:printerr("IPV4 leaked socket");quit(2);return
	released.close();server.close();reply.close();client.close()
	print("LAN_IPV4_CONTRACT_OK translated_reply=true normalized_endpoint=true sockets_released=true")
	quit()
