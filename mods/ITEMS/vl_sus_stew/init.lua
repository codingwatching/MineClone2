vl_sus_stew = {}

local S = core.get_translator(core.get_current_modname())

--                                          ____________________________
--_________________________________________/    Variables & Functions    \_________

local eat = core.item_eat(6, "mcl_core:bowl") --6 hunger points, player receives mcl_core:bowl after eating

local ingredient_effect = {}
local effects = {}

local function get_random_effect()
	local keys = {}
	for k in pairs(effects) do
		table.insert(keys, k)
	end
	return effects[keys[math.random(#keys)]]
end

local function eat_stew(itemstack, user, pointed_thing)
	local e = itemstack:get_meta():get_string("effect")
	local f = effects[e]
	if not f then
		f = get_random_effect()
	end
	return f(itemstack, user, pointed_thing)
end

local function eat_stew_delayed(itemstack, user, pointed_thing)
	local called
	itemstack, called = mcl_util.handle_node_rightclick(itemstack, user, pointed_thing)
	if called then return itemstack end

	-- Wrapper for handling mcl_hunger delayed eating
	local name = user:get_player_name()
	mcl_hunger.eat_internal[name]._custom_itemstack = itemstack -- Used as comparison to make sure the custom wrapper executes only when the same item is eaten
	mcl_hunger.eat_internal[name]._custom_var = {
		user = user,
		pointed_thing = pointed_thing,
	}
	mcl_hunger.eat_internal[name]._custom_func = eat_stew
	mcl_hunger.eat_internal[name]._custom_wrapper = function(name)
		mcl_hunger.eat_internal[name]._custom_func(
			mcl_hunger.eat_internal[name]._custom_itemstack,
			mcl_hunger.eat_internal[name]._custom_var.user,
			mcl_hunger.eat_internal[name]._custom_var.pointed_thing
		)
	end

	core.do_item_eat(0, "mcl_core:bowl", itemstack, user, pointed_thing)

	return itemstack
end

core.register_on_craft(function(itemstack, player, old_craft_grid, craft_inv)
	if itemstack:get_name() ~= "vl_sus_stew:stew" then return end
	for _,it in pairs(old_craft_grid) do
		local effect = ingredient_effect[it:get_name()]
		if effect ~= nil then
			itemstack:get_meta():set_string("effect", effect)
			return itemstack
		end
	end
end)

--											________________________
--_________________________________________/	Item Registration	\_________________
core.register_craftitem("vl_sus_stew:stew",{
	description = S("Suspicious Stew"),
	inventory_image = "sus_stew.png",
	stack_max = 1,
	on_place = eat_stew_delayed,
	on_secondary_use = eat_stew_delayed,
	groups = { food = 2, eatable = 4, can_eat_when_full = 1, not_in_creative_inventory=1,},
	_mcl_saturation = 7.2,
})

mcl_hunger.register_food("vl_sus_stew:stew", 6, "mcl_core:bowl")

-- compat with old (mcl5) sus_stew
core.register_alias("mcl_sus_stew:poison_stew", "vl_sus_stew:stew")
core.register_alias("mcl_sus_stew:hunger_stew", "vl_sus_stew:stew")
core.register_alias("mcl_sus_stew:jump_boost_stew", "vl_sus_stew:stew")
core.register_alias("mcl_sus_stew:regneration_stew", "vl_sus_stew:stew")
core.register_alias("mcl_sus_stew:night_vision_stew", "vl_sus_stew:stew")

-- compat with old mod namespace
core.register_alias("mcl_sus_stew:stew", "vl_sus_stew:stew")

--										 	____________
--_________________________________________/	API		\________________________________

local forbidden_sec_ingr = {
	["mcl_mushrooms:mushroom_red"] = true,
	["mcl_mushrooms:mushroom_brown"] = true,
	["mcl_core:bowl"] = true
}
function vl_sus_stew.register_sus_stew(secret_ingredient, effect_name)
	assert(not forbidden_sec_ingr[secret_ingredient], "Duplicate ingredient not allowed!")
	ingredient_effect[secret_ingredient] = effect_name
	core.register_craft({
		type = "shapeless",
		output = "vl_sus_stew:stew",
		recipe = {"mcl_mushrooms:mushroom_red", "mcl_mushrooms:mushroom_brown", "mcl_core:bowl", secret_ingredient},
	})
end

function vl_sus_stew.register_sus_effect(effect_name, effect_func)
	effects[effect_name] = effect_func
end

function vl_sus_stew.register_sus_potion_effect(potion_name, level, duration, effect_name)
	if effect_name == nil then effect_name = potion_name end
	local function on_eat_effect(itemstack, placer, pointed_thing)
		mcl_potions.give_effect_by_level(potion_name, placer, level, duration)
		return "mcl_core:bowl"
	end
	vl_sus_stew.register_sus_effect(effect_name, on_eat_effect)
end

vl_sus_stew.register_sus_potion_effect("fire_resistance", 1, 20)
vl_sus_stew.register_sus_potion_effect("blindness",       1, 10)
vl_sus_stew.register_sus_potion_effect("poison",          1, 12)
vl_sus_stew.register_sus_potion_effect("saturation",      1, 10)
vl_sus_stew.register_sus_potion_effect("leaping",         1, 20, "jump")
vl_sus_stew.register_sus_potion_effect("regeneration",    1, 15)
vl_sus_stew.register_sus_potion_effect("withering",       1, 8)
vl_sus_stew.register_sus_potion_effect("weakness",        1, 12)
vl_sus_stew.register_sus_potion_effect("night_vision",    1, 10)

vl_sus_stew.register_sus_stew("mcl_flowers:allium",             "fire_resistance")
vl_sus_stew.register_sus_stew("mcl_flowers:azure_bluet",        "blindness")
vl_sus_stew.register_sus_stew("mcl_flowers:lily_of_the_valley", "poison")
vl_sus_stew.register_sus_stew("mcl_flowers:blue_orchid",        "saturation")
vl_sus_stew.register_sus_stew("mcl_flowers:dandelion",          "saturation")
vl_sus_stew.register_sus_stew("mcl_flowers:cornflower",         "jump")
vl_sus_stew.register_sus_stew("mcl_flowers:oxeye_daisy",        "regeneration")
vl_sus_stew.register_sus_stew("mcl_flowers:poppy",              "night_vision")
vl_sus_stew.register_sus_stew("mcl_flowers:wither_rose",        "withering")
vl_sus_stew.register_sus_stew("mcl_flowers:tulip_orange",       "weakness")
vl_sus_stew.register_sus_stew("mcl_flowers:tulip_pink",         "weakness")
vl_sus_stew.register_sus_stew("mcl_flowers:tulip_red",          "weakness")
vl_sus_stew.register_sus_stew("mcl_flowers:tulip_white",        "weakness")
