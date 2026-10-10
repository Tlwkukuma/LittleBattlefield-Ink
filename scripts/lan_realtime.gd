extends Node
## Independent datagrams: unrelated entity chunks must not discard each other.
var session

@rpc("authority","call_remote","unreliable",1)
func frame(packet: Dictionary):
	if session.is_client():session.receive_realtime(packet)

@rpc("any_peer","call_remote","unreliable_ordered",2)
func control(packet: Dictionary):
	if session.is_host():session.accept_control(multiplayer.get_remote_sender_id(),packet)
