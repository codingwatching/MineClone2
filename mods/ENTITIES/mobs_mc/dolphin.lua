--MCmobs v0.4
--maikerumine
--made for MC like Survival game
--License for code WTFPL and otherwise stated in readmes

local pi = math.pi
local atann = math.atan
local atan = function(x)
	if not x or x ~= x then
		return 0
	else
		return atann(x)
	end
end

local dir_to_pitch = function(dir)
	local dir2 = vector.normalize(dir)
	local xz = math.abs(dir.x) + math.abs(dir.z)
	return -math.atan2(-dir.y, xz)
end

local function degrees(rad)
	return rad * 180.0 / math.pi
end

local S = minetest.get_translator(minetest.get_current_modname())

--###################
--################### dolphin
--###################

local dolphin = {
	description = S("Dolphin"),
	type = "animal",
	spawn_class = "water",
	can_despawn = true,
	passive = true,
	initial_properties = {
		hp_min = 10,
		hp_max = 10,
		breath_max = 120,
		collisionbox = {-0.3, 0.0, -0.3, 0.3, 0.79, 0.3},
	},
	xp_min = 1,
	xp_max = 3,
	armor = 100,
	walk_chance = 100,
	rotate = 180,
	spawn_in_group_min = 2, -- was 3
	spawn_in_group = 4, -- was 4. nerfed until water has own cap, and it represents max pack size rather than per spawn attempt
	tilt_swim = true,
	visual = "mesh",
	mesh = "extra_mobs_dolphin.b3d",
	textures = {
		{"extra_mobs_dolphin.png"}
	},
	sounds = {
	},
	animation = {
		stand_start = 20,
		stand_end = 20,
		walk_start = 0,
		walk_end = 15,
		run_start = 30,
		run_end = 45,
		},
		drops = {
			{name = "mcl_fishing:fish_raw",
			chance = 1,
			min = 0,
			max = 1,},
	},
	visual_size = {x=3, y=3},
	makes_footstep_sound = false,
    fly = true,
    fly_in = { "mcl_core:water_source", "mclx_core:river_water_source" },
	breathes_in_water = true,
	jump = false,
	view_range = 16,
	fear_height = 4,
	walk_velocity = 3,
	run_velocity = 6,
	reach = 2,
	damage = 2.5,
	attack_type = "dogfight",
	--[[ this is supposed to make them jump out the water but doesn't appear to work very well
	do_custom = function(self,dtime)
		mcl_util.set_bone_position(self.object, "body", vector.new(0,1,0), vector.new(dir_to_pitch(self.object:get_velocity()) * -1 + math.pi/2,0,0))
		if minetest.get_item_group(self.standing_in, "water") ~= 0 then
			if self.object:get_velocity().y < 5 then
				self.object:add_velocity({ x = 0 , y = math.random()*.014-.007, z = 0 })
			end
		end
	end,
	--]]
}

mcl_mobs.register_mob("mobs_mc:dolphin", dolphin)


