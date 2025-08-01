local S = core.get_translator(core.get_current_modname())

local function active_brewing_formspec(fuel_percent, brew_percent)
	return table.concat({
		"size[9,8.75]",
		"background[-0.19,-0.25;9.5,9.5;mcl_brewing_inventory.png]",
		"label[4,0;",core.formspec_escape(core.colorize("#313131", S("Brewing Stand"))),"]",
		"label[0,4.0;",core.formspec_escape(core.colorize("#313131", S("Inventory"))),"]",
		"list[current_player;main;0,4.5;9,3;9]",
		mcl_formspec.get_itemslot_bg(0,4.5,9,3),
		"list[current_player;main;0,7.75;9,1;]",
		mcl_formspec.get_itemslot_bg(0,7.75,9,1),
		"list[context;fuel;0.5,1.75;1,1;]",
		mcl_formspec.get_itemslot_bg(0.5,1.75,1,1),"image[0.5,1.75;1,1;mcl_brewing_fuel_bg.png]",
		"list[context;input;2.75,0.5;1,1;]",
		mcl_formspec.get_itemslot_bg(2.75,0.5,1,1),
		"list[context;stand;4.5,2.5;1,1;]",
		mcl_formspec.get_itemslot_bg(4.5,2.5,1,1),"image[4.5,2.5;1,1;mcl_brewing_bottle_bg.png]",
		"list[context;stand;6,2.8;1,1;1]",
		mcl_formspec.get_itemslot_bg(6,2.8,1,1),"image[6,2.8;1,1;mcl_brewing_bottle_bg.png]",
		"list[context;stand;7.5,2.5;1,1;2]",
		mcl_formspec.get_itemslot_bg(7.5,2.5,1,1),"image[7.5,2.5;1,1;mcl_brewing_bottle_bg.png]",

		"image[2.7,3.33;1.28,0.41;mcl_brewing_burner.png^[lowpart:",
		(100-fuel_percent),":mcl_brewing_burner_active.png^[transformR270]",

		"image[2.76,1.4;1,2.15;mcl_brewing_bubbles.png^[lowpart:",
		(brew_percent),":mcl_brewing_bubbles_active.png]",

		"listring[current_player;main]",
		"listring[context;distr]]",
		"listring[context;fuel]",
		"listring[current_player;main]",
		"listring[context;input]",
		"listring[current_player;main]",
		"listring[context;stand]"
	})
end

local brewing_formspec = table.concat({
	"size[9,8.75]",
	"background[-0.19,-0.25;9.5,9.5;mcl_brewing_inventory.png]",
	"label[4,0;",core.formspec_escape(core.colorize("#313131", S("Brewing Stand"))),"]",
	"label[0,4.0;",core.formspec_escape(core.colorize("#313131", S("Inventory"))),"]",
	"list[current_player;main;0,4.5;9,3;9]",
	mcl_formspec.get_itemslot_bg(0,4.5,9,3),
	"list[current_player;main;0,7.75;9,1;]",
	mcl_formspec.get_itemslot_bg(0,7.75,9,1),
	"list[context;fuel;0.5,1.75;1,1;]",
	mcl_formspec.get_itemslot_bg(0.5,1.75,1,1),"image[0.5,1.75;1,1;mcl_brewing_fuel_bg.png]",
	"list[context;input;2.75,0.5;1,1;]",
	mcl_formspec.get_itemslot_bg(2.75,0.5,1,1),
	"list[context;stand;4.5,2.5;1,1;]",
	mcl_formspec.get_itemslot_bg(4.5,2.5,1,1),"image[4.5,2.5;1,1;mcl_brewing_bottle_bg.png]",
	"list[context;stand;6,2.8;1,1;1]",
	mcl_formspec.get_itemslot_bg(6,2.8,1,1),"image[6,2.8;1,1;mcl_brewing_bottle_bg.png]",
	"list[context;stand;7.5,2.5;1,1;2]",
	mcl_formspec.get_itemslot_bg(7.5,2.5,1,1),"image[7.5,2.5;1,1;mcl_brewing_bottle_bg.png]",

	"image[2.7,3.33;1.28,0.41;mcl_brewing_burner.png^[transformR270]",
	"image[2.76,1.4;1,2.15;mcl_brewing_bubbles.png]",

	"listring[current_player;main]",
	"listring[context;distr]",
	"listring[context;fuel]",
	"listring[current_player;main]",
	"listring[context;input]",
	"listring[current_player;main]",
	"listring[context;stand]"
})



