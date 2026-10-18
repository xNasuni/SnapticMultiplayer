local MIRRAXIS = "levels/mirraxis/mirraxis"
local PLAYER = "actors/player/player"

-- read the event pressed instead of just pressed (lets chat_box.gd sink this input)
for _, file in ipairs(GDPatch.get_pack().files) do
	if file == PLAYER .. ".gdc" or file == PLAYER .. ".gd" then
		GDPatch.patch_script_as_text(file, function(_, src)
			return (
				src:gsub('Input%.is_action_just_pressed%(&"oldest_trick_in_the_book"%)', function()
					return '_event.is_action_pressed(&"oldest_trick_in_the_book")'
				end, 1)
			)
		end)
	end
end

for _, file in ipairs(GDPatch.get_pack().files) do
	if file == MIRRAXIS .. ".gdc" or file == MIRRAXIS .. ".gd" then
		GDPatch.patch_script_as_text(file, function(_, src)
			--call me the regex goat (I'm kiddingI needed help I couldn't do this alone)
			return (
				src:gsub('(music%s*=%s*AudioManager%.find_child%("Mirraxis"%))', function(line)
					return line .. "\n\tif multiplayer.has_multiplayer_peer():\n\t\t_on_initial_cutscene_finished()\n\t\treturn"
				end, 1)
			)
		end)
	end
end
