-- Possible future improvements:
-- * rewrite to use node timers instead of ABMs, but needs benchmarking
-- * redesign the catch-up logic
-- * switch to exponentially-weighted moving average for light instead using a single variable to conserve IO
--
local math = math
local vector = vector

local plant_lists = {}
mcl_farming.plant_lists = plant_lists -- export
local plant_nodename_to_id_list = {}

local time_speed = tonumber(minetest.settings:get("time_speed")) or 72
local time_multiplier = time_speed > 0 and (86400 / time_speed) or 0

local function get_intervals_counter(pos, interval, chance)
	if time_multiplier == 0 then return 0 end
	-- "wall clock time", so plants continue to grow while sleeping
	local current_game_time = (minetest.get_day_count() + minetest.get_timeofday()) * time_multiplier
	local approx_interval = math.max(interval, 1) * math.max(chance, 1)

	local meta = minetest.get_meta(pos)
	local last_game_time = meta:get_float("last_gametime")
	if last_game_time < 1 then
		last_game_time = current_game_time - approx_interval * 0.5
	elseif last_game_time == current_game_time then
		current_game_time = current_game_time + approx_interval
	end
	meta:set_float("last_gametime", current_game_time)
	return (current_game_time - last_game_time) / approx_interval
end

local function get_avg_light_level(pos)
	local meta = minetest.get_meta(pos)
	-- EWMA would use a single variable:
	-- local avg = meta:get_float("avg_light")
	-- avg = avg + (node_light - avg) * 0.985
	-- meta.set_float("avg_light", avg)
	local summary = meta:get_int("avg_light_summary")
	local counter = meta:get_int("avg_light_count")
	if counter > 99 then
		summary, counter = math.ceil(summary * 0.5), 50
	end
	local node_light = minetest.get_node_light(pos)
	if node_light ~= nil then
		summary, counter = summary + node_light, counter + 1
		meta:set_int("avg_light_summary", summary)
		meta:set_int("avg_light_count", counter)
	end
	return math.ceil(summary / counter)
end

function mcl_farming:add_plant(identifier, full_grown, names, interval, chance)
	local plant_info = {}
	plant_info.full_grown = full_grown
	plant_info.names = names
	plant_info.interval = interval
	plant_info.chance = chance
	for _, nodename in pairs(names) do
		plant_nodename_to_id_list[nodename] = identifier
	end
	plant_info.step_from_name = {}
	for i, name in ipairs(names) do
		plant_info.step_from_name[name] = i
	end
	plant_lists[identifier] = plant_info
	minetest.register_abm({
		label = string.format("Farming plant growth (%s)", identifier),
		nodenames = names,
		interval = interval,
		chance = chance,
		action = function(pos, node)
			local low_speed = minetest.get_node(vector.offset(pos, 0, -1, 0)).name ~= "mcl_farming:soil_wet"
			mcl_farming:grow_plant(identifier, pos, node, 1, false, low_speed)
		end,
	})
end

-- Attempts to advance a plant at pos by one or more growth stages (if possible)
-- identifier: Identifier of plant as defined by mcl_farming:add_plant
-- pos: Position
-- node: Node table
-- stages: Number of stages to advance (optional, defaults to 1)
-- ignore_light: if true, ignore light requirements for growing
-- low_speed: grow more slowly (not wet), default false
-- Returns true if plant has been grown by 1 or more stages.
-- Returns false if nothing changed.
function mcl_farming:grow_plant(identifier, pos, node, stages, ignore_light, low_speed)
	stages = stages or 1
	local plant_info = plant_lists[identifier]
	local intervals_counter = get_intervals_counter(pos, plant_info.interval, plant_info.chance)
	if stages > 0 then intervals_counters = intervals_counter - 1 end
	if low_speed then -- 10% speed approximately
		if intervals_counter < 1.01 and math.random(0, 9) > 0 then return false end
		intervals_counter = intervals_counter / 10
	end
	if not ignore_light and intervals_counter < 1.5 then
		local light = minetest.get_node_light(pos)
		if not light or light < 10 then return false end
	end

	if intervals_counter >= 1.5 then
		local average_light_level = get_avg_light_level(pos)
		if average_light_level < 0.1 then return false end
		if average_light_level < 10 then
			intervals_counter = intervals_counter * average_light_level / 10
		end
	end

	local step = plant_info.step_from_name[node.name]
	if step == nil then return false end
	stages = stages + math.floor(intervals_counter)
	if stages == 0 then return false end
	local new_node = { name = plant_info.names[step + stages] or plant_info.full_grown }
	new_node.param = node.param
	new_node.param2 = node.param2
	minetest.set_node(pos, new_node)
	return true
end

