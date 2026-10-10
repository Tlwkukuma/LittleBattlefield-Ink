extends RefCounted
## Presentation rate uses monotonic wall time, never clamped/scaled game delta.
var window_start_usec: int=-1
var frames: int=0
var value: int=0
func sample(now_usec: int) -> int:
	if window_start_usec<0 or now_usec<window_start_usec:
		window_start_usec=now_usec;frames=0;return value
	frames+=1
	var elapsed=now_usec-window_start_usec
	if elapsed>=500000:
		value=roundi(float(frames)*1000000.0/float(elapsed))
		window_start_usec=now_usec;frames=0
	return value
