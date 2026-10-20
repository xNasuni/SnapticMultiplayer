extends RefCounted

const DELAY := 0.1
const KEEP := 32
const TELEPORT := 20.0
const MAX_LAG := 0.4
const CATCH_UP := 2.0
const MAX_SPEEDUP := 0.5

var _times: Array[float] = []
var _poses: Array = []
var _clock := 0.0


func push(time: float, pose) -> void:
	if not _times.is_empty():
		var last = _poses.back()

		if time <= _times.back():
			return

		if pose.mode == last.mode and pose.position.distance_to(last.position) > TELEPORT:
			_times.clear()
			_poses.clear()

	if _times.is_empty():
		_clock = time - DELAY

	_times.append(time)
	_poses.append(pose)

	if _times.size() > KEEP:
		_times.pop_front()
		_poses.pop_front()


func drained() -> bool:
	return _times.is_empty() or _clock >= _times.back()

func ends_with(event: int) -> bool:
	return not _poses.is_empty() and _poses.back().events & event != 0


func sample(delta: float):
	if _times.is_empty():
		return null

	var newest: float = _times.back()
	var lag := newest - _clock

	if lag > MAX_LAG:
		_clock = newest - DELAY
		lag = DELAY

	var speed := 1.0 + clampf((lag - DELAY) * CATCH_UP, -MAX_SPEEDUP, MAX_SPEEDUP)
	_clock = minf(_clock + delta * speed, newest)

	if _clock <= _times[0]:
		return _poses[0].copy()

	for i in range(1, _times.size()):
		if _times[i] < _clock:
			continue

		var from = _poses[i - 1]
		var to = _poses[i]
		var span := _times[i] - _times[i - 1]
		var pose = from.mixed(to, (_clock - _times[i - 1]) / span)

		pose.velocity = Vector3.ZERO

		if from.mode == to.mode:
			pose.velocity = (to.position - from.position) / span

		return pose

	var held = _poses.back().copy()
	held.velocity = Vector3.ZERO

	return held