function mcl_farming:place_seed(itemstack, placer, pointed_thing, plantname)
	local pt = pointed_thing
	if not pt or pt.type ~= "node" then return end

	-- Use pointed node's on_rightclick function first, if present
	local node = minetest.get_node(pt.under)
	if placer and not placer:get_player_control().sneak then
		if minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].on_rightclick then
			return minetest.registered_nodes[node.name].on_rightclick(pt.under, node, placer, itemstack) or itemstack
		end
	end

	if minetest.get_node(pt.above).name ~= "air" then return end
	local farmland = minetest.registered_nodes[minetest.get_node(vector.offset(pt.above, 0, -1, 0)).name]
	if not farmland or (farmland.groups.soil or 0) < 2 then return end
	minetest.sound_play(minetest.registered_nodes[plantname].sounds.place, { pos = pt.above }, true)
	minetest.add_node(pt.above, { name = plantname, param2 = minetest.registered_nodes[plantname].place_param2 })

	if not minetest.is_creative_enabled(placer:get_player_name()) then itemstack:take_item() end
	return itemstack
end


--[[ Helper function to create a gourd (e.g. melon, pumpkin), the connected stem nodes as

- full_unconnected_stem: itemstring of the full-grown but unconnected stem node. This node must already be done
- connected_stem_basename: prefix of the itemstrings used for the 4 connected stem nodes to create
- stem_itemstring: Desired itemstring of the fully-grown unconnected stem node
- stem_def: Partial node definition of the fully-grown unconnected stem node. Many fields are already defined. You need to add `tiles` and `description` at minimum. Don't define on_construct without good reason
- stem_drop: Drop probability table for all stem
- gourd_itemstring: Desired itemstring of the full gourd node
- gourd_def: (almost) full definition of the gourd node. This function will add on_construct and after_destruct to the definition for unconnecting any connected stems
- grow_interval: Will attempt to grow a gourd periodically at this interval in seconds
- grow_chance: Chance of 1/grow_chance to grow a gourd next to the full unconnected stem after grow_interval has passed. Must be a natural number
- connected_stem_texture: Texture of the connected stem
]]