local function brewable(inv)

	local ingredient = inv:get_stack("input",1):get_name()
	local stands = {}
	local stand_size = inv:get_size("stand")
	local was_alchemy = {false,false,false}

	local bottle, alchemy

	for i=1,stand_size do

		bottle = inv:get_stack("stand", i)
		alchemy = mcl_potions.get_alchemy(ingredient, bottle)

		if alchemy then
			stands[i] = alchemy
			was_alchemy[i] = true
		else
			stands[i] = bottle
		end

	end
	-- if any stand holds a new potion, return the list of new potions
	for i=1,#was_alchemy do
		if was_alchemy[i] then return stands end
	end

	return false
end


local function brewing_stand_timer(pos, elapsed)
	-- Inizialize metadata
	local meta = core.get_meta(pos)

	local fuel_timer = meta:get_float("fuel_timer") or 0
	local BREW_TIME = 20 -- all brews brew the same
	local BURN_TIME = BREW_TIME * 10

	--local input_item = meta:get_string("input_item") or ""
	local stand_timer = meta:get_float("stand_timer") or 0
	local fuel = meta:get_float("fuel") or 0
	local inv = meta:get_inventory()

	--local input_list, stand_list, fuel_list
	local brew_output, d
	local input_count, fuel_name, fuel_count, formspec, fuel_percent, brew_percent

	local update = true

	while update do

		update = false

		-- TODO reset progress if change detected

		brew_output = brewable(inv)
		if fuel ~= 0 and brew_output then

			fuel_timer = fuel_timer + elapsed
			stand_timer = stand_timer + elapsed

			if fuel_timer >= BURN_TIME then --replace with more fuel
				fuel = 0 --force a new fuel grab
				fuel_timer = 0
			end

			d = 0.5
			core.add_particlespawner({
				amount = 4,
				time = 1,
				minpos = {x=pos.x-d, y=pos.y+0.5, z=pos.z-d},
				maxpos = {x=pos.x+d, y=pos.y+2, z=pos.z+d},
				minvel = {x=-0.1, y=0, z=-0.1},
				maxvel = {x=0.1, y=0.5, z=0.1},
				minacc = {x=-0.05, y=0, z=-0.05},
				maxacc = {x=0.05, y=.1, z=0.05},
				minexptime = 1,
				maxexptime = 2,
				minsize = 0.5,
				maxsize = 2,
				collisiondetection = true,
				vertical = false,
				texture = "mcl_brewing_bubble_sprite.png",
			})

			-- Replace the stand item with the brew result
			if stand_timer >= BREW_TIME then

				input_count = inv:get_stack("input",1):get_count()
				if (input_count-1) ~= 0 then
					inv:set_stack("input",1,inv:get_stack("input",1):get_name().." "..(input_count-1))
				else
					inv:set_stack("input",1,"")
				end

				for i=1, inv:get_size("stand") do
					if brew_output[i] then
						core.sound_play("mcl_brewing_complete", {pos=pos, gain=0.4, max_hear_range=6}, true)
						inv:set_stack("stand", i, brew_output[i])
						core.sound_play("mcl_potions_bottle_pour", {pos=pos, gain=0.6, max_hear_range=6}, true)
					end
				end
				stand_timer = 0
				update = false -- stop the update if brew is complete
			end

		elseif fuel == 0 then  --get more fuel from fuel_list

			-- only allow flaming powder fuel
			fuel_name = inv:get_stack("fuel",1):get_name()
			fuel_count = inv:get_stack("fuel",1):get_count()

			if fuel_name == "mcl_mobitems:flaming_powder" then -- Grab another fuel

				if (fuel_count-1) ~= 0 then
					inv:set_stack("fuel",1,fuel_name.." "..(fuel_count-1))
				else
					inv:set_stack("fuel",1,"")
				end
				update = true
				fuel = 1
			else -- no fuel available
				update = false
			end

		end

		elapsed = 0
	end

	--update formspec
	formspec = brewing_formspec

	local result = false

	if fuel_timer ~= 0 then
		fuel_percent = math.floor(fuel_timer/BURN_TIME*100 % BURN_TIME)
		brew_percent = math.floor(stand_timer/BREW_TIME*100)
		formspec = active_brewing_formspec(fuel_percent, brew_percent*1 % 100)
		result = true
	else
		core.get_node_timer(pos):stop()
	end

	meta:set_float("fuel_timer", fuel_timer)
	meta:set_float("stand_timer", stand_timer)
	meta:set_float("fuel", fuel)
	meta:set_string("formspec", formspec)

	return result
