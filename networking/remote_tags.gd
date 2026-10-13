extends Node

signal changed

const Utils := preload("../ui/shared/utils.gd")
const Log := preload("log.gd")

const URL := "https://raw.githubusercontent.com/xNasuni/SnapticMultiplayer/refs/heads/main/remote_tags.json"
const TIMEOUT := 5.0
const MAX_BYTES := 1048576
const COOLDOWN := 300000
const TAG_MAX_LENGTH := 24

var _request := HTTPRequest.new()
var _fetched := -COOLDOWN

func _ready() -> void:
	_request.timeout = TIMEOUT
	_request.body_size_limit = MAX_BYTES
	_request.request_completed.connect(_on_completed)
	add_child(_request)

	fetch()

func fetch() -> void:
	if URL.is_empty() or Time.get_ticks_msec() - _fetched < COOLDOWN:
		return

	if _request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return

	var err := _request.request(URL)
	if err != OK:
		Log.say("can't fetch tags (%s)" % error_string(err))

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		Log.say("tags unavailable (result %d, http %d)" % [result, code])
		return

	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		Log.warn("the tags file isn't valid json")
		return

	var tags := _parse(data)
	_fetched = Time.get_ticks_msec()

	if tags != Utils.remote_tags:
		Utils.remote_tags = tags
		Log.say("loaded tags for %d players" % tags.size())
		changed.emit()


static func _parse(data: Dictionary) -> Dictionary:
	var tags := {}

	for key: String in data:
		if not key.is_valid_int() or key.to_int() <= 0 or not data[key] is Array:
			continue

		var list := []
		for t in data[key]:
			var tag_name := str(t.get("name", "")).strip_edges().left(TAG_MAX_LENGTH) if t is Dictionary else ""

			if not tag_name.is_empty():
				list.append({"name": tag_name, "color": Utils.color_of(t.get("color"))})

		tags[key.to_int()] = list
	return tags
