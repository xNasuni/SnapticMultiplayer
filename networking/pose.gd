extends RefCounted

enum Mode { BODY, MARBLE, RAGDOLL }

const MOVED := 0.02
const TURNED := 0.03
const STEP := 0.04

var mode := Mode.BODY
var position := Vector3.ZERO
var velocity := Vector3.ZERO
var up := Vector3.UP
var spin := Quaternion.IDENTITY
var yaw := 0.0
var moving := false
var grounded := true

var running := 0.0
var wall_slide := 0.0
var bhop_wind := 0.0
var skid := 0.0
var twirl := Vector3.ZERO
var magnetic := false
var afterimage := false
var marble_trail := false

var jumps := 0
var landings := 0
var hits := 0
var trails := 0
var hit_normal := Vector3.UP
var hit_strength := 0.0
var bumps := 0
var magnets := 0
var clangs := 0
var bump_strength := 0.0


func differs(other) -> bool:
	return mode != other.mode \
		or moving != other.moving \
		or grounded != other.grounded \
		or magnetic != other.magnetic \
		or afterimage != other.afterimage \
		or marble_trail != other.marble_trail \
		or jumps != other.jumps \
		or landings != other.landings \
		or hits != other.hits \
		or bumps != other.bumps \
		or magnets != other.magnets \
		or clangs != other.clangs \
		or trails != other.trails \
		or absf(running - other.running) > STEP \
		or absf(wall_slide - other.wall_slide) > STEP \
		or absf(bhop_wind - other.bhop_wind) > STEP \
		or absf(skid - other.skid) > STEP \
		or twirl.distance_to(other.twirl) > 1.0 \
		or position.distance_to(other.position) > MOVED \
		or absf(angle_difference(yaw, other.yaw)) > TURNED \
		or spin.angle_to(other.spin) > TURNED \
		or up.angle_to(other.up) > TURNED


func mixed(other, t: float):
	var pose = get_script().new()
	var blended := up.lerp(other.up, t)
	var near = other if t >= 0.5 else self

	pose.position = position.lerp(other.position, t)
	pose.velocity = velocity.lerp(other.velocity, t)
	pose.up = blended.normalized() if not blended.is_zero_approx() else other.up
	pose.spin = spin.slerp(other.spin, t)
	pose.yaw = lerp_angle(yaw, other.yaw, t)

	pose.running = lerpf(running, other.running, t)
	pose.wall_slide = lerpf(wall_slide, other.wall_slide, t)
	pose.bhop_wind = lerpf(bhop_wind, other.bhop_wind, t)
	pose.skid = lerpf(skid, other.skid, t)
	pose.twirl = twirl.lerp(other.twirl, t)

	pose.mode = near.mode
	pose.moving = near.moving
	pose.grounded = near.grounded
	pose.magnetic = near.magnetic
	pose.afterimage = near.afterimage
	pose.marble_trail = near.marble_trail

	pose.jumps = near.jumps
	pose.landings = near.landings
	pose.hits = near.hits
	pose.trails = near.trails
	pose.hit_normal = near.hit_normal
	pose.hit_strength = near.hit_strength
	pose.bumps = near.bumps
	pose.magnets = near.magnets
	pose.clangs = near.clangs
	pose.bump_strength = near.bump_strength

	return pose


func copy():
	return mixed(self, 0.0)
