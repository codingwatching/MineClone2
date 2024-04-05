local modname = minetest.get_current_modname()
local mod = mcl_minecarts
local S = minetest.get_translator(modname)

local LOGGING_ON = minetest.settings:get_bool("mcl_logging_minecarts", false)
local DEBUG = false
local function mcl_log(message)
	if LOGGING_ON then
		mcl_util.mcl_log(message, "[Minecarts]", true)
	end
end

-- Import external functions
local table_merge = mcl_util.table_merge

-- Constants
local max_step_distance = 0.5
local friction = 0.4
local MINECART_MAX_HP = 4
local PASSENGER_ATTACH_POSITION = vector.new(0, -1.75, 0)

local function detach_minecart(self)
	local staticdata = self._staticdata

	staticdata.connected_at = nil
	self.object:set_velocity(staticdata.dir * staticdata.velocity)
end
local function try_detach_minecart(self)
	local staticdata = self._staticdata

	local node = minetest.get_node(staticdata.connected_at)
	if minetest.get_item_group(node.name, "rail") == 0 then
		detach_minecart(self)
	end
end

--[[
	Array of hooks { {u,v,w}, name }
	Actual position is pos + u * dir + v * right + w * up
]]
local enter_exit_checks = {
	{ 0, 0, 0, "" },
	{ 0, 0, 1, "_above" },
	{ 0, 0,-1, "_below" },
	{ 0, 1, 0, "_side" },
	{ 0,-1, 0, "_side" },
}

local function handle_cart_enter_exit(self, pos, next_dir, event)
	local staticdata = self._staticdata

	local dir = staticdata.dir
	local right = vector.new( dir.z, dir.y, -dir.x)
	local up = vector.new(0,1,0)
	for _,check in ipairs(enter_exit_checks) do
		local check_pos = pos + dir * check[1] + right * check[2] + up * check[3]
		local node = minetest.get_node(check_pos)
		local node_def = minetest.registered_nodes[node.name]

		-- node-specific hook
		local hook_name = "_mcl_minecarts_"..event..check[4]
		local hook = node_def[hook_name]
		if hook then hook(check_pos, self, next_dir, pos) end

		-- global minecart hook
		hook = mcl_minecarts[event..check[4]]
		if hook then hook(check_pos, self, next_dir, node_def) end
	end

	-- Handle cart-specific behaviors
	local hook = self["_mcl_minecarts_"..event]
	if hook then hook(self, pos) end
end
local function handle_cart_enter(self, pos, next_dir)
	handle_cart_enter_exit(self, pos, next_dir, "on_enter" )
end
local function handle_cart_leave(self, pos, next_dir)
	handle_cart_enter_exit(self, pos, next_dir, "on_leave" )
end

