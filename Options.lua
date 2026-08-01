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

local DISABLE = DISABLE
local ENABLE = ENABLE
local GENERAL_LABEL = GENERAL_LABEL
local HIDE = HIDE
local LibStub = LibStub
local LOCK = LOCK
local math_floor = math.floor
local MINIMAP_LABEL = MINIMAP_LABEL
local Reload = C_UI.Reload

-- --------------------------------------------------------------------
-- Addon / libraries
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

local DEFAULT_ICON = "Interface\\Icons\\Spell_holy_resurrection"

-- --------------------------------------------------------------------
-- Local helpers
-- --------------------------------------------------------------------

local function GetProfileDB()
	return addon.db.profile
end

local function GetGlobalDB()
	return addon.db.global
end

local function GetMinimapDB()
	return addon.db.global.minimap
end

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
	addon.LibDBIcon:Refresh("SmartRes2", GetMinimapDB())
end

local function IsMasqueDisabled()
	return not GetProfileDB().enabled or not addon:IsMasqueAvailable()
end

local function IsMasqueHidden()
	return not addon:IsMasqueAvailable()
end

-- --------------------------------------------------------------------
-- Options table
-- --------------------------------------------------------------------

local options
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

							if value then
								addon:Enable()
							else
								addon:Disable()
							end
						end,
					},
					resetGlobalOnProfileChange = {
						order = 20,
						type = "toggle",
						name = L["Reset All Settings on Profile Change"],
						desc = L["Reset the entire SmartRes2 database to defaults whenever a profile is changed, copied, or reset. This option turns itself off after the reset."],
						get = function()
							return GetGlobalDB().resetGlobalOnProfileChange
						end,
						set = function(_, value)
							GetGlobalDB().resetGlobalOnProfileChange = value
						end,
					},
					useMasque = {
						order = 30,
						type = "toggle",
						name = L["Use Masque"],
						desc = L["Use Masque to skin bar icons."],
						disabled = IsMasqueDisabled,
						hidden = IsMasqueHidden,
						get = function()
							return GetProfileDB().useMasque
						end,
						set = function(_, value)
							GetProfileDB().useMasque = value
						end,
					},
					notifySelf = {
						order = 40,
						type = "toggle",
						name = L["Notify Self"],
						desc = L["Inform yourself of SmartRes2 system messages."],
						get = function()
							return GetProfileDB().notifySelf
						end,
						set = function(_, value)
							GetProfileDB().notifySelf = value
						end,
					},
					useClassColorsForSystemMessages = {
						order = 50,
						type = "toggle",
						name = L["Class-Colored Names"],
						desc = L["Use class colors for player names in SmartRes2 system messages."],
						disabled = function()
							return not GetProfileDB().notifySelf
						end,
						get = function()
							return GetProfileDB().useClassColorsForSystemMessages
						end,
						set = function(_, value)
							GetProfileDB().useClassColorsForSystemMessages = value
						end,
					},
					useFullNameForSystemMessages = {
						order = 60,
						type = "toggle",
						name = L["Full Names"],
						desc = L["Show realm names for player names in SmartRes2 system messages."],
						disabled = function()
							return not GetProfileDB().notifySelf
						end,
						get = function()
							return GetProfileDB().useFullNameForSystemMessages
						end,
						set = function(_, value)
							GetProfileDB().useFullNameForSystemMessages = value
						end,
					},
					waitingDelay = {
						order = 70,
						type = "range",
						name = L["Res Offer Threshold"],
						desc = L["Allow smart resurrection when an existing resurrection offer or self-resurrection option has this many seconds or less remaining."],
						get = function()
							return GetProfileDB().waitingDelay
						end,
						set = function(_, value)
							GetProfileDB().waitingDelay = value
						end,
						min = 0,
						max = 10,
						step = 0.5,
						bigStep = 2.5,
					},
					keybindTrigger = {
						order = 80,
						type = "select",
						name = L["Keybind Trigger"],
						desc = L["Choose when the keybind should trigger. Changing this requires a UI reload to take effect."],
						confirm = function(_, value)
							if GetProfileDB().keybindTrigger == value then
								return false
							end
							return L["Changing this setting will reload your UI. Continue?"]
						end,
						values = {
							["AnyUp"] = L["Key Up"],
							["AnyDown"] = L["Key Down"],
						},
						get = function()
							return GetProfileDB().keybindTrigger
						end,
						set = function(_, value)
							if GetProfileDB().keybindTrigger == value then
								return
							end

							GetProfileDB().keybindTrigger = value
							Reload()
						end,
					},
					keyBindingsDescription = {
						order = 90,
						type = "description",
						name = L["SmartRes2 key bindings are configured in Blizzard's Key Bindings UI."],
						fontSize = "medium",
						width = "full",
					},
				},
			},
			minimap = {
				order = 60,
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
								addon.LibDBIcon:Hide("SmartRes2")
							else
								addon.LibDBIcon:Show("SmartRes2")
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
								addon.LibDBIcon:Lock("SmartRes2")
							else
								addon.LibDBIcon:Unlock("SmartRes2")
							end

							minimapDB.minimapPos = GetRoundedMinimapPosition(minimapDB.minimapPos)
							addon.LibDBIcon:SetButtonToPosition("SmartRes2", minimapDB.minimapPos)
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

							addon.LibDBIcon:SetButtonToPosition("SmartRes2", minimapDB.minimapPos)
							RefreshMinimapButton()
						end,
					},
					useClassIconForBroker = {
						order = 40,
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
						order = 50,
						type = "toggle",
						name = L["AddOn Compartment"],
						desc = L["Show the minimap button in the addon compartment."],
						disabled = function()
							return not addon.LibDBIcon:IsButtonCompartmentAvailable()
						end,
						hidden = function()
							return not addon.LibDBIcon:IsButtonCompartmentAvailable()
						end,
						get = function()
							return GetMinimapDB().showInCompartment
						end,
						set = function(_, value)
							GetMinimapDB().showInCompartment = value
							RefreshMinimapButton()
						end,
					},
					minimapPos = {
						order = 60,
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

							addon.LibDBIcon:SetButtonToPosition("SmartRes2", minimapDB.minimapPos)
							RefreshMinimapButton()
						end,
						min = 1,
						max = 360,
						step = 1,
						bigStep = 15,
					},
				},
			},
		},
	}

	return options
end