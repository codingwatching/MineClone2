local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)
local S = core.get_translator(modname)
local storage = core.get_mod_storage()
local mod = {}
vl_tuning = mod

local DEBUG = false

-- All registered tunable parameters
--- @type table<string, vl_tuning.Setting>
local tunables = {}
vl_tuning.registered_settings = tunables

-- Supported variable types
local tunable_types = {
	bool = {
		to_string = tostring,
		from_string = function(value)
			return (value == "true")
		end,
		default = false,
	},
	number = {
		to_string = tostring,
		from_string = tonumber,
		default = 0,
	},
	string = {
		to_string = function(v) return v end,
		from_string = function(v) return v end,
		default = "",
	},
}

---@alias vl_tuning.Value string|number|boolean

-- Tunable metatable functions
---@class (exact) vl_tuning.Setting
---@field name string
---@field setting_type "string"|"number"|"bool"
---@field description string
---@field default vl_tuning.Value
---@field set fun(self : vl_tuning.Setting, value : vl_tuning.Value, no_hook : boolean?)
---@field setter fun(value : vl_tuning.Value)
---@field getter fun() : vl_tuning.Value
---@field from_string fun(value : string) : vl_tuning.Value
---@field to_string fun(value : vl_tuning.Value)
---@field on_change? fun(self : vl_tuning.Setting)
---@field formspec_desc_lines? number
local tunable_class = {}

---@param self vl_tuning.Setting
---@param value vl_tuning.Value
---@param no_hook? boolean
function tunable_class:set(value, no_hook)
	if type(value) == "string" then
		local new_value = self.from_string(value)
		if new_value == nil then new_value = self.default end

		self.setter(new_value)
	else
		self.setter(value)
	end

	if DEBUG then
		core.log("action", "[vl_tuning] Set "..self.name.." to "..dump(self.getter()))
	end

	-- Call on_change hook
	if not no_hook then
		local hook = self.on_change
		if hook then hook(self) end
	end

	-- Persist value
	storage:set_string(self.name, self.to_string(self.getter()))
end
function tunable_class:get_string()
	return self.to_string(self.getter())
end

---@class vl_tuning.SettingDef
---@field set fun(value : vl_tuning.Value)
---@field get fun(): vl_tuning.Value
---@field default? vl_tuning.Value
---@field description? string
---@field formspec_desc_lines? number

---@param name string
---@param p_type? "bool"|"number"|"string"
---@param def? vl_tuning.SettingDef
---@return vl_tuning.Setting
function mod.setting(name, p_type, def)
	-- return the existing setting if it was previously registered. Don't update the definition
	local tunable = tunables[name]
	if tunable then return tunable end
	assert(p_type)
	assert(def)
	assert(type(def.set) == "function", "Tunable requires set method")
	assert(type(def.get) == "function", "Tunable required get method")
	assert(tunable_types[p_type])

	-- Setup the tunable data
	---@type vl_tuning.Setting
	tunable = {
		name = name,
		setting_type = p_type,
		description = def.description or "",
		setter = def.set,
		getter = def.get,
		set = tunable_class.set,
		get_string = tunable_class.get_string,
		from_string = tunable_types[p_type].from_string,
		to_string = tunable_types[p_type].to_string,
		formspec_desc_lines = def.formspec_desc_lines,
		default = def.default or tunable_class.default,
	}

	-- Load the setting value from mod storage
	local setting_value = storage:get_string(name)
	if setting_value and setting_value ~= "" then
		tunable:set(setting_value, true)
		if DEBUG then
			core.log("action", "[vl_tuning] Loading "..name.." = "..dump(setting_value).." ("..dump(tunable.getter())..")")
		end
	elseif def.default then
		tunable:set(def.default)
	end

	setmetatable(tunable, {__index=tunable_class})

	-- Add to the list of all available settings
	tunables[name] = tunable

	-- Provide it so that the current value can be retrieved from result.getter()
	return tunable
end

core.register_chatcommand("set_setting", {
	description = S("Admin tool to tune settings and game rules"),
	params = S("<setting> <value>"),
	privs = { server = true },
	func = function(name, params_raw)
		-- Split apart the params
		local params = {}
		for str in string.gmatch(params_raw, "([^ ]+)") do
			params[#params + 1] = str
		end

		if #params ~= 2 then
			return false, S("Usage: /tune <setting> <value>")
		end

		local tunable = tunables[params[1]]
		if not tunable then
			return false, S("Setting @1 doesn't exist", params[1])
		end

		if DEBUG then
			core.log("action", "[vl_tuning] "..name.." set ".. params[1] .." to "..params[2])
		end
		tunable:set(params[2])
		return true
	end
})
core.register_chatcommand("get_setting", {
	description = S("Admin tool to view settings and game rules"),
	params = S("<setting>"),
	privs = { server = true },
	func = function(_, param)
		local tunable = tunables[param]
		if tunable then
			return true, tunable:get_string()
		else
			return false, S("Setting @1 doesn't exist", param)
		end
	end
})

core.register_chatcommand("gamerule", {
	description = S("Display or set customizable options"),
	params = S("<rule> [<value>]"),
	privs = { server = true },
	func = function(_, params_raw)
		-- Split apart the params
		local params = {}
		for str in string.gmatch(params_raw, "([^ ]+)") do
			params[#params + 1] = str
		end

		if #params < 1 or #params > 2 then
			return false, S("Usage: /gamerule <rule> [<value>]")
		end

		local tunable = tunables["gamerule:"..params[1]]
		if not tunable then
			return false, S("Game rule @1 doesn't exist", params[1])
		end

		local value = params[2]
		if value then
			if DEBUG then
				core.log("action", "[vl_tuning] Setting game rule "..params[1].." to "..params[2])
			end
			tunable:set(params[2])
			return true
		else
			return true, tunable:get_string()
		end
	end
})

dofile(modpath.."/settings.lua")
dofile(modpath.."/gui.lua")

mod.setting("debug:vl_tuning:report_value_changes", "bool", {
	default = false,
	set = function(val) DEBUG = val end,
	get = function() return DEBUG end,
})