function mcl_farming:add_gourd(full_unconnected_stem, connected_stem_basename, stem_itemstring, stem_def, stem_drop, gourd_itemstring, gourd_def, grow_interval, grow_chance, connected_stem_texture)
	local connected_stem_names = {
		connected_stem_basename .. "_r",
		connected_stem_basename .. "_l",
		connected_stem_basename .. "_t",
		connected_stem_basename .. "_b" }

	-- Connect the stem at stempos to the first neighboring gourd block.
	-- No-op if not a stem or no gourd block found
	local function try_connect_stem(stempos)
		local stem = minetest.get_node(stempos)
		if stem.name ~= full_unconnected_stem then return false end
		-- four directions, but avoid table allocation
		local neighbor = vector.offset(stempos, 1, 0, 0)
		if minetest.get_node(neighbor).name == gourd_itemstring then
			minetest.swap_node(stempos, { name = connected_stem_names[1] })
			return true
		end
		local neighbor = vector.offset(stempos, -1, 0, 0)
		if minetest.get_node(neighbor).name == gourd_itemstring then
			minetest.swap_node(stempos, { name = connected_stem_names[2] })
			return true
		end
		local neighbor = vector.offset(stempos, 0, 0, 1)
		if minetest.get_node(neighbor).name == gourd_itemstring then
			minetest.swap_node(stempos, { name = connected_stem_names[3] })
			return true
		end
		local neighbor = vector.offset(stempos, 0, 0, -1)
		if minetest.get_node(neighbor).name == gourd_itemstring then
			minetest.swap_node(stempos, { name = connected_stem_names[4] })
			return true
		end
	end

	-- Register gourd
	if not gourd_def.after_destruct then
		gourd_def.after_destruct = function(blockpos, oldnode)
			-- Disconnect any connected stems, turning them back to normal stems
			-- four directions, but avoid using a table
			-- opposite directions to above, as we go from groud to stem now!
			local stempos = vector.offset(blockpos, -1, 0, 0)
			if minetest.get_node(stempos).name == connected_stem_names[1] then
				minetest.swap_node(stempos, { name = full_unconnected_stem })
				try_connect_stem(stempos)
			end
			local stempos = vector.offset(blockpos, 1, 0, 0)
			if minetest.get_node(stempos).name == connected_stem_names[2] then
				minetest.swap_node(stempos, { name = full_unconnected_stem })
				try_connect_stem(stempos)
			end
			local stempos = vector.offset(blockpos, 0, 0, -1)
			if minetest.get_node(stempos).name == connected_stem_names[3] then
				minetest.swap_node(stempos, { name = full_unconnected_stem })
				try_connect_stem(stempos)
			end
			local stempos = vector.offset(blockpos, 0, 0, 1)
			if minetest.get_node(stempos).name == connected_stem_names[4] then
				minetest.swap_node(stempos, { name = full_unconnected_stem })
				try_connect_stem(stempos)
			end
		end
	end
	if not gourd_def.on_construct then
		function gourd_def.on_construct(blockpos)
			-- Connect all unconnected stems at full size
			try_connect_stem(vector.offset(blockpos, 1, 0, 0))
			try_connect_stem(vector.offset(blockpos, -1, 0, 0))
			try_connect_stem(vector.offset(blockpos, 0, 0, 1))
			try_connect_stem(vector.offset(blockpos, 0, 0, -1))
		end
	end
	minetest.register_node(gourd_itemstring, gourd_def)

	-- Register unconnected stem

	-- Default values for the stem definition
	if not stem_def.selection_box then
		stem_def.selection_box = { type = "fixed", fixed = { { -0.15, -0.5, -0.15, 0.15, 0.5, 0.15 } } }
	end
	stem_def.paramtype = stem_def.paramtype or "light"
	stem_def.drawtype = stem_def.drawtype or "plantlike"
	stem_def.walkable = stem_def.walkable or false
	stem_def.sunlight_propagates = stem_def.sunlight_propagates == nil or stem_def.sunlight_propagates
	stem_def.drop = stem_def.drop or stem_drop
	stem_def.groups = stem_def.groups or { dig_immediate = 3, not_in_creative_inventory = 1, plant = 1, attached_node = 1, dig_by_water = 1, destroy_by_lava_flow = 1 }
	stem_def.sounds = stem_def.sounds or mcl_sounds.node_sound_leaves_defaults()
	stem_def.on_construct = stem_def.on_construct or try_connect_stem
	minetest.register_node(stem_itemstring, stem_def)

	-- Register connected stems

	local connected_stem_tiles = {
		{ "blank.png", -- top
		  "blank.png", -- bottom
		  "blank.png", -- right
		  "blank.png", -- left
		  connected_stem_texture, -- back
		  connected_stem_texture .. "^[transformFX" -- front
		},
		{ "blank.png", -- top
		  "blank.png", -- bottom
		  "blank.png", -- right
		  "blank.png", -- left
		  connected_stem_texture .. "^[transformFX", -- back
		  connected_stem_texture, -- front
		},
		{ "blank.png", -- top
		  "blank.png", -- bottom
		  connected_stem_texture .. "^[transformFX", -- right
		  connected_stem_texture, -- left
		  "blank.png", -- back
		  "blank.png", -- front
		},
		{ "blank.png", -- top
		  "blank.png", -- bottom
		  connected_stem_texture, -- right
		  connected_stem_texture .. "^[transformFX", -- left
		  "blank.png", -- back
		  "blank.png", -- front
		}
	}
	local connected_stem_nodebox = {
		{ -0.5, -0.5, 0, 0.5, 0.5, 0 },
		{ -0.5, -0.5, 0, 0.5, 0.5, 0 },
		{ 0, -0.5, -0.5, 0, 0.5, 0.5 },
		{ 0, -0.5, -0.5, 0, 0.5, 0.5 },
	}
	local connected_stem_selectionbox = {
		{ -0.1, -0.5, -0.1, 0.5, 0.2, 0.1 },
		{ -0.5, -0.5, -0.1, 0.1, 0.2, 0.1 },
		{ -0.1, -0.5, -0.1, 0.1, 0.2, 0.5 },
		{ -0.1, -0.5, -0.5, 0.1, 0.2, 0.1 },
	}

	for i = 1, 4 do
		minetest.register_node(connected_stem_names[i], {
			_doc_items_create_entry = false,
			paramtype = "light",
			sunlight_propagates = true,
			walkable = false,
			drop = stem_drop,
			drawtype = "nodebox",
			node_box = { type = "fixed", fixed = connected_stem_nodebox[i] },
			selection_box = { type = "fixed", fixed = connected_stem_selectionbox[i] },
			tiles = connected_stem_tiles[i],
			use_texture_alpha = minetest.features.use_texture_alpha_string_modes and "clip" or true,
			groups = { dig_immediate = 3, not_in_creative_inventory = 1, plant = 1, attached_node = 1, dig_by_water = 1, destroy_by_lava_flow = 1 },
			sounds = mcl_sounds.node_sound_leaves_defaults(),
			_mcl_blast_resistance = 0,
		})

		if minetest.get_modpath("doc") then
			doc.add_entry_alias("nodes", full_unconnected_stem, "nodes", connected_stem_names[i])
		end
	end

	-- Check for a suitable spot to grow
	local function check_neighbor_soil(blockpos)
		if minetest.get_node(blockpos).name ~= "air" then return false end
		local floorpos = vector.offset(blockpos, 0, -1, 0)
		local floorname = minetest.get_node(floorpos).name
		if floorname == "mcl_core:dirt" then return true end
		local floordef = minetest.registered_nodes[floorname]
		return floordef.groups.grass_block or floordef.groups.dirt or (floordef.groups.soil or 0) >= 2
	end

	minetest.register_abm({
		label = "Grow gourd stem to gourd (" .. full_unconnected_stem .. " → " .. gourd_itemstring .. ")",
		nodenames = { full_unconnected_stem },
		neighbors = { "air" },
		interval = grow_interval,
		chance = grow_chance,
		action = function(stempos)
			local light = minetest.get_node_light(stempos)
			if not light or light <= 10 then return end
			-- Check the four neighbors and filter out neighbors where gourds can't grow
			local neighbor, dir, nchance = nil, -1, 1 -- reservoir sampling
			if nchance == 1 or math.random(1, nchance) == 1 then
				local blockpos = vector.offset(stempos, 1, 0, 0)
				if check_neighbor_soil(blockpos) then
					neighbor, dir, nchance = blockpos, 1, nchance + 1
				end
			end
			if nchance == 1 or math.random(1, nchance) == 1 then
				local blockpos = vector.offset(stempos, -1, 0, 0)
				if check_neighbor_soil(blockpos) then
					neighbor, dir, nchance = blockpos, 2, nchance + 1
				end
			end
			if nchance == 1 or math.random(1, nchance) == 1 then
				local blockpos = vector.offset(stempos, 0, 0, 1)
				if check_neighbor_soil(blockpos) then
					neighbor, dir, nchance = blockpos, 3, nchance + 1
				end
			end
			if nchance == 1 or math.random(1, nchance) == 1 then
				local blockpos = vector.offset(stempos, 0, 0, -1)
				if check_neighbor_soil(blockpos) then
					neighbor, dir, nchance = blockpos, 4, nchance + 1
				end
			end

			-- Gourd needs at least 1 free neighbor to grow
			if not neighbor then return end
			minetest.swap_node(stempos, { name = connected_stem_names[dir] })
			-- Place the gourd
			if gourd_def.paramtype2 == "facedir" then
				local p2 = (dir == 1 and 3) or (dir == 2 and 1) or (dir == 3 and 2) or 0
				minetest.add_node(neighbor, { name = gourd_itemstring, param2 = p2 })
			else
				minetest.add_node(neighbor, { name = gourd_itemstring })
			end

			-- Reset farmland, etc. to dirt when the gourd grows on top
			local floorpos = vector.offset(neighbor, 0, -1, 0)
			if minetest.get_item_group(minetest.get_node(floorpos).name, "dirtifies_below_solid") == 1 then
				minetest.set_node(floorpos, { name = "mcl_core:dirt" })
			end
		end,
	})
