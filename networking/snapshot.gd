extends RefCounted

const Pose := preload("pose.gd")

const PROTOCOL := 1
const POSE := 43
const TIME := 4
const STATE := TIME + POSE
const ENTRY := 4 + STATE
const HEADER := 1

const SPIN := 32767.0
const UNIT := 127.0
const MAX_HIT := 2.0
const MAX_TWIRL := 60.0

const MODE := 0b011
const MOVING := 0b100
const GROUNDED := 0b1000
const MAGNETIC := 0b10000
const AFTERIMAGE := 0b100000


static func pack_state(time: int, pose) -> PackedByteArray:
	var bytes := PackedByteArray()

	bytes.resize(STATE)
	bytes.encode_u32(0, time)
	put_pose(bytes, TIME, pose)

	return bytes


static func unpack_state(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() != STATE:
		return {}

	return {"time": bytes.decode_u32(0), "pose": get_pose(bytes, TIME)}


static func pack_world(states: Dictionary) -> PackedByteArray:
	var bytes := PackedByteArray()
	var at := HEADER

	bytes.resize(HEADER + ENTRY * states.size())
	bytes.encode_u8(0, states.size())

	for id in states:
		bytes.encode_u32(at, id)
		bytes.encode_u32(at + 4, states[id].time)
		put_pose(bytes, at + 8, states[id].pose)
		at += ENTRY

	return bytes


static func unpack_world(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER:
		return {}

	var count := bytes.decode_u8(0)
	var states := {}
	var at := HEADER

	if bytes.size() != HEADER + ENTRY * count:
		return {}

	for i in count:
		states[bytes.decode_u32(at)] = {
			"time": bytes.decode_u32(at + 4),
			"pose": get_pose(bytes, at + 8),
		}
		at += ENTRY

	return states


static func put_pose(bytes: PackedByteArray, at: int, pose) -> void:
	var flags: int = pose.mode
	var spin: Quaternion = pose.spin

	if pose.moving:
		flags |= MOVING
	if pose.grounded:
		flags |= GROUNDED
	if pose.magnetic:
		flags |= MAGNETIC
	if pose.afterimage:
		flags |= AFTERIMAGE

	bytes.encode_float(at, pose.position.x)
	bytes.encode_float(at + 4, pose.position.y)
	bytes.encode_float(at + 8, pose.position.z)
	bytes.encode_float(at + 12, pose.yaw)
	bytes.encode_u8(at + 16, flags)

	bytes.encode_s16(at + 17, roundi(spin.x * SPIN))
	bytes.encode_s16(at + 19, roundi(spin.y * SPIN))
	bytes.encode_s16(at + 21, roundi(spin.z * SPIN))
	bytes.encode_s16(at + 23, roundi(spin.w * SPIN))

	bytes.encode_u8(at + 25, to_byte(pose.running, 1.0))
	bytes.encode_u8(at + 26, to_byte(pose.wall_slide, 1.0))
	bytes.encode_u8(at + 27, to_byte(pose.bhop_wind, 1.0))
	bytes.encode_u8(at + 28, to_byte(pose.skid, 1.0))

	bytes.encode_u8(at + 29, pose.jumps & 0xFF)
	bytes.encode_u8(at + 30, pose.landings & 0xFF)
	bytes.encode_u8(at + 31, pose.hits & 0xFF)
	bytes.encode_u8(at + 32, pose.trails & 0xFF)

	put_unit(bytes, at + 33, pose.hit_normal)
	bytes.encode_u8(at + 36, to_byte(pose.hit_strength, MAX_HIT))
	put_unit(bytes, at + 37, pose.up)
	put_unit(bytes, at + 40, pose.twirl / MAX_TWIRL)


static func get_pose(bytes: PackedByteArray, at: int):
	var pose = Pose.new()
	var flags := bytes.decode_u8(at + 16)

	var spin := Quaternion(
		bytes.decode_s16(at + 17) / SPIN,
		bytes.decode_s16(at + 19) / SPIN,
		bytes.decode_s16(at + 21) / SPIN,
		bytes.decode_s16(at + 23) / SPIN,
	)

	var normal := get_unit(bytes, at + 33)
	var up := get_unit(bytes, at + 37)

	pose.position = Vector3(
		bytes.decode_float(at),
		bytes.decode_float(at + 4),
		bytes.decode_float(at + 8),
	)
	pose.yaw = bytes.decode_float(at + 12)

	pose.mode = clampi(flags & MODE, Pose.Mode.BODY, Pose.Mode.RAGDOLL)
	pose.moving = flags & MOVING != 0
	pose.grounded = flags & GROUNDED != 0
	pose.magnetic = flags & MAGNETIC != 0
	pose.afterimage = flags & AFTERIMAGE != 0

	pose.spin = spin.normalized() if spin.length_squared() > 0.0 else Quaternion.IDENTITY

	pose.running = from_byte(bytes.decode_u8(at + 25), 1.0)
	pose.wall_slide = from_byte(bytes.decode_u8(at + 26), 1.0)
	pose.bhop_wind = from_byte(bytes.decode_u8(at + 27), 1.0)
	pose.skid = from_byte(bytes.decode_u8(at + 28), 1.0)

	pose.jumps = bytes.decode_u8(at + 29)
	pose.landings = bytes.decode_u8(at + 30)
	pose.hits = bytes.decode_u8(at + 31)
	pose.trails = bytes.decode_u8(at + 32)

	pose.hit_normal = normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	pose.hit_strength = from_byte(bytes.decode_u8(at + 36), MAX_HIT)
	pose.up = up.normalized() if up.length_squared() > 0.0 else Vector3.UP
	pose.twirl = get_unit(bytes, at + 40) * MAX_TWIRL

	return pose


static func put_unit(bytes: PackedByteArray, at: int, value: Vector3) -> void:
	bytes.encode_s8(at, roundi(clampf(value.x, -1.0, 1.0) * UNIT))
	bytes.encode_s8(at + 1, roundi(clampf(value.y, -1.0, 1.0) * UNIT))
	bytes.encode_s8(at + 2, roundi(clampf(value.z, -1.0, 1.0) * UNIT))


static func get_unit(bytes: PackedByteArray, at: int) -> Vector3:
	return Vector3(
		bytes.decode_s8(at),
		bytes.decode_s8(at + 1),
		bytes.decode_s8(at + 2),
	) / UNIT


static func to_byte(value: float, limit: float) -> int:
	return roundi(clampf(value / limit, 0.0, 1.0) * 255.0)


static func from_byte(value: int, limit: float) -> float:
	return value / 255.0 * limit
