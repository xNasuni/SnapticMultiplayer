local MIRRAXIS = "levels/mirraxis/mirraxis"

for _, file in ipairs(GDPatch.get_pack().files) do
	if file == MIRRAXIS .. ".gdc" or file == MIRRAXIS .. ".gd" then
		GDPatch.patch_script_as_text(file, function(_, src)
			--call me the regex goat (I'm kiddingI needed help I couldn't do this alone)
			return (
				src:gsub('(music%s*=%s*AudioManager%.find_child%("Mirraxis"%))', function(line)
					return line .. "\n\tif multiplayer.has_multiplayer_peer():\n\t\treturn"
				end, 1)
			)
		end)
	end
end
