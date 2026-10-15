extends Node

signal changed

const Utils := preload("../ui/shared/utils.gd")
const Log := preload("log.gd")

const TAGS_URL := "https://raw.githubusercontent.com/xNasuni/SnapticMultiplayer/refs/heads/main/remote_tags.json"
const RELEASE_URL := "https://api.github.com/repos/xNasuni/SnapticMultiplayer/releases/latest"
const TIMEOUT := 5.0
const MAX_BYTES := 1048576
const TAG_MAX_LENGTH := 24

var latest_version := ""

var _tags_done := false
var _release_done := false
var _waiting: Array[Callable] = []

func _ready() -> void:
	_fetch(TAGS_URL, _on_tags, PackedStringArray())
	_fetch(RELEASE_URL, _on_release, PackedStringArray(["Accept: application/vnd.github+json"]))

func is_mod_outdated(version: String, callback: Callable) -> void:
	if _release_done:
		callback.call(_is_outdated(version), latest_version)
		return

	_waiting.append(func() -> void:
		callback.call(_is_outdated(version), latest_version))

func _is_outdated(version: String) -> bool:
	return not latest_version.is_empty() and latest_version != version

func _fetch(url: String, handler: Callable, headers: PackedStringArray) -> void:
	var request := HTTPRequest.new()
	request.timeout = TIMEOUT
	request.body_size_limit = MAX_BYTES
	add_child(request)

	request.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			Log.say("couldn't fetch %s (result %d, http %d)" % [url, result, code])
			handler.call(null)
			return
		handler.call(JSON.parse_string(body.get_string_from_utf8())))

	var err := request.request(url, headers)
	if err != OK:
		Log.say("can't fetch %s (%s)" % [url, error_string(err)])
		request.queue_free()
		handler.call(null)

func _on_tags(data: Variant) -> void:
	_tags_done = true

	if not data is Dictionary:
		if data != null:
			Log.warn("the tags file isn't valid json")
		return

	var tags := _parse(data)
	if tags != Utils.remote_tags:
		Utils.remote_tags = tags
		Log.say("loaded tags for %d players" % tags.size())
		changed.emit()

func _on_release(data: Variant) -> void:
	_release_done = true

	if data is Dictionary and data.get("tag_name") is String:
		latest_version = (data["tag_name"] as String).strip_edges()
		Log.say("latest release is %s" % latest_version)

	var waiting := _waiting
	_waiting = []
	for cb in waiting:
		cb.call()

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