end



-- Drop input items of brewing_stand at pos with metadata meta
local function drop_brewing_stand_items(pos, meta)

	local inv = meta:get_inventory()

	local stack = inv:get_stack("fuel", 1)
	if not stack:is_empty() then
		local p = {x=pos.x+math.random(0, 10)/10-0.5, y=pos.y, z=pos.z+math.random(0, 10)/10-0.5}
		core.add_item(p, stack)
	end

	local stack = inv:get_stack("input", 1)
	if not stack:is_empty() then
		local p = {x=pos.x+math.random(0, 10)/10-0.5, y=pos.y, z=pos.z+math.random(0, 10)/10-0.5}
		core.add_item(p, stack)
	end

	for i=1, inv:get_size("stand") do
		local stack = inv:get_stack("stand", i)
		if not stack:is_empty() then
			local p = {x=pos.x+math.random(0, 10)/10-0.5, y=pos.y, z=pos.z+math.random(0, 10)/10-0.5}
			core.add_item(p, stack)
		end
	end
end


local on_rotate
if core.get_modpath("screwdriver") then
	on_rotate = screwdriver.rotate_simple
end

local doc_string =
	S("To use a brewing stand, rightclick it.").."\n"..
	S("To brew, you need flaming powder as fuel, a brewing material and at least 1 glass bottle filled with a liquid.").."\n"..
	S("Place the flaming powder in the left slot, the brewing material in the middle slot and 1-3 bottles in the remaining slots.").."\n"..
	S("When you have found a good combination, the brewing will commence automatically and steam starts to appear, using up the fuel and brewing material. The potions will soon be ready.").."\n"..
	S("Different combinations of brewing materials and liquids will give different results. Try to experiment!")

local tiles = {
	"mcl_brewing_top.png", 	--top
	"mcl_brewing_base.png", 	--bottom
	"mcl_brewing_side.png", 	--right
	"mcl_brewing_side.png", 	--left
	"mcl_brewing_side.png", 	--back
	"mcl_brewing_side.png^[transformFX",   --front
}

local function allow_put(pos, listname, index, stack, player)
	local name = player:get_player_name()
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return 0
	elseif listname == "stand" then
		local meta = core.get_meta(pos)
		local inv = meta:get_inventory()
		local def = stack:get_definition()
		if def and def.groups and (def.groups._mcl_potion or def.groups.bottle or 0) > 0
				and inv:get_stack(listname, index):is_empty() then
			return 1
		end
		return 0
	elseif listname == "distr" then
		local meta = core.get_meta(pos)
		local inv = meta:get_inventory()
		local def = stack:get_definition()
		local fuel_stack = inv:get_stack("fuel", 1)
		local input_stack = inv:get_stack("input", 1)
		if def and def.groups and (def.groups._mcl_potion or def.groups.bottle or 0) > 0 then
			for i=1, inv:get_size("stand") do
				if inv:get_stack("stand", i):is_empty() then
					return 1
				end
			end
			return 0
		elseif not fuel_stack:is_empty() and fuel_stack:item_fits(stack:peek_item()) then
			return fuel_stack:get_free_space()
		elseif not input_stack:is_empty() and input_stack:item_fits(stack:peek_item()) then
			return input_stack:get_free_space()
		elseif fuel_stack:is_empty() or input_stack:is_empty() then
			return stack:get_count()
		else
			return 0
		end
	else
		return stack:get_count()
	end