--spawning TO DO: in schools
mcl_mobs:spawn_setup({
	name = "mobs_mc:dolphin",
	dimension = "overworld",
	type_of_spawning = "water",
	biomes = {
		"Mesa",
		"FlowerForest",
		"Swampland",
		"Taiga",
		"ExtremeHills",
		"Jungle",
		"Savanna",
		"BirchForest",
		"MegaSpruceTaiga",
		"MegaTaiga",
		"ExtremeHills+",
		"Forest",
		"Plains",
		"Desert",
		"ColdTaiga",
		"MushroomIsland",
		"IcePlainsSpikes",
		"SunflowerPlains",
		"IcePlains",
		"RoofedForest",
		"ExtremeHills+_snowtop",
		"MesaPlateauFM_grasstop",
		"JungleEdgeM",
		"ExtremeHillsM",
		"JungleM",
		"BirchForestM",
		"MesaPlateauF",
		"MesaPlateauFM",
		"MesaPlateauF_grasstop",
		"MesaBryce",
		"JungleEdge",
		"SavannaM",
		"FlowerForest_beach",
		"Forest_beach",
		"StoneBeach",
		"Taiga_beach",
		"Savanna_beach",
		"Plains_beach",
		"ExtremeHills_beach",
		"ColdTaiga_beach",
		"Swampland_shore",
		"MushroomIslandShore",
		"JungleM_shore",
		"Jungle_shore",
		"MesaPlateauFM_sandlevel",
		"MesaPlateauF_sandlevel",
		"MesaBryce_sandlevel",
		"Mesa_sandlevel",
		"RoofedForest_ocean",
		"JungleEdgeM_ocean",
		"BirchForestM_ocean",
		"BirchForest_ocean",
		"IcePlains_deep_ocean",
		"Jungle_deep_ocean",
		"Savanna_ocean",
		"MesaPlateauF_ocean",
		"ExtremeHillsM_deep_ocean",
		"Savanna_deep_ocean",
		"SunflowerPlains_ocean",
		"Swampland_deep_ocean",
		"Swampland_ocean",
		"MegaSpruceTaiga_deep_ocean",
		"ExtremeHillsM_ocean",
		"JungleEdgeM_deep_ocean",
		"SunflowerPlains_deep_ocean",
		"BirchForest_deep_ocean",
		"IcePlainsSpikes_ocean",
		"Mesa_ocean",
		"StoneBeach_ocean",
		"Plains_deep_ocean",
		"JungleEdge_deep_ocean",
		"SavannaM_deep_ocean",
		"Desert_deep_ocean",
		"Mesa_deep_ocean",
		"ColdTaiga_deep_ocean",
		"Plains_ocean",
		"MesaPlateauFM_ocean",
		"Forest_deep_ocean",
		"JungleM_deep_ocean",
		"FlowerForest_deep_ocean",
		"MushroomIsland_ocean",
		"MegaTaiga_ocean",
		"StoneBeach_deep_ocean",
		"IcePlainsSpikes_deep_ocean",
		"ColdTaiga_ocean",
		"SavannaM_ocean",
		"MesaPlateauF_deep_ocean",
		"MesaBryce_deep_ocean",
		"ExtremeHills+_deep_ocean",
		"ExtremeHills_ocean",
		"MushroomIsland_deep_ocean",
		"Forest_ocean",
		"MegaTaiga_deep_ocean",
		"JungleEdge_ocean",
		"MesaBryce_ocean",
		"MegaSpruceTaiga_ocean",
		"ExtremeHills+_ocean",
		"Jungle_ocean",
		"RoofedForest_deep_ocean",
		"IcePlains_ocean",
		"FlowerForest_ocean",
		"ExtremeHills_deep_ocean",
		"MesaPlateauFM_deep_ocean",
		"Desert_ocean",
		"Taiga_ocean",
		"BirchForestM_deep_ocean",
		"Taiga_deep_ocean",
		"JungleM_ocean",
		"FlowerForest_underground",
		"JungleEdge_underground",
		"StoneBeach_underground",
		"MesaBryce_underground",
		"Mesa_underground",
		"RoofedForest_underground",
		"Jungle_underground",
		"Swampland_underground",
		"MushroomIsland_underground",
		"BirchForest_underground",
		"Plains_underground",
		"MesaPlateauF_underground",
		"ExtremeHills_underground",
		"MegaSpruceTaiga_underground",
		"BirchForestM_underground",
		"SavannaM_underground",
		"MesaPlateauFM_underground",
		"Desert_underground",
		"Savanna_underground",
		"Forest_underground",
		"SunflowerPlains_underground",
		"ColdTaiga_underground",
		"IcePlains_underground",
		"IcePlainsSpikes_underground",
		"MegaTaiga_underground",
		"Taiga_underground",
		"ExtremeHills+_underground",
		"JungleM_underground",
		"ExtremeHillsM_underground",
		"JungleEdgeM_underground",
	},
	min_light = 0,
	max_light = minetest.LIGHT_MAX+1,
	chance = 70,
	interval = 30,
	aoc = 3,
	min_height = mobs_mc.water_level - 16,
	max_height = mobs_mc.water_level + 1
})

--spawn egg
mcl_mobs.register_egg("mobs_mc:dolphin", S("Dolphin"), "#223b4d", "#f9f9f9", 0)
