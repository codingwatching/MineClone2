mcl_bossbars = {
	bars = {},
	huds = {},
	static = {},
	colors = {"light_purple", "blue", "red", "green", "yellow", "dark_purple", "white"},
}

function mcl_bossbars.recalculate_colors()
	local sorted = {}
	local colors = mcl_bossbars.colors
	local color_count = #colors
	local frame_count = color_count * 2
	for i, color in ipairs(colors) do
		local idx = i * 2 - 1
		local image = "mcl_bossbars.png"
			.. "^[transformR270"
			.. "^[verticalframe:" .. frame_count .. ":" .. (idx - 1)
			.. "^(mcl_bossbars_empty.png"
			.. "^[lowpart:%d:mcl_bossbars.png"
			.. "^[transformR270"
			.. "^[verticalframe:" .. frame_count .. ":" .. idx .. ")"
		local _, hex = mcl_util.get_color(color)
		sorted[color] = {
			image = image,
			hex = hex,
		}
	end
	mcl_bossbars.colors_sorted = sorted
end

local function get_color_info(color, percentage)
	local cdef = mcl_bossbars.colors_sorted[color]
	return cdef.hex, string.format(cdef.image, percentage)
end

local last_id = 0

function mcl_bossbars.add_bar(player, def)
	local name = player:get_player_name()
	local bar = {text = def.text}
	bar.color, bar.image = get_color_info(def.color, def.percentage)
	table.insert(mcl_bossbars.bars[name], bar)
	if not def.dynamic then
		bar.raw_color = def.color
		bar.id = last_id + 1
		last_id = bar.id
		mcl_bossbars.static[bar.id] = bar
		return id
	end
end

function mcl_bossbars.remove_bar(id)
	mcl_bossbars.static[id].bar.static = false
	mcl_bossbars.static[id] = nil
end

function mcl_bossbars.update_bar(id, def)
	local old = mcl_bossbars.static[id]
	old.color = get_color_info(def.color or old.raw_color, def.percentage or old.percentage)
	old.text = def.text or old.text
end

function mcl_bossbars.update_boss(luaentity, name, color)
	local object = luaentity.object
	local bardef = {
		text = luaentity.nametag,
		percentage = math.floor(luaentity.health / luaentity.hp_max * 100),
		color = color,
		dynamic = true,
	}
	if not bardef.text or bardef.text == "" then
		bardef.text = name
	end
	for _, obj in pairs(minetest.get_objects_inside_radius(object:get_pos(), 128)) do
		if obj:is_player() then
			mcl_bossbars.add_bar(obj, bardef)
		end
	end
end

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	mcl_bossbars.huds[name] = {}
	mcl_bossbars.bars[name] = {}
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	mcl_bossbars.huds[name] = nil
	for _, bar in pairs(mcl_bossbars.bars[name]) do
		if bar.id then
			mcl_bossbars.static[bar.id] = nil
		end
	end
	mcl_bossbars.bars[name] = nil
end)

minetest.register_globalstep(function()
	for _, player in pairs(minetest.get_connected_players()) do
		local name = player:get_player_name()
		local bars = mcl_bossbars.bars[name]
		local huds = mcl_bossbars.huds[name]
		local huds_new = {}
		local bars_new = {}
		local i = 0

		while #huds > 0 or #bars > 0 do
			local bar = table.remove(bars, 1)
			local hud = table.remove(huds, 1)

			if bar and bar.id then
				table.insert(bars_new, bar)
			end

			if bar and not hud then
				hud = {
					color = bar.color,
					image = bar.image,
					text = bar.text,
					text_id = player:hud_add({
						hud_elem_type = "text",
						text = bar.text,
						number = bar.color,
						position = {x = 0.5, y = 0},
						alignment = {x = 0, y = 1},
						offset = {x = 0, y = i * 40},
					}),
					image_id = player:hud_add({
						hud_elem_type = "image",
						text = bar.image,
						position = {x = 0.5, y = 0},
						alignment = {x = 0, y = 1},
						offset = {x = 0, y = i * 40 + 25},
						scale = {x = 3, y = 3},
					}),
				}
			elseif hud and not bar then
				player:hud_remove(hud.text_id)
				player:hud_remove(hud.image_id)
				hud = nil
			else
				if bar.text ~= hud.text then
					player:hud_change(hud.text_id, "text", bar.text)
					hud.text = bar.text
				end

				if bar.color ~= hud.color then
					player:hud_change(hud.text_id, "number", bar.color)
					hud.color = bar.color
				end

				if bar.image ~= hud.image then
					player:hud_change(hud.image_id, "text", bar.image)
					hud.image = bar.image
				end
			end

			table.insert(huds_new, hud)
			i = i + 1
		end

		mcl_bossbars.huds[name] = huds_new
		mcl_bossbars.bars[name] = bars_new
	end
end)

mcl_bossbars.recalculate_colors()
