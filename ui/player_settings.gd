extends RefCounted

const PlayerPreview := preload("player_preview.gd")


func build(panel) -> void:
	var page = panel.add_tab("Player")
	var preview := PlayerPreview.new()

	page.add_color("Player Color", "player_color")
	preview.bind(panel.store, "player_color")
	page.set_preview(preview)