end

local function on_put(pos, listname, index, stack, player)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()
	local str = ""
	local s
	local oldparam2 = core.get_node(pos).param2
	if listname == "distr" then
		local def = stack:get_definition()
		local fuel_stack = inv:get_stack("fuel", 1)
		if def and def.groups and (def.groups._mcl_potion or def.groups.bottle or 0) > 0 then
			for i=1, inv:get_size("stand") do
				if inv:get_stack("stand", i):is_empty() then
					inv:set_stack("stand", i, stack)
					inv:set_stack("distr", 1, ItemStack())
					break
				end
			end
		elseif not fuel_stack:is_empty() and fuel_stack:item_fits(stack) then
			inv:add_item("fuel", stack)
			inv:set_stack("distr", 1, ItemStack())
		elseif inv:room_for_item("input", stack) then
			inv:add_item("input", stack)
			inv:set_stack("distr", 1, ItemStack())
		elseif inv:room_for_item("fuel", stack) then
			inv:add_item("fuel", stack)
			inv:set_stack("distr", 1, ItemStack())
		end
	end
	for i=1, inv:get_size("stand") do
		s = inv:get_stack("stand", i)
		if not s:is_empty() then
			str = str.."1"
		else str = str.."0"
		end
	end
	core.swap_node(pos, {name = "mcl_brewing:stand_"..str, param2 = oldparam2})
	core.get_node_timer(pos):start(1.0)
end

local function on_destruct(pos)
	local meta = core.get_meta(pos)
	drop_brewing_stand_items(pos, meta)
end

local function allow_take(pos, listname, index, stack, player)
	local name = player:get_player_name()
	if core.is_protected(pos, name) then
		core.record_protection_violation(pos, name)
		return 0
	else
		local def = stack:get_definition()
		if listname == "stand" and def and def.groups and (def.groups._mcl_potion or 0) > 0 then
			awards.unlock(name, "mcl:localBrewery")
		end
		return stack:get_count()
	end
end

local function allow_move(pos, from_list, from_index, to_list, to_index, count, player)
	if (from_list == "stand" or to_list == "stand")
			and (from_list ~= to_list
				or not core.get_meta(pos):get_inventory():get_stack(to_list, to_index):is_empty())
			or from_list == "distr" or to_list == "distr" then
		return 0
	elseif from_list == "stand" and to_list == "stand" then
		return 1
	else
		return count
	end
end

local function hoppers_on_try_push(pos, hop_pos, hop_inv, hop_list)
	local meta = core.get_meta(pos)
	local inv = meta:get_inventory()

	if math.abs(pos.y - hop_pos.y) > math.abs(pos.x - hop_pos.x) and math.abs(pos.y - hop_pos.y) > math.abs(pos.z - hop_pos.z)
	then
		local function filter(stack)
			return core.get_item_group(stack:get_name(), "brewitem") == 1 and
			       core.get_item_group(stack:get_name(), "bottle") == 0
		end

		return inv, "input", mcl_util.select_stack(hop_inv, hop_list, inv, "input", filter, 1)
	else
		local filter = function(stack)
			return stack:get_name() == "mcl_mobitems:flaming_powder"
		end
		local stack = mcl_util.select_stack(hop_inv, hop_list, inv, "fuel", filter, 1 )
		if stack then
			return inv, "fuel", stack
		else
			local function filter(stack)
				local stack_name = stack:get_name()
				return core.get_item_group(stack_name, "bottle") == 1
				    or core.get_item_group(stack_name, "_mcl_potion") == 1
			end

			-- Don't use distr inventory for sorting out bottles if there is something already there
			inv:set_size("distr", 1)
			if not inv:get_stack("distr", 1):is_empty() then return end

			-- Allow a bottle to go into the distr inventory if there is an empty bottle position
			for i=1,inv:get_size("stand") do
				if inv:get_stack("stand", i):is_empty() then
					return inv, "distr", mcl_util.select_stack(hop_inv, hop_list, inv, "stand", filter, 1)
				end
			end
		end
	end
