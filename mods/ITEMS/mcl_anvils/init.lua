local anvildef = {
	groups = {pickaxey=1, falling_node=1, crush_after_fall=1, deco_block=1, anvil=1},
	tiles = {"mcl_anvils_anvil_top_damaged_0.png^[transformR90", "mcl_anvils_anvil_base.png", "mcl_anvils_anvil_side.png"},
	paramtype = "light",
	sunlight_propagates = true,
	is_ground_content = false,
	paramtype2 = "facedir",
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-8/16, 2/16, -5/16, 8/16, 8/16, 5/16}, --  top
			{-6/16, -4/16, -1/16, 6/16, 5/16, 1/16}, -- middle
			{-8/16, -8/16, -5/16, 8/16, -4/16, 5/16}, -- base
		}
	},
	sounds = mcl_sounds.node_sound_metal_defaults(),
	_mcl_blast_resistance = 6000,
	_mcl_hardness = 5,
	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		local inv = meta:get_inventory()
		inv:set_size("input1", 1)
		inv:set_size("input2", 1)
		inv:set_size("output", 1)
		local form = "size[9,8.75]"..
		"background[-0.19,-0.25;9.41,9.49;mcl_anvils_inventory.png]"..
		mcl_vars.inventory_header..
		"list[current_player;main;0,4.5;9,3;9]"..
		"list[current_player;main;0,7.74;9,1;]"..
		"list[context;input1;1,2.5;1,1;]"..
		"list[current_name;input2;4,2.5;1,1;]"..
		"list[current_name;output;8,2.5;1,1;]"..
		"listring[current_name;output]"..
		"listring[current_player;main]"..
		"listring[current_name;input1]"..
		"listring[current_player;main]"..
		"listring[current_name;input2]"..
		"listring[current_player;main]"
		meta:set_string("formspec", form)
	end,
}
if minetest.get_modpath("screwdriver") then
	anvildef.on_rotate = screwdriver.rotate_simple
end

local anvildef0 = table.copy(anvildef)
anvildef0.description = "Anvil"

local anvildef1 = table.copy(anvildef)
anvildef1.description = "Slightly Damaged Anvil"
anvildef1.groups.not_in_creative_inventory = 1
anvildef1._doc_items_create_entry = false
anvildef1.tiles = {"mcl_anvils_anvil_top_damaged_1.png^[transformR90", "mcl_anvils_anvil_base.png", "mcl_anvils_anvil_side.png"}

local anvildef2 = table.copy(anvildef)
anvildef2.description = "Very Damaged Anvil"
anvildef2.groups.not_in_creative_inventory = 1
anvildef2._doc_items_create_entry = false
anvildef2.tiles = {"mcl_anvils_anvil_top_damaged_2.png^[transformR90", "mcl_anvils_anvil_base.png", "mcl_anvils_anvil_side.png"}

minetest.register_node("mcl_anvils:anvil", anvildef0)
minetest.register_node("mcl_anvils:anvil_damage_1", anvildef1)
minetest.register_node("mcl_anvils:anvil_damage_2", anvildef2)

minetest.register_craft({
	output = "mcl_anvils:anvil",
	recipe = {
		{ "mcl_core:ironblock", "mcl_core:ironblock", "mcl_core:ironblock" },
		{ "", "mcl_core:iron_ingot", "" },
		{ "mcl_core:iron_ingot", "mcl_core:iron_ingot", "mcl_core:iron_ingot" },
	}
})

dofile(minetest.get_modpath(minetest.get_current_modname()).."/falling_anvil.lua")
