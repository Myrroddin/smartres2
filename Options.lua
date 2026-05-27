-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Options
--
-- Current scope:
-- - Main enable/disable option.
-- - Global minimap/Broker settings.
-- - No keybinding options. Blizzard's Key Bindings UI will own binds.
-- - No Chat/Bars module options yet.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local ENABLE = ENABLE
local DISABLE = DISABLE
local HIDE = HIDE
local LOCK = LOCK
local MINIMAP_LABEL = MINIMAP_LABEL
local GENERAL_LABEL = GENERAL_LABEL

local math_floor = math.floor
local LibStub = LibStub

-- --------------------------------------------------------------------
-- Addon / libraries
-- --------------------------------------------------------------------

---@class LibDBIcon-1.0
---@field IsButtonCompartmentAvailable fun(self: LibDBIcon-1.0): boolean?
---@field IsButtonInCompartment fun(self: LibDBIcon-1.0, buttonName: string): boolean
---@field AddButtonToCompartment fun(self: LibDBIcon-1.0, buttonName: string, customIcon?: string|number)
---@field RemoveButtonFromCompartment fun(self: LibDBIcon-1.0, buttonName: string)

---@class SmartRes2MinimapDB: LibDBIcon.button.DB
---@field hide boolean
---@field lock boolean
---@field showInCompartment boolean
---@field lockOnDegree boolean
---@field minimapPos number

---@class SmartRes2GlobalDB
---@field useClassIconForBroker boolean
---@field minimap SmartRes2MinimapDB

---@class SmartRes2ProfileDB
---@field enabled boolean

---@class SmartRes2DB: AceDBObject-3.0
---@field profile SmartRes2ProfileDB
---@field global SmartRes2GlobalDB

---@class SmartRes2: AceAddon
---@field db SmartRes2DB
---@field RefreshBrokerIcon fun(self: SmartRes2)
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local LibDBIcon = LibStub("LibDBIcon-1.0")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

local DEFAULT_ICON = "Interface\\Icons\\Spell_holy_resurrection"

-- --------------------------------------------------------------------
-- Local helpers
-- --------------------------------------------------------------------

---@return SmartRes2ProfileDB profileDB
local function GetProfileDB()
	return addon.db.profile
end

---@return SmartRes2GlobalDB globalDB
local function GetGlobalDB()
	return addon.db.global
end

---@return SmartRes2MinimapDB minimapDB
local function GetMinimapDB()
	return addon.db.global.minimap
end

---@param value number
---@return number position
local function GetRoundedMinimapPosition(value)
	local minimapDB = GetMinimapDB()

	if minimapDB.lockOnDegree then
		value = math_floor(value + 0.5)
	end

	if value < 1 then
		return 1
	elseif value > 360 then
		return 360
	end

	return value
end

local function RefreshMinimapButton()
	LibDBIcon:Refresh("SmartRes2", GetMinimapDB())
end

-- --------------------------------------------------------------------
-- Options table
-- --------------------------------------------------------------------