end

local function hoppers_on_try_pull(pos, hop_pos, hop_inv, hop_list)
	local meta = core.get_meta(pos)
	local stand_timer = meta:get_float("stand_timer") or 0
	if stand_timer > 0 then
		return nil, nil, nil
	end

	local inv = meta:get_inventory()
	local stack = mcl_util.select_stack(inv, "stand", hop_inv, hop_list)
	return inv, "stand", stack
end

local stand_def = {
	description = S("Brewing Stand"),
	_doc_items_longdesc = S("The stand allows you to brew potions!"),
	_doc_items_usagehelp = doc_string,
	_tt_help = S("Brew Potions"),
	groups = {pickaxey=1, container = 2, brewitem=1 },
	tiles = tiles,
	use_texture_alpha = "clip",
	drop = "mcl_brewing:stand",
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	paramtype2 = "facedir",
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {

			{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
			{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
			{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
			{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

			{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
			{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
			{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
			{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1

			{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
			{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
			{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
			{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

			{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
			{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
			{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
		}
	},
	sounds = mcl_sounds.node_sound_metal_defaults(),
	_mcl_blast_resistance = 0.5,
	_mcl_hardness = 0.5,
	on_destruct = on_destruct,
	allow_metadata_inventory_take = allow_take,
	allow_metadata_inventory_put = allow_put,
	allow_metadata_inventory_move = allow_move,
	on_metadata_inventory_put = on_put,
	on_metadata_inventory_take = on_put,
	on_metadata_inventory_move = on_put,

	on_construct = function(pos)
		local meta = core.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size("input", 1)
		inv:set_size("fuel", 1)
		inv:set_size("stand", 3)
		inv:set_size("distr", 1)
		local form = brewing_formspec
		meta:set_string("formspec", form)
	end,

	on_receive_fields = function(pos, formname, fields, sender)
		local sender_name = sender:get_player_name()
		if core.is_protected(pos, sender_name) then
			core.record_protection_violation(pos, sender_name)
			return
		end
	end,

	on_timer = brewing_stand_timer,
	on_rotate = on_rotate,
	_mcl_hoppers_on_try_push = hoppers_on_try_push,
	_mcl_hoppers_on_try_pull = hoppers_on_try_pull,
	_mcl_hoppers_on_after_push = function(pos, listname, stack)
		on_put(pos, listname, nil, stack, nil)
	end,
	_mcl_hoppers_on_after_pull = function(pos)
		on_put(pos, nil, nil, nil, nil)
	end,
}
core.register_node("mcl_brewing:stand_000", stand_def)

local stand_def_100 = table.copy(stand_def)
stand_def_100._doc_items_create_entry = false
stand_def_100._doc_items_longdesc = nil
stand_def_100._doc_items_usagehelp = nil
stand_def_100.groups = { pickaxey = 1, container = 2,
	not_in_creative_inventory = 1, not_in_craft_guide = 1 }
stand_def_100.node_box = {
	type = "fixed",
	fixed = {

		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

		{-7/16, -6/16 ,-7/16 , -6/16,  1/16, -6/16 }, -- bottle 1
		{-6/16, -6/16 ,-6/16 , -5/16,  3/16, -5/16 }, -- bottle 1
		{-5/16, -6/16 ,-5/16 , -4/16,  3/16, -4/16 }, -- bottle 1
		{-4/16, -6/16 ,-4/16 , -3/16,  3/16, -3/16 }, -- bottle 1
		{-3/16, -6/16 ,-3/16 , -2/16,  1/16, -2/16 }, -- bottle 1

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_100", stand_def_100)

local stand_def_010 = table.copy(stand_def_100)
stand_def_010.node_box = {
	type = "fixed",
	fixed = {

		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1


		{7/16, -6/16 ,-7/16 , 6/16,  1/16, -6/16 }, -- bottle 2
		{6/16, -6/16 ,-6/16 , 5/16,  3/16, -5/16 }, -- bottle 2
		{5/16, -6/16 ,-5/16 , 4/16,  3/16, -4/16 }, -- bottle 2
		{4/16, -6/16 ,-4/16 , 3/16,  3/16, -3/16 }, -- bottle 2
		{3/16, -6/16 ,-3/16 , 2/16,  1/16, -2/16 }, -- bottle 2

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_010", stand_def_010)

local stand_def_001 = table.copy(stand_def_100)
stand_def_001.node_box = {
	type = "fixed",
	fixed = {
		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, --

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, -6/16 , 2/16 , 1/16, 1/16, 7/16 }, -- bottle 3
		{0/16, 1/16 , 3/16 , 1/16,  3/16, 6/16 }, -- bottle 3

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_001", stand_def_001)

local stand_def_110 = table.copy(stand_def_100)
stand_def_110.node_box = {
	type = "fixed",
	fixed = {
		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

		{-7/16, -6/16 ,-7/16 , -6/16,  1/16, -6/16 }, -- bottle 1
		{-6/16, -6/16 ,-6/16 , -5/16,  3/16, -5/16 }, -- bottle 1
		{-5/16, -6/16 ,-5/16 , -4/16,  3/16, -4/16 }, -- bottle 1
		{-4/16, -6/16 ,-4/16 , -3/16,  3/16, -3/16 }, -- bottle 1
		{-3/16, -6/16 ,-3/16 , -2/16,  1/16, -2/16 }, -- bottle 1

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1


		{7/16, -6/16 ,-7/16 , 6/16,  1/16, -6/16 }, -- bottle 2
		{6/16, -6/16 ,-6/16 , 5/16,  3/16, -5/16 }, -- bottle 2
		{5/16, -6/16 ,-5/16 , 4/16,  3/16, -4/16 }, -- bottle 2
		{4/16, -6/16 ,-4/16 , 3/16,  3/16, -3/16 }, -- bottle 2
		{3/16, -6/16 ,-3/16 , 2/16,  1/16, -2/16 }, -- bottle 2

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_110", stand_def_110)

local stand_def_101 = table.copy(stand_def_100)
stand_def_101.node_box = {
	type = "fixed",
	fixed = {
		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

		{-7/16, -6/16 ,-7/16 , -6/16,  1/16, -6/16 }, -- bottle 1
		{-6/16, -6/16 ,-6/16 , -5/16,  3/16, -5/16 }, -- bottle 1
		{-5/16, -6/16 ,-5/16 , -4/16,  3/16, -4/16 }, -- bottle 1
		{-4/16, -6/16 ,-4/16 , -3/16,  3/16, -3/16 }, -- bottle 1
		{-3/16, -6/16 ,-3/16 , -2/16,  1/16, -2/16 }, -- bottle 1

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, -6/16 , 2/16 , 1/16, 1/16, 7/16 }, -- bottle 3
		{0/16, 1/16 , 3/16 , 1/16,  3/16, 6/16 }, -- bottle 3

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_101", stand_def_101)

local stand_def_011 = table.copy(stand_def_100)
stand_def_011.node_box = {
	type = "fixed",
	fixed = {
		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1

		{7/16, -6/16 ,-7/16 , 6/16,  1/16, -6/16 }, -- bottle 2
		{6/16, -6/16 ,-6/16 , 5/16,  3/16, -5/16 }, -- bottle 2
		{5/16, -6/16 ,-5/16 , 4/16,  3/16, -4/16 }, -- bottle 2
		{4/16, -6/16 ,-4/16 , 3/16,  3/16, -3/16 }, -- bottle 2
		{3/16, -6/16 ,-3/16 , 2/16,  1/16, -2/16 }, -- bottle 2

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, -6/16 , 2/16 , 1/16, 1/16, 7/16 }, -- bottle 3
		{0/16, 1/16 , 3/16 , 1/16,  3/16, 6/16 }, -- bottle 3

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_011", stand_def_011)

local stand_def_111 = table.copy(stand_def_100)
stand_def_111.node_box = {
	type = "fixed",
	fixed = {
		{-1/16, -5/16, -1/16, 1/16, 8/16, 1/16}, -- heat plume
		{ 2/16, -8/16, -8/16, 8/16, -6/16, -2/16}, -- base
		{-8/16, -8/16, -8/16, -2/16, -6/16, -2/16}, -- base
		{-3/16, -8/16, 2/16, 3/16, -6/16, 8/16}, -- base

		{-7/16, -6/16 ,-7/16 , -6/16,  1/16, -6/16 }, -- bottle 1
		{-6/16, -6/16 ,-6/16 , -5/16,  3/16, -5/16 }, -- bottle 1
		{-5/16, -6/16 ,-5/16 , -4/16,  3/16, -4/16 }, -- bottle 1
		{-4/16, -6/16 ,-4/16 , -3/16,  3/16, -3/16 }, -- bottle 1
		{-3/16, -6/16 ,-3/16 , -2/16,  1/16, -2/16 }, -- bottle 1

		{-5/16, 3/16 ,-5/16 , -4/16,  7/16, -4/16 }, -- line 1
		{-4/16, 6/16 ,-4/16 , -3/16,  8/16, -3/16 }, -- line 1
		{-3/16, 7/16 ,-3/16 , -2/16,  8/16, -2/16 }, -- line 1
		{-2/16, 7/16 ,-2/16 , -1/16,  8/16, -1/16 }, -- line 1


		{7/16, -6/16 ,-7/16 , 6/16,  1/16, -6/16 }, -- bottle 2
		{6/16, -6/16 ,-6/16 , 5/16,  3/16, -5/16 }, -- bottle 2
		{5/16, -6/16 ,-5/16 , 4/16,  3/16, -4/16 }, -- bottle 2
		{4/16, -6/16 ,-4/16 , 3/16,  3/16, -3/16 }, -- bottle 2
		{3/16, -6/16 ,-3/16 , 2/16,  1/16, -2/16 }, -- bottle 2

		{5/16, 3/16 ,-5/16 ,4/16,  7/16, -4/16 }, -- line 2
		{4/16, 6/16 ,-4/16 ,3/16,  8/16, -3/16 }, -- line 2
		{3/16, 7/16 ,-3/16 ,2/16,  8/16, -2/16 }, -- line 2
		{2/16, 7/16 ,-2/16 ,1/16,  8/16, -1/16 }, -- line 2

		{0/16, -6/16 , 2/16 , 1/16, 1/16, 7/16 }, -- bottle 3
		{0/16, 1/16 , 3/16 , 1/16,  3/16, 6/16 }, -- bottle 3

		{0/16, 7/16 , 1/16 , 1/16, 8/16, 3/16 }, -- line 3
		{0/16, 6/16 , 3/16 , 1/16, 7/16, 5/16 }, -- line 3
		{0/16, 3/16 , 4/16 , 1/16, 6/16, 5/16 }, -- line 3
	}
}
core.register_node("mcl_brewing:stand_111", stand_def_111)

core.register_craft({
	output = "mcl_brewing:stand_000",
	recipe = {
		{ "", "mcl_mobitems:flaming_rod", "" },
		{ "group:cobble", "group:cobble", "group:cobble" },
	}
})

core.register_alias("mcl_brewing:stand", "mcl_brewing:stand_000")

if core.get_modpath("doc") then
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_001")
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_010")
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_011")
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_100")
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_101")
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_110")
	doc.add_entry_alias("nodes", "mcl_brewing:stand_000", "nodes", "mcl_brewing:stand_111")
end

if core.get_modpath("mesecons_mvps") then
	for _, s in ipairs({"000", "001", "010", "011", "100", "101", "110", "111"}) do
		mesecon.register_mvps_stopper("mcl_brewing:stand_" .. s)
	end
end