end

-- Used for growing gourd stems. Returns the intermediate color between startcolor and endcolor at a step
-- * startcolor: ColorSpec in table form for the stem in its lowest growing stage
-- * endcolor: ColorSpec in table form for the stem in its final growing stage
-- * step: The nth growth step. Counting starts at 1
-- * step_count: The number of total growth steps
function mcl_farming:stem_color(startcolor, endcolor, step, step_count)
	local mix = (step - 1) / (step_count - 1)
	return string.format("#%02X%02X%02X",
		math.max(0, math.min(255, math.round((1 - mix) * startcolor.r + mix * endcolor.r))),
		math.max(0, math.min(255, math.round((1 - mix) * startcolor.g + mix * endcolor.g))),
		math.max(0, math.min(255, math.round((1 - mix) * startcolor.b + mix * endcolor.b))))
end

--[[Get a callback that either eats the item or plants it.

Used for on_place callbacks for craft items which are seeds that can also be consumed.
]]
function mcl_farming:get_seed_or_eat_callback(plantname, hp_change)
	return function(itemstack, placer, pointed_thing)
		return mcl_farming:place_seed(itemstack, placer, pointed_thing, plantname)
		or minetest.do_item_eat(hp_change, nil, itemstack, placer, pointed_thing)
	end
end

minetest.register_lbm({
	label = "Add growth for unloaded farming plants",
	name = "mcl_farming:growth",
	nodenames = { "group:plant" },
	run_at_every_load = true,
	action = function(pos, node, dtime_s)
		local identifier = plant_nodename_to_id_list[node.name]
		if not identifier then return end
		local low_speed = minetest.get_node(vector.offset(pos, 0, -1, 0)).name ~= "mcl_farming:soil_wet"
		mcl_farming:grow_plant(identifier, pos, node, 0, false, low_speed)
	end,
})

