-- Flint and Steel
minetest.register_tool("mcl_fire:flint_and_steel", {
	description = "Flint and Steel",
	inventory_image = "mcl_fire_flint_and_steel.png",
	liquids_pointable = false,
	stack_max = 1,
	groups = { tool = 1 },
	tool_capabilities = {
		full_punch_interval = 1.0,
		max_drop_level=0,
		groupcaps={
			flamable = {uses=65, maxlevel=1},
		}
	},
	on_use = function(itemstack, user, pointed_thing)
		if pointed_thing.type == "node" then
			if minetest.get_node(pointed_thing.under).name == "mcl_tnt:tnt" then
				tnt.ignite(pointed_thing.under)
			else
				mcl_core.set_fire(pointed_thing)
				itemstack:add_wear(66000/65) -- 65 uses
				return itemstack
			end
		end
	end,
})

minetest.register_craft({
	type = 'shapeless',
	output = 'mcl_core:flint_and_steel',
	recipe = { 'mcl_core:steel_ingot', 'mcl_core:flint'},
})