local function handle_cart_node_watches(self, dtime)
	local staticdata = self._staticdata
	local watches = staticdata.node_watches or {}
	local new_watches = {}
	for _,node_pos in ipairs(watches) do
		local node = minetest.get_node(node_pos)
		local node_def = minetest.registered_nodes[node.name]
		local hook = node_def._mcl_minecarts_node_on_step
		if hook and hook(node_pos, self, dtime) then
			new_watches[#new_watches+1] = node_pos
		end
	end

	staticdata.node_watches = new_watches
end

local function update_cart_orientation(self,staticdata)
	-- constants
	local _2_pi = math.pi * 2
	local pi = math.pi
	local dir = staticdata.dir

	-- Calculate an angle from the x,z direction components
	local rot_y = math.atan2( dir.x, dir.z ) + ( staticdata.rot_adjust or 0 )
	if rot_y < 0 then
		rot_y = rot_y + _2_pi
	end

	-- Check if the rotation is a 180 flip and don't change if so
	local rot = self.object:get_rotation()
	local diff = math.abs((rot_y - ( rot.y + pi ) % _2_pi) )
	if diff < 0.001 or diff > _2_pi - 0.001 then
		-- Update rotation adjust and recalculate the rotation
		staticdata.rot_adjust = ( ( staticdata.rot_adjust or 0 ) + pi ) % _2_pi
		rot.y = math.atan2( dir.x, dir.z ) + ( staticdata.rot_adjust or 0 )
	else
		rot.y = rot_y
	end

	-- Forward/backwards tilt (pitch)
	if dir.y < 0 then
		rot.x = -0.25 * pi
	elseif dir.y > 0 then
		rot.x = 0.25 * pi
	else
		rot.x = 0
	end

	if ( staticdata.rot_adjust or 0 ) < 0.01 then
		rot.x = -rot.x
	end
	if dir.z ~= 0 then
		rot.x = -rot.x
	end

	self.object:set_rotation(rot)
end

local function direction_away_from_players(self, staticdata)
	local objs = minetest.get_objects_inside_radius(self.object:get_pos(), 1.1)
	for n=1,#objs do
		local obj = objs[n]
		local player_name = obj:get_player_name()
		if player_name and player_name ~= "" and not ( self._driver and self._driver == player_name ) then
			local diff = obj:get_pos() - self.object:get_pos()

			local length = vector.distance(vector.new(0,0,0),diff)
			local vec = diff / length
			local force = vector.dot( vec, vector.normalize(staticdata.dir) )

			-- Check if this would push past the end of the track and don't move it it would
			-- This prevents an oscillation that would otherwise occur
			local dir = staticdata.dir
			if force > 0 then
				dir = -dir
			end
			if mcl_minecarts:is_rail( staticdata.connected_at + dir ) then
				if force > 0.5 then
					return -length * 4
				elseif force < -0.5 then
					return length * 4
				end
			end
		end
	end

	return 0
end

local function calculate_acceleration(self, staticdata)
	local acceleration = 0

	-- Fix up movement data
	staticdata.velocity = staticdata.velocity or 0

	-- Apply friction if moving
	if staticdata.velocity > 0 then
		acceleration = -friction
	end

	local pos = staticdata.connected_at
	local node_name = minetest.get_node(pos).name
	local node_def = minetest.registered_nodes[node_name]
	local max_vel = mcl_minecarts.speed_max

	if self._go_forward then
		acceleration = 4
	elseif self._brake then
		acceleration = -1.5
	elseif (staticdata.fueltime or 0) > 0 and staticdata.velocity <= 4 then
		acceleration = 0.6
	elseif staticdata.velocity >= ( node_def._max_acceleration_velocity or max_vel ) then
		-- Standard friction
	else
		if node_def._rail_acceleration then
			acceleration = node_def._rail_acceleration * 4
		end
	end

	-- Factor in gravity after everything else
	local gravity_strength = 2.45 --friction * 5
	if staticdata.dir.y < 0 then
		acceleration = gravity_strength - friction
	elseif staticdata.dir.y > 0 then
		acceleration = -gravity_strength + friction
	end

	return acceleration
end

local function reverse_direction(self, staticdata)
	-- Complete moving thru this block into the next, reverse direction, and put us back at the same position we were at
	local next_dir = -staticdata.dir
	staticdata.connected_at = staticdata.connected_at + staticdata.dir
	staticdata.distance = 1 - staticdata.distance

	-- recalculate direction
	local next_dir,_ = mcl_minecarts:get_rail_direction(staticdata.connected_at, next_dir, nil, nil, staticdata.railtype)
	staticdata.dir = next_dir
end

local function do_movement_step(self, dtime)
	local staticdata = self._staticdata
	if not staticdata.connected_at then return 0 end

	-- Calculate timestep remaiing in this block
	local x_0 = staticdata.distance or 0
	local remaining_in_block = 1 - x_0
	local a = calculate_acceleration(self, staticdata)
	local v_0 = staticdata.velocity

	-- Repel minecarts
	local away = direction_away_from_players(self, staticdata)
	if away > 0 then
		v_0 = away
	elseif away < 0 then
		reverse_direction(self, staticdata)
		v_0 = -away
	end

	if DEBUG and ( v_0 > 0 or a ~= 0 ) then
		print( "    cart #"..tostring(staticdata.cart_id)..
		       ": a="..tostring(a)..
		        ",v_0="..tostring(v_0)..
		        ",x_0="..tostring(x_0)..
		        ",timestep="..tostring(timestep)..
		        ",dir="..tostring(staticdata.dir)..
			",connected_at="..tostring(staticdata.connected_at)..
			",distance="..tostring(staticdata.distance)
		)
	end

	-- Not moving
	if a == 0 and v_0 == 0 then return 0 end

	-- Movement equation with acceleration: x_1 = x_0 + v_0 * t + 0.5 * a * t*t
	local timestep
	local stops_in_block = false
	local inside = v_0 * v_0 + 2 * a * remaining_in_block
	if inside < 0 then
		-- Would stop or reverse direction inside this block, calculate time to v_1 = 0
		timestep = -v_0 / a
		stops_in_block = true
	elseif a ~= 0 then
		-- Setting x_1 = x_0 + remaining_in_block, and solving for t gives:
		timestep = ( math.sqrt( v_0 * v_0 + 2 * a * remaining_in_block) - v_0 ) / a
	else
		timestep = remaining_in_block / v_0
	end

	-- Truncate timestep to remaining time delta
	if timestep > dtime then
		timestep = dtime
	end

	-- Truncate timestep to prevent v_1 from being larger that speed_max
	local v_max = mcl_minecarts.speed_max
	if (v_0 ~= v_max) and ( v_0 + a * timestep > v_max) then
		timestep = ( v_max - v_0 ) / a
	end

	-- Prevent infinite loops
	if timestep <= 0 then return 0 end

	-- Calculate v_1 taking v_max into account
	local v_1 = v_0 + a * timestep
	if v_1 > v_max then
		v_1 = v_max
	elseif v_1 < friction / 5 then
		v_1 = 0
	end

	-- Calculate x_1
	local x_1 = x_0 + timestep * v_0 + 0.5 * a * timestep * timestep

	-- Update position and velocity of the minecart
	staticdata.velocity = v_1
	staticdata.distance = x_1

	if DEBUG and (1==0) and ( v_0 > 0 or a ~= 0 ) then
		print( "-   cart #"..tostring(staticdata.cart_id)..
		       ": a="..tostring(a)..
		        ",v_0="..tostring(v_0)..
		        ",v_1="..tostring(v_1)..
		        ",x_0="..tostring(x_0)..
		        ",x_1="..tostring(x_1)..
		        ",timestep="..tostring(timestep)..
		        ",dir="..tostring(staticdata.dir)..
			",connected_at="..tostring(staticdata.connected_at)..
			",distance="..tostring(staticdata.distance)
		)
	end


	-- Entity movement
	local pos = staticdata.connected_at

	-- Handle movement to next block, account for loss of precision in calculations
	if x_1 >= 0.99 then
		staticdata.distance = 0

		-- Anchor at the next node
		local old_pos = pos
		pos = pos + staticdata.dir
		staticdata.connected_at = pos

		-- Get the next direction
		local next_dir,_ = mcl_minecarts:get_rail_direction(pos, staticdata.dir, nil, nil, staticdata.railtype)
		if DEBUG and next_dir ~= staticdata.dir then
			print( "Changing direction from "..tostring(staticdata.dir).." to "..tostring(next_dir))
		end

		-- Leave the old node
		handle_cart_leave(self, old_pos, next_dir )

		-- Enter the new node
		handle_cart_enter(self, pos, next_dir)

		try_detach_minecart(self)

		-- Handle end of track
		if next_dir == staticdata.dir * -1 and next_dir.y == 0 then
			if DEBUG then print("Stopping cart at end of track at "..tostring(pos)) end
			staticdata.velocity = 0
		end

		-- Update cart direction
		staticdata.dir = next_dir
	elseif stops_in_block and v_1 < (friction/5) and a <= 0 then
		-- Handle direction flip due to gravity
		if DEBUG then print("Gravity flipped direction") end

		-- Velocity should be zero at this point
		staticdata.velocity = 0

		reverse_direction(self, staticdata)

		-- Intermediate movement
		pos = staticdata.connected_at + staticdata.dir * staticdata.distance
	else
		-- Intermediate movement
		pos = pos + staticdata.dir * staticdata.distance
	end

	self.object:move_to(pos)

	-- Update cart orientation
	update_cart_orientation(self,staticdata)

	-- Debug reporting
	if DEBUG and ( v_0 > 0 or v_1 > 0 ) then
		print( "    cart #"..tostring(staticdata.cart_id)..
		       ": a="..tostring(a)..
		        ",v_0="..tostring(v_0)..
		        ",v_1="..tostring(v_1)..
		        ",x_0="..tostring(x_0)..
		        ",x_1="..tostring(x_1)..
		        ",timestep="..tostring(timestep)..
		        ",dir="..tostring(staticdata.dir)..
			",pos="..tostring(pos)..
			",connected_at="..tostring(staticdata.connected_at)..
			",distance="..tostring(staticdata.distance)
		)
	end

	-- Report the amount of time processed
	return dtime - timestep
end

local function do_movement( self, dtime )
	local staticdata = self._staticdata

	-- Allow the carts to be delay for the rest of the world to react before moving again
	if ( staticdata.delay or 0 ) > dtime then
		staticdata.delay = staticdata.delay - dtime
		return
	else
		staticdata.delay = 0
	end

	-- Break long movements at block boundaries to make it
	-- it impossible to jump across gaps due to server lag
	-- causing large timesteps
	while dtime > 0 do
		local new_dtime = do_movement_step(self, dtime)

		-- Handle node watches here in steps to prevent server lag from changing behavior
		handle_cart_node_watches(self, dtime - new_dtime)

		dtime = new_dtime
	end
end

local function do_detached_movement(self, dtime)
	local staticdata = self._staticdata

	-- Apply physics
	if mcl_physics then
		mcl_physics.apply_entity_environmental_physics(self)
	else
		-- Simple physics
		local friction = self.object:get_velocity()
		friction.y = 0

		local accel = vector.new(0,-9.81,0) -- gravity
		accel = vector.add(accel, vector.multiply(friction,-0.9))
		self.object:set_acceleration(accel)
	end

	-- Try to reconnect to rail
	local pos_r = vector.round(self.object:get_pos())
	local node = minetest.get_node(pos_r)
	if minetest.get_item_group(node.name, "rail") ~= 0 then
		staticdata.connected_at = pos_r
		staticdata.railtype = node.name

		local freebody_velocity = self.object:get_velocity()
		staticdata.dir = mod:get_rail_direction(pos_r, mod.snap_direction(freebody_velocity))

		-- Use vector projection to only keep the velocity in the new direction of movement on the rail
		-- https://en.wikipedia.org/wiki/Vector_projection
		staticdata.velocity = vector.dot(staticdata.dir,freebody_velocity)

		-- Clear freebody movement
		self.object:set_velocity(vector.new(0,0,0))
		self.object:set_acceleration(vector.new(0,0,0))
	end
end

local function detach_driver(self)
	if not self._driver then
		return
	end
	mcl_player.player_attached[self._driver] = nil
	local player = minetest.get_player_by_name(self._driver)
	self._driver = nil
	self._start_pos = nil
	if player then
		player:set_detach()
		player:set_eye_offset(vector.new(0,0,0),vector.new(0,0,0))
		mcl_player.player_set_animation(player, "stand" , 30)
	end
end

local function activate_normal_minecart(self)
	detach_driver(self)

	-- Detach passenger
	if self._passenger then
		local mob = self._passenger.object
		mob:set_detach()
	end
end

local function hopper_take_item(self, dtime)
	local pos = self.object:get_pos()
	if not pos then return end

	if not self or self.name ~= "mcl_minecarts:hopper_minecart" then return end

	if mcl_util.check_dtime_timer(self, dtime, "hoppermc_take", 0.15) then
		--minetest.log("The check timer was triggered: " .. dump(pos) .. ", name:" .. self.name)
	else
		--minetest.log("The check timer was not triggered")
		return
	end


	local above_pos = vector.offset(pos, 0, 0.9, 0)
	local objs = minetest.get_objects_inside_radius(above_pos, 1.25)

	if objs then
		mcl_log("there is an itemstring. Number of objs: ".. #objs)

		for k, v in pairs(objs) do
			local ent = v:get_luaentity()

			if ent and not ent._removed and ent.itemstring and ent.itemstring ~= "" then
				local taken_items = false

				mcl_log("ent.name: " .. tostring(ent.name))
				mcl_log("ent pos: " .. tostring(ent.object:get_pos()))

				local inv = mcl_entity_invs.load_inv(self, 5)
				if not inv then return false end

				local current_itemstack = ItemStack(ent.itemstring)

				mcl_log("inv. size: " .. self._inv_size)
				if inv:room_for_item("main", current_itemstack) then
					mcl_log("Room")
					inv:add_item("main", current_itemstack)
					ent.object:get_luaentity().itemstring = ""
					ent.object:remove()
					taken_items = true
				else
					mcl_log("no Room")
				end

				if not taken_items then
					local items_remaining = current_itemstack:get_count()

					-- This will take part of a floating item stack if no slot can hold the full amount
					for i = 1, self._inv_size, 1 do
						local stack = inv:get_stack("main", i)

						mcl_log("i: " .. tostring(i))
						mcl_log("Items remaining: " .. items_remaining)
						mcl_log("Name: " .. tostring(stack:get_name()))

						if current_itemstack:get_name() == stack:get_name() then
							mcl_log("We have a match. Name: " .. tostring(stack:get_name()))

							local room_for = stack:get_stack_max() - stack:get_count()
							mcl_log("Room for: " .. tostring(room_for))

							if room_for == 0 then
								-- Do nothing
								mcl_log("No room")
							elseif room_for < items_remaining then
								mcl_log("We have more items remaining than space")

								items_remaining = items_remaining - room_for
								stack:set_count(stack:get_stack_max())
								inv:set_stack("main", i, stack)
								taken_items = true
							else
								local new_stack_size = stack:get_count() + items_remaining
								stack:set_count(new_stack_size)
								mcl_log("We have more than enough space. Now holds: " .. new_stack_size)

								inv:set_stack("main", i, stack)
								items_remaining = 0

								ent.object:get_luaentity().itemstring = ""
								ent.object:remove()

								taken_items = true
								break
							end

							mcl_log("Count: " .. tostring(stack:get_count()))
							mcl_log("stack max: " .. tostring(stack:get_stack_max()))
							--mcl_log("Is it empty: " .. stack:to_string())
						end

						if i == self._inv_size and taken_items then
							mcl_log("We are on last item and still have items left. Set final stack size: " .. items_remaining)
							current_itemstack:set_count(items_remaining)
							--mcl_log("Itemstack2: " .. current_itemstack:to_string())
							ent.itemstring = current_itemstack:to_string()
						end
					end
				end

				--Add in, and delete
				if taken_items then
					mcl_log("Saving")
					mcl_entity_invs.save_inv(ent)
					return taken_items
				else
					mcl_log("No need to save")
				end

			end
		end
	end

	return false
end

-- Table for item-to-entity mapping. Keys: itemstring, Values: Corresponding entity ID
local entity_mapping = {}

local function make_staticdata( railtype, connected_at, dir )
	return {
		railtype = railtype,
		connected_at = connected_at,
		distance = 0,
		velocity = 0,
		dir = vector.new(dir),
		cart_id = math.random(1,1000000000),
	}
end

local DEFAULT_CART_DEF = {
	initial_properties = {
		physical = true,
		collisionbox = {-10/16., -0.5, -10/16, 10/16, 0.25, 10/16},
		visual = "mesh",
		visual_size = {x=1, y=1},
	},

	hp_max = MINECART_MAX_HP,

	groups = {
		minecart = 1,
	},

	_driver = nil, -- player who sits in and controls the minecart (only for minecart!)
	_passenger = nil, -- for mobs
	_start_pos = nil, -- Used to calculate distance for “On A Rail” achievement
	_last_float_check = nil, -- timestamp of last time the cart was checked to be still on a rail
	_boomtimer = nil, -- how many seconds are left before exploding
	_blinktimer = nil, -- how many seconds are left before TNT blinking
	_blink = false, -- is TNT blink texture active?
	_old_pos = nil,
	_staticdata = nil,
}
function DEFAULT_CART_DEF:on_activate(staticdata, dtime_s)
	-- Initialize
	local data = minetest.deserialize(staticdata)
	if type(data) == "table" then
		-- Migrate old data
		if data._railtype then
			data.railtype = data._railtype
			data._railtype = nil
		end
		-- Fix up types
		data.dir = vector.new(data.dir)

		-- Make sure all carts have an ID to isolate them
		data.cart_id = staticdata.cart_id or math.random(1,1000000000)

		self._staticdata = data
	end

	-- Activate cart if on activator rail
	if self.on_activate_by_rail then
		local pos = self.object:get_pos()
		local node = minetest.get_node(vector.floor(pos))
		if node.name == "mcl_minecarts:activator_rail_on" then
			self:on_activate_by_rail()
		end
	end
end
function DEFAULT_CART_DEF:add_node_watch(pos)
	local staticdata = self._staticdata
	local watches = staticdata.node_watches or {}

	for _,watch in ipairs(watches) do
		if watch == pos then return end
	end

	watches[#watches+1] = pos
	staticdata.node_watches = watches
end
function DEFAULT_CART_DEF:remove_node_watch(pos)
	local staticdata = self._staticdata
	local watches = staticdata.node_watches or {}

	local new_watches = {}
	for _,node_pos in ipairs(watches) do
		if node_pos ~= pos then
			new_watches[#new_watches] = node_pos
		end
	end
	staticdata.node_watches = new_watches
end
function DEFAULT_CART_DEF:get_staticdata()
	return minetest.serialize(self._staticdata or {})
end
function DEFAULT_CART_DEF:on_step(dtime)
	local staticdata = self._staticdata
	if not staticdata then
		staticdata = make_staticdata()
		self._staticdata = staticdata
	end

	-- Regen
	local hp = self.object:get_hp()
	if hp < MINECART_MAX_HP then
		if (staticdata.regen_timer or 0) > 0.5 then
			hp = hp + 1
			staticdata.regen_timer = staticdata.regen_timer - 1
		end
		staticdata.regen_timer = (staticdata.regen_timer or 0) + dtime
		self.object:set_hp(hp)
	else
		staticdata.regen_timer = nil
	end

	-- Fix railtype field
	local pos = self.object:get_pos()
	if staticdata.connected_at and not staticdata.railtype then
		local node = minetest.get_node(vector.floor(pos)).name
		staticdata.railtype = minetest.get_item_group(node, "connect_to_raillike")
	end

	-- Cart specific behaviors
	local hook = self._mcl_minecarts_on_step
	if hook then hook(self,dtime) end

	if (staticdata.hopper_delay or 0) > 0 then
		staticdata.hopper_delay = staticdata.hopper_delay - dtime
	end

	-- Controls
	local ctrl, player = nil, nil
	if self._driver then
		player = minetest.get_player_by_name(self._driver)
		if player then
			ctrl = player:get_player_control()
			-- player detach
			if ctrl.sneak then
				detach_driver(self)
				return
			end

			-- Experimental controls
			self._go_forward = ctrl.up
			self._brake = ctrl.down
		end

		-- Give achievement when player reached a distance of 1000 nodes from the start position
		if vector.distance(self._start_pos, pos) >= 1000 then
			awards.unlock(self._driver, "mcl:onARail")
		end
	end

	if staticdata.connected_at then
		do_movement(self, dtime)
	else
		do_detached_movement(self, dtime)
	end

	-- TODO: move this into mcl_core:cactus _mcl_minecarts_on_enter_side
	-- Drop minecart if it collides with a cactus node
	local r = 0.6
	for _, node_pos in pairs({{r, 0}, {0, r}, {-r, 0}, {0, -r}}) do
		if minetest.get_node(vector.offset(pos, node_pos[1], 0, node_pos[2])).name == "mcl_core:cactus" then
			detach_driver(self)
			local drop = self.drop
			for d = 1, #drop do
				minetest.add_item(pos, drop[d])
			end
			self.object:remove()
			return
		end
	end
end
function DEFAULT_CART_DEF:on_death(killer)
	local staticdata = self._staticdata
	detach_driver(self)

	-- Detach passenger
	if self._passenger then
		local mob = self._passenger.object
		mob:set_detach()
	end

	-- Leave nodes
	if staticdata.attached_at then
		handle_cart_leave(self, staticdata.attached_at, staticdata.dir )
	else
		mcl_log("TODO: handle detatched minecart death")
	end

	-- Drop items
	local drop = self.drop
	if not killer or not minetest.is_creative_enabled(killer:get_player_name()) then
		for d=1, #drop do
			minetest.add_item(self.object:get_pos(), drop[d])
		end
	elseif killer and killer:is_player() then
		local inv = killer:get_inventory()
		for d=1, #drop do
			if not inv:contains_item("main", drop[d]) then
				inv:add_item("main", drop[d])
			end
		end
	end
end

-- Place a minecart at pointed_thing
function mcl_minecarts.place_minecart(itemstack, pointed_thing, placer)
	if not pointed_thing.type == "node" then
		return
	end

	local railpos, node
	if mcl_minecarts:is_rail(pointed_thing.under) then
		railpos = pointed_thing.under
		node = minetest.get_node(pointed_thing.under)
	elseif mcl_minecarts:is_rail(pointed_thing.above) then
		railpos = pointed_thing.above
		node = minetest.get_node(pointed_thing.above)
	else
		return
	end

	local entity_id = entity_mapping[itemstack:get_name()]
	local cart = minetest.add_entity(railpos, entity_id)
	local railtype = minetest.get_item_group(node.name, "connect_to_raillike")
	local cart_dir = mcl_minecarts:get_rail_direction(railpos, vector.new(1,0,0), nil, nil, railtype)
	cart:set_yaw(minetest.dir_to_yaw(cart_dir))

	-- Update static data
	local le = cart:get_luaentity()
	if le then
		le._staticdata = make_staticdata( railtype, railpos, cart_dir )
	end

	-- Call placer
	if le._mcl_minecarts_on_place then
		le._mcl_minecarts_on_place(le, placer)
	end

	handle_cart_enter(le, railpos)

	local pname = ""
	if placer then
		pname = placer:get_player_name()
	end
	if not minetest.is_creative_enabled(pname) then
		itemstack:take_item()
	end
	return itemstack
end

local function dropper_place_minecart(dropitem, pos)
	local node = minetest.get_node(pos)
	local nodedef = minetest.registered_nodes[node.name]

	-- Don't try to place the minecart if pos isn't a rail
	if (nodedef.groups.rail or 0) == 0 then return false end

	mcl_minecarts.place_minecart(dropitem, {
		above = pos,
		under = vector.offset(pos,0,-1,0)
	})
	return true
end

local function register_minecart_craftitem(itemstring, def)
	local groups = { minecart = 1, transport = 1 }
	if def.creative == false then
		groups.not_in_creative_inventory = 1
	end
	local item_def = {
		stack_max = 1,
		_mcl_dropper_on_drop = dropper_place_minecart,
		on_place = function(itemstack, placer, pointed_thing)
			if not pointed_thing.type == "node" then
				return
			end

			-- Call on_rightclick if the pointed node defines it
			local node = minetest.get_node(pointed_thing.under)
			if placer and not placer:get_player_control().sneak then
				if minetest.registered_nodes[node.name] and minetest.registered_nodes[node.name].on_rightclick then
					return minetest.registered_nodes[node.name].on_rightclick(pointed_thing.under, node, placer, itemstack) or itemstack
				end
			end

			return mcl_minecarts.place_minecart(itemstack, pointed_thing, placer)
		end,
		_on_dispense = function(stack, pos, droppos, dropnode, dropdir)
			-- Place minecart as entity on rail. If there's no rail, just drop it.
			local placed
			if minetest.get_item_group(dropnode.name, "rail") ~= 0 then
				-- FIXME: This places minecarts even if the spot is already occupied
				local pointed_thing = { under = droppos, above = vector.new( droppos.x, droppos.y+1, droppos.z ) }
				placed = mcl_minecarts.place_minecart(stack, pointed_thing)
			end
			if placed == nil then
				-- Drop item
				minetest.add_item(droppos, stack)
			end
		end,
		groups = groups,
	}
	item_def.description = def.description
	item_def._tt_help = def.tt_help
	item_def._doc_items_longdesc = def.longdesc
	item_def._doc_items_usagehelp = def.usagehelp
	item_def.inventory_image = def.icon
	item_def.wield_image = def.icon
	minetest.register_craftitem(itemstring, item_def)
end

--[[
Register a minecart
* itemstring: Itemstring of minecart item
* entity_id: ID of minecart entity
* description: Item name / description
* longdesc: Long help text
* usagehelp: Usage help text
* mesh: Minecart mesh
* textures: Minecart textures table
* icon: Item icon
* drop: Dropped items after destroying minecart
* on_rightclick: Called after rightclick
* on_activate_by_rail: Called when above activator rail
* creative: If false, don't show in Creative Inventory
]]
local function register_minecart(def)
	assert( def.drop, "def.drop is required parameter" )
	assert( def.itemstring, "def.itemstring is required parameter" )

	local entity_id = def.entity_id; def.entity_id = nil
	local craft = def.craft; def.craft = nil
	local itemstring = def.itemstring; def.itemstring = nil

	-- Build cart definition
	local cart = table.copy(DEFAULT_CART_DEF)
	table_merge(cart, def)
	minetest.register_entity(entity_id, cart)

	-- Register item to entity mapping
	entity_mapping[itemstring] = entity_id

	register_minecart_craftitem(itemstring, def)
	if minetest.get_modpath("doc_identifier") then
		doc.sub.identifier.register_object(entity_id, "craftitems", itemstring)
	end

	if craft then
		minetest.register_craft(craft)
	end
end

-- Minecart
register_minecart({
	itemstring = "mcl_minecarts:minecart",
	craft = {
		output = "mcl_minecarts:minecart",
		recipe = {
			{"mcl_core:iron_ingot", "", "mcl_core:iron_ingot"},
			{"mcl_core:iron_ingot", "mcl_core:iron_ingot", "mcl_core:iron_ingot"},
		},
	},
	entity_id = "mcl_minecarts:minecart",
	description = S("Minecart"),
	tt_helop = S("Vehicle for fast travel on rails"),
	long_descp = S("Minecarts can be used for a quick transportion on rails.") .. "\n" ..
		S("Minecarts only ride on rails and always follow the tracks. At a T-junction with no straight way ahead, they turn left. The speed is affected by the rail type."),
		S("You can place the minecart on rails. Right-click it to enter it. Punch it to get it moving.") .. "\n" ..
		S("To obtain the minecart, punch it while holding down the sneak key.") .. "\n" ..
		S("If it moves over a powered activator rail, you'll get ejected."),
	initial_properties = {
		mesh = "mcl_minecarts_minecart.b3d",
		textures = {"mcl_minecarts_minecart.png"},
	},
	icon = "mcl_minecarts_minecart_normal.png",
	drop = {"mcl_minecarts:minecart"},
	on_rightclick = function(self, clicker)
		local name = clicker:get_player_name()
		if not clicker or not clicker:is_player() then
			return
		end
		local player_name = clicker:get_player_name()
		if self._driver and player_name == self._driver then
			--detach_driver(self)
		elseif not self._driver and not clicker:get_player_control().sneak then
			self._driver = player_name
			self._start_pos = self.object:get_pos()
			mcl_player.player_attached[player_name] = true
			clicker:set_attach(self.object, "", vector.new(1,-1.75,-2), vector.new(0,0,0))
			mcl_player.player_attached[name] = true
			minetest.after(0.2, function(name)
				local player = minetest.get_player_by_name(name)
				if player then
					mcl_player.player_set_animation(player, "sit" , 30)
					player:set_eye_offset(vector.new(0,-5.5,0), vector.new(0,-4,0))
					mcl_title.set(clicker, "actionbar", {text=S("Sneak to dismount"), color="white", stay=60})
				end
			end, name)
		end
	end,
	on_activate_by_rail = activate_normal_minecart,
	_mcl_minecarts_on_step = function(self, dtime)
		-- Grab mob
		if math.random(1,20) > 15 and not self._passenger then
			local mobsnear = minetest.get_objects_inside_radius(self.object:get_pos(), 1.3)
			for n=1, #mobsnear do
				local mob = mobsnear[n]
				if mob then
					local entity = mob:get_luaentity()
					if entity and entity.is_mob then
						self._passenger = entity
						mob:set_attach(self.object, "", PASSENGER_ATTACH_POSITION, vector.zero())
						break
					end
				end
			end
		elseif self._passenger then
			local passenger_pos = self._passenger.object:get_pos()
			if not passenger_pos then
				self._passenger = nil
			end
		end
	end
})

-- Minecart with Chest
register_minecart({
	itemstring = "mcl_minecarts:chest_minecart",
	craft = {
		output = "mcl_minecarts:chest_minecart",
		recipe = {
			{"mcl_chests:chest"},
			{"mcl_minecarts:minecart"},
		},
	},
	entity_id = "mcl_minecarts:chest_minecart",
	description = S("Minecart with Chest"),
	tt_help = nil,
	longdesc = nil,
	usagehelp = nil,
	initial_properties = {
		mesh = "mcl_minecarts_minecart_chest.b3d",
		textures = {
			"mcl_chests_normal.png",
			"mcl_minecarts_minecart.png"
		},
	},
	icon = "mcl_minecarts_minecart_chest.png",
	drop = {"mcl_minecarts:minecart", "mcl_chests:chest"},
	groups = { container = 1 },
	on_rightclick = nil,
	on_activate_by_rail = nil,
	creative = true
})
mcl_entity_invs.register_inv("mcl_minecarts:chest_minecart","Minecart",27,false,true)

-- Minecart with Furnace
register_minecart({
	itemstring = "mcl_minecarts:furnace_minecart",
	craft = {
		output = "mcl_minecarts:furnace_minecart",
		recipe = {
			{"mcl_furnaces:furnace"},
			{"mcl_minecarts:minecart"},
		},
	},
	entity_id = "mcl_minecarts:furnace_minecart",
	description = S("Minecart with Furnace"),
	tt_help = nil,
	longdesc = S("A minecart with furnace is a vehicle that travels on rails. It can propel itself with fuel."),
	usagehelp = S("Place it on rails. If you give it some coal, the furnace will start burning for a long time and the minecart will be able to move itself. Punch it to get it moving.") .. "\n" ..
		S("To obtain the minecart and furnace, punch them while holding down the sneak key."),

	initial_properties = {
		mesh = "mcl_minecarts_minecart_block.b3d",
		textures = {
			"default_furnace_top.png",
			"default_furnace_top.png",
			"default_furnace_front.png",
			"default_furnace_side.png",
			"default_furnace_side.png",
			"default_furnace_side.png",
			"mcl_minecarts_minecart.png",
		},
	},
	icon = "mcl_minecarts_minecart_furnace.png",
	drop = {"mcl_minecarts:minecart", "mcl_furnaces:furnace"},
	on_rightclick = function(self, clicker)
		local staticdata = self._staticdata

		-- Feed furnace with coal
		if not clicker or not clicker:is_player() then
			return
		end
		local held = clicker:get_wielded_item()
		if minetest.get_item_group(held:get_name(), "coal") == 1 then
			staticdata.fueltime = (staticdata.fueltime or 0) + 180

			-- Trucate to 27 minutes (9 uses)
			if staticdata.fueltime > 27*60 then
				staticdata.fuel_time = 27*60
			end

			if not minetest.is_creative_enabled(clicker:get_player_name()) then
				held:take_item()
				local index = clicker:get_wield_index()
				local inv = clicker:get_inventory()
				inv:set_stack("main", index, held)
			end
			self.object:set_properties({textures =
			{
				"default_furnace_top.png",
				"default_furnace_top.png",
				"default_furnace_front_active.png",
				"default_furnace_side.png",
				"default_furnace_side.png",
				"default_furnace_side.png",
				"mcl_minecarts_minecart.png",
			}})
		end
	end,
	on_activate_by_rail = nil,
	creative = true,
	_mcl_minecarts_on_step = function(self, dtime)
		local staticdata = self._staticdata

		-- Update furnace stuff
		if (staticdata.fueltime or 0) > 0 then
			staticdata.fueltime = (staticdata.fueltime or dtime) - dtime
			if staticdata.fueltime <= 0 then
				self.object:set_properties({textures =
					{
					"default_furnace_top.png",
					"default_furnace_top.png",
					"default_furnace_front.png",
					"default_furnace_side.png",
					"default_furnace_side.png",
					"default_furnace_side.png",
					"mcl_minecarts_minecart.png",
				}})
				staticdata.fueltime = 0
			end
		end
	end
})
function table_metadata(table)
	return {
		table = table,
		set_string = function(self, key, value)
			--print("set_string("..tostring(key)..", "..tostring(value)..")")
			self.table[key] = tostring(value)
		end,
		get_string = function(self, key)
			if self.table[key] then
				return tostring(self.table[key])
			end
		end
	}
end

-- Minecart with Command Block
register_minecart({
	itemstring = "mcl_minecarts:command_block_minecart",
	entity_id = "mcl_minecarts:command_block_minecart",
	description = S("Minecart with Command Block"),
	tt_help = nil,
	loncdesc = nil,
	usagehelp = nil,
	initial_properties = {
		mesh = "mcl_minecarts_minecart_block.b3d",
		textures = {
			"jeija_commandblock_off.png^[verticalframe:2:0",
			"jeija_commandblock_off.png^[verticalframe:2:0",
			"jeija_commandblock_off.png^[verticalframe:2:0",
			"jeija_commandblock_off.png^[verticalframe:2:0",
			"jeija_commandblock_off.png^[verticalframe:2:0",
			"jeija_commandblock_off.png^[verticalframe:2:0",
			"mcl_minecarts_minecart.png",
		},
	},
	icon = "mcl_minecarts_minecart_command_block.png",
	drop = {"mcl_minecarts:minecart"},
	on_rightclick = function(self, clicker)
		self._staticdata.meta = self._staticdata.meta or {}
		local meta = table_metadata(self._staticdata.meta)

		mesecon.commandblock.handle_rightclick(meta, clicker)
	end,
	_mcl_minecarts_on_place = function(self, placer)
		-- Create a fake metadata object that stores into the cart's staticdata
		self._staticdata.meta = self._staticdata.meta or {}
		local meta = table_metadata(self._staticdata.meta)

		mesecon.commandblock.initialize(meta)
		mesecon.commandblock.place(meta, placer)
	end,
	on_activate_by_rail = function(self, timer)
		self._staticdata.meta = self._staticdata.meta or {}
		local meta = table_metadata(self._staticdata.meta)

		mesecon.commandblock.action_on(meta, self.object:get_pos())
	end,
	creative = true
})

-- Minecart with Hopper
register_minecart({
	itemstring = "mcl_minecarts:hopper_minecart",
	craft = {
		output = "mcl_minecarts:hopper_minecart",
		recipe = {
			{"mcl_hoppers:hopper"},
			{"mcl_minecarts:minecart"},
		},
	},
	entity_id = "mcl_minecarts:hopper_minecart",
	description = S("Minecart with Hopper"),
	tt_help = nil,
	longdesc = nil,
	usagehelp = nil,
	initial_properties = {
		mesh = "mcl_minecarts_minecart_hopper.b3d",
		textures = {
			"mcl_hoppers_hopper_inside.png",
			"mcl_minecarts_minecart.png",
			"mcl_hoppers_hopper_outside.png",
			"mcl_hoppers_hopper_top.png",
		},
	},
	icon = "mcl_minecarts_minecart_hopper.png",
	drop = {"mcl_minecarts:minecart", "mcl_hoppers:hopper"},
	groups = { container = 1 },
	on_rightclick = nil,
	on_activate_by_rail = nil,
	_mcl_minecarts_on_enter = function(self, pos)
		local staticdata = self._staticdata
		if (staticdata.hopper_delay or 0) > 0 then
			return
		end

		-- try to pull from containers into our inventory
		local inv = mcl_entity_invs.load_inv(self,5)
		local above_pos = pos + vector.new(0,1,0)
		mcl_util.hopper_pull_to_inventory(inv, 'main', above_pos, pos)

		staticdata.hopper_delay =  (staticdata.hopper_delay or 0) + (1/20)
	end,
	_mcl_minecarts_on_step = function(self, dtime)
		hopper_take_item(self, dtime)
	end,
	creative = true
})
mcl_entity_invs.register_inv("mcl_minecarts:hopper_minecart", "Hopper Minecart", 5, false, true)

-- Minecart with TNT
local function activate_tnt_minecart(self, timer)
	if self._boomtimer then
		return
	end
	if timer then
		self._boomtimer = timer
	else
		self._boomtimer = tnt.BOOMTIMER
	end
	self.object:set_properties({textures = {
		"mcl_tnt_blink.png",
		"mcl_tnt_blink.png",
		"mcl_tnt_blink.png",
		"mcl_tnt_blink.png",
		"mcl_tnt_blink.png",
		"mcl_tnt_blink.png",
		"mcl_minecarts_minecart.png",
	}})
	self._blinktimer = tnt.BLINKTIMER
	minetest.sound_play("tnt_ignite", {pos = self.object:get_pos(), gain = 1.0, max_hear_distance = 15}, true)
end
register_minecart({
	itemstring = "mcl_minecarts:tnt_minecart",
	craft = {
		output = "mcl_minecarts:tnt_minecart",
		recipe = {
			{"mcl_tnt:tnt"},
			{"mcl_minecarts:minecart"},
		},
	},
	entity_id = "mcl_minecarts:tnt_minecart",
	description = S("Minecart with TNT"),
	tt_help = S("Vehicle for fast travel on rails").."\n"..S("Can be ignited by tools or powered activator rail"),
	longdesc = S("A minecart with TNT is an explosive vehicle that travels on rail."),
	usagehelp = S("Place it on rails. Punch it to move it. The TNT is ignited with a flint and steel or when the minecart is on an powered activator rail.") .. "\n" ..
		S("To obtain the minecart and TNT, punch them while holding down the sneak key. You can't do this if the TNT was ignited."),
	initial_properties = {
		mesh = "mcl_minecarts_minecart_block.b3d",
		textures = {
			"default_tnt_top.png",
			"default_tnt_bottom.png",
			"default_tnt_side.png",
			"default_tnt_side.png",
			"default_tnt_side.png",
			"default_tnt_side.png",
			"mcl_minecarts_minecart.png",
		},
	},
	icon = "mcl_minecarts_minecart_tnt.png",
	drop = {"mcl_minecarts:minecart", "mcl_tnt:tnt"},
	on_rightclick = function(self, clicker)
		-- Ingite
		if not clicker or not clicker:is_player() then
			return
		end
		if self._boomtimer then
			return
		end
		local held = clicker:get_wielded_item()
		if held:get_name() == "mcl_fire:flint_and_steel" then
			if not minetest.is_creative_enabled(clicker:get_player_name()) then
				held:add_wear(65535/65) -- 65 uses
				local index = clicker:get_wield_index()
				local inv = clicker:get_inventory()
				inv:set_stack("main", index, held)
			end
			activate_tnt_minecart(self)
		end
	end,
	on_activate_by_rail = activate_tnt_minecart,
	creative = true,
	_mcl_minecarts_on_step = function(self, dtime)
		-- Update TNT stuff
		if self._boomtimer then
			-- Explode
			self._boomtimer = self._boomtimer - dtime
			local pos = self.object:get_pos()
			if self._boomtimer <= 0 then
				self.object:remove()
				mcl_explosions.explode(pos, 4, { drop_chance = 1.0 })
				return
			else
				tnt.smoke_step(pos)
			end
		end
		if self._blinktimer then
			self._blinktimer = self._blinktimer - dtime
			if self._blinktimer <= 0 then
				self._blink = not self._blink
				if self._blink then
					self.object:set_properties({textures =
					{
					"default_tnt_top.png",
					"default_tnt_bottom.png",
					"default_tnt_side.png",
					"default_tnt_side.png",
					"default_tnt_side.png",
					"default_tnt_side.png",
					"mcl_minecarts_minecart.png",
					}})
				else
					self.object:set_properties({textures =
					{
					"mcl_tnt_blink.png",
					"mcl_tnt_blink.png",
					"mcl_tnt_blink.png",
					"mcl_tnt_blink.png",
					"mcl_tnt_blink.png",
					"mcl_tnt_blink.png",
					"mcl_minecarts_minecart.png",
					}})
				end
				self._blinktimer = tnt.BLINKTIMER
			end
		end
	end,
})

if minetest.get_modpath("mcl_wip") then
	mcl_wip.register_wip_item("mcl_minecarts:chest_minecart")
	mcl_wip.register_wip_item("mcl_minecarts:furnace_minecart")
	mcl_wip.register_wip_item("mcl_minecarts:command_block_minecart")
end