local options
---@return table options
function addon:GetOptions()
	if options then
		return options
	end
	options = {
		order = 10,
		type = "group",
		childGroups = "tab",
		name = "SmartRes2",
		handler = addon,
		args = {
			addonDescription = {
				order = 10,
				type = "description",
				name = L["Notes"],
				fontSize = "large",
				image = DEFAULT_ICON,
				imageWidth = 32,
				imageHeight = 32,
			},
			breakLine = {
				order = 20,
				type = "header",
				name = "",
			},
			generalOptions = {
				order = 30,
				type = "group",
				name = GENERAL_LABEL,
				args = {
					enabled = {
						order = 10,
						type = "toggle",
						name = ENABLE .. " / " .. DISABLE,
						desc = L["Toggle SmartRes2 on or off."],
						get = function()
							return GetProfileDB().enabled
						end,
						set = function(_, value)
							GetProfileDB().enabled = value
							addon:SetEnabledState(value)
						end,
					},
				},
			},
			minimap = {
				order = 40,
				type = "group",
				name = MINIMAP_LABEL,
				args = {
					hide = {
						order = 10,
						type = "toggle",
						name = HIDE,
						desc = L["Hide the minimap button."],
						get = function()
							return GetMinimapDB().hide
						end,
						set = function(_, value)
							local minimapDB = GetMinimapDB()

							minimapDB.hide = value

							if value then
								LibDBIcon:Hide("SmartRes2")
							else
								LibDBIcon:Show("SmartRes2")
							end

							RefreshMinimapButton()
						end,
					},
					lock = {
						order = 20,
						type = "toggle",
						name = LOCK,
						desc = L["Lock the minimap button and prevent dragging."],
						get = function()
							return GetMinimapDB().lock
						end,
						set = function(_, value)
							local minimapDB = GetMinimapDB()

							minimapDB.lock = value

							if value then
								LibDBIcon:Lock("SmartRes2")
							else
								LibDBIcon:Unlock("SmartRes2")
							end

							minimapDB.minimapPos = GetRoundedMinimapPosition(minimapDB.minimapPos)
							LibDBIcon:SetButtonToPosition("SmartRes2", minimapDB.minimapPos)
							RefreshMinimapButton()
						end,
					},
					lockOnDegree = {
						order = 30,
						type = "toggle",
						name = L["Precise Lock"],
						desc = L["When locked, snap the minimap button to an exact degree."],
						get = function()
							return GetMinimapDB().lockOnDegree
						end,
						set = function(_, value)
							local minimapDB = GetMinimapDB()

							minimapDB.lockOnDegree = value
							minimapDB.minimapPos = GetRoundedMinimapPosition(minimapDB.minimapPos)

							LibDBIcon:SetButtonToPosition("SmartRes2", minimapDB.minimapPos)
							RefreshMinimapButton()
						end,
					},
					minimapPos = {
						order = 40,
						type = "range",
						name = L["Rotate Button"],
						desc = L["Rotate the minimap button."],
						disabled = function()
							return GetMinimapDB().lock
						end,
						get = function()
							return GetMinimapDB().minimapPos
						end,
						set = function(_, value)
							local minimapDB = GetMinimapDB()

							minimapDB.minimapPos = GetRoundedMinimapPosition(value)

							LibDBIcon:SetButtonToPosition("SmartRes2", minimapDB.minimapPos)
							RefreshMinimapButton()
						end,
						min = 1,
						max = 360,
						step = 1,
						bigStep = 15,
					},
					useClassIconForBroker = {
						order = 50,
						type = "toggle",
						name = L["Class Button"],
						desc = L["Use your class resurrection spell icon for the minimap button."],
						get = function()
							return GetGlobalDB().useClassIconForBroker
						end,
						set = function(_, value)
							GetGlobalDB().useClassIconForBroker = value
							addon:RefreshBrokerIcon()
						end,
					},
					addonCompartment = {
						order = 60,
						type = "toggle",
						name = L["AddOn Compartment"],
						desc = L["Show the minimap button in the addon compartment."],
						disabled = function()
							return not LibDBIcon:IsButtonCompartmentAvailable()
						end,
						hidden = function()
							return not LibDBIcon:IsButtonCompartmentAvailable()
						end,
						get = function()
							return GetMinimapDB().showInCompartment
						end,
						set = function(_, value)
							GetMinimapDB().showInCompartment = value
							RefreshMinimapButton()
						end,
					},
				},
			},
			keybindings = {
				order = 50,
				type = "group",
				name = L["Key Bindings"],
				args = {
					keybindingInfo = {
						order = 10,
						type = "description",
						name = L["SmartRes2 key bindings are configured in Blizzard's Key Bindings UI."],
						fontSize = "medium",
					},
				},
			},
		},
	}

	return options
end