extends RefCounted
## Carry unchanged ENet datagrams through explicit IPv4 sockets on LAN.
var front: PacketPeerUDP
var back: PacketPeerUDP
var host=""
var port=0
var client_port=0
var sent=0
var received=0
var wire_received=0
var last_sender=""

func open(address: String,game_port: int) -> int:
	close();host=address;port=game_port
	front=PacketPeerUDP.new();back=PacketPeerUDP.new()
	var error=front.bind(0,"127.0.0.1",1024*1024)
	if error==OK:error=back.bind(0,"0.0.0.0",1024*1024)
	if error==OK:error=back.set_dest_address(host,port)
	if error!=OK:close()
	return error

func local_port() -> int:return front.get_local_port() if front!=null else 0

func pump():
	if front==null or back==null:return
	flush_outbound()
	for i in range(mini(256,back.get_available_packet_count())):
		var packet=back.get_packet()
		wire_received+=1;last_sender=back.get_packet_ip()+":"+str(back.get_packet_port())
		# A transparent UDP path may translate the reply's source port. Restore
		# the endpoint expected by ENet, while accepting only the chosen host IP.
		if back.get_packet_ip()!=host or client_port==0:continue
		front.set_dest_address("127.0.0.1",client_port)
		if front.put_packet(packet)==OK:received+=1

func flush_outbound():
	if front==null or back==null:return
	for i in range(mini(256,front.get_available_packet_count())):
		var packet=front.get_packet();var sender=front.get_packet_ip();var sender_port=front.get_packet_port()
		if sender!="127.0.0.1":continue
		if client_port==0:client_port=sender_port
		if sender_port!=client_port:continue
		if back.put_packet(packet)==OK:sent+=1

func close():
	if front!=null:front.close();front=null
	if back!=null:back.close();back=null
	client_port=0
