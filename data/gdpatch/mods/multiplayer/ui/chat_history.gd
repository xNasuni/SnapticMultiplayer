extends RefCounted

const LIMIT := 128

var _entries: Array[String] = []
var _at := -1
var _draft := ""

func add(text: String) -> void:
	reset()
	if not _entries.is_empty() and _entries.back() == text:
		return

	_entries.append(text)
	if _entries.size() > LIMIT:
		_entries.pop_front()

func reset() -> void:
	_at = -1
	_draft = ""

func older(current: String) -> String:
	if _entries.is_empty():
		return current
	if _at == -1:
		_draft = current
		_at = _entries.size()

	_at = maxi(_at - 1, 0)
	return _entries[_at]

func newer(current: String) -> String:
	if _at == -1:
		return current

	_at += 1
	if _at >= _entries.size():
		var draft := _draft
		reset()
		
		return draft
	return _entries[_at]