--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Sygon_Paul of Lightbringer
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- Blizzard has two variants of GetAddOnMetadata; make a compatibility workaround
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- create the main addon
local addon = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceEvent-3.0", "AceConsole-3.0", "AceComm-3.0", "LibAboutPanel-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
addon:SetDefaultModuleLibraries("AceEvent-3.0")

-- get the addon version
addon.version = GetAddOnMetadata("SmartRes2", "Version")
if addon.version:match("@") then
	addon.version = "Development"
end

-- additional libraries
local LDB = LibStub("LibDataBroker-1.1")
local DBI = LibStub("LibDBIcon-1.0")
local LDS = LibStub("LibDualSpec-1.0")
local Dialog = LibStub("AceConfigDialog-3.0")
local Registry = LibStub("AceConfigRegistry-3.0")
local Command = LibStub("AceConfigCmd-3.0")

-- variables that are file scope
local _, default_icon, isMainline, isWrath, player_class
_, _, default_icon = GetSpellInfo(2006)
isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
player_class = UnitClassBase("player")

-- create the default user options and shortcut variables
local db, gdb
local defaults = {
	global = {
		minimap = {
			hide = false,
			lock = true,
			minimapPos = 190,
			radius = 80
		},
		useClassIconForBroker = true
	},
	profile = {
		enabled = true,
		modules = {
			["**"] = {}
		}
	}
}

-- create the user options
local options = {
	type = "group",
	childGroups = "tab",
	name = "SmartRes2 " .. addon.version,
	args = {
		enableAddOn = {
			order = 10,
			type = "toggle",
			name = ENABLE .. " " .. JUST_OR .. " " .. DISABLE,
			desc = L["Toggle SmartRes2 and all modules on/off."],
			descStyle = "inline",
			get = function() return db.enabled end,
			set = function(info, value)
				db[info[#info]] = value
				if value then
					addon:OnEnable()
				else
					addon:OnDisable()
				end
			end
		},
		minimapStuff = {
			order = 20,
			type = "group",
			name = MINIMAP_LABEL,
			args = {
				button = {
					order = 10,
					type = "toggle",
					name = L["Minimap Button"],
					desc = L["Show or hide the minimap icon."],
					descStyle = "inline",
					get = function() return gdb.minimap.hide end,
					set = function(info, value)
						gdb[info[#info]] = value
						if value then
							DBI:Show("SmartRes2")
						else
							DBI:Hide("SmartRes2")
						end
					end
				},
				buttonLock = {
					order = 20,
					type = "toggle",
					name = L["Lock Button"],
					desc = L["Lock minimap button and prevent moving."],
					descStyle = "inline",
					get = function() return gdb.minimap.lock end,
					set = function(info, value)
						gdb[info[#info]] = value
						if value then
							DBI:Lock("SmartRes2")
						else
							DBI:Unlock("SmartRes2")
						end
					end
				},
				useClassIconForBroker = {
					order = 30,
					type = "toggle",
					name = L["Class Button"],
					desc = L["Use your class spell icon for the Broker display (defaults to Priest's Resurrection)."],
					get = function() return gdb[info[#info]] end,
					set = function(info, value)
						gdb[info[#info]] = value
						addon:BrokerIconChanged("SmartRes2")
					end
				},
				resetButton = {
					order = 40,
					type = "execute",
					name = L["Reset Button"],
					desc = L["Reset the minimap button to defaults (position, visible, locked)."],
					func = function()
						gdb = addon.db.global
						DBI:Refresh("SmartRes2", gdb.minimap)
					end
				}
			}
		}
	}
}

-- local function that returns the player's class resurrection spell icon or default_icon
local function GetIconForBrokerDisplay(player_class)
	local res_spells = {
		["PALADIN"] = GetSpellInfo(7328),				-- Redemption
		["PRIEST"] = GetSpellInfo(2006),				-- Resurrection
		["SHAMAN"] = GetSpellInfo(2008),				-- Ancestral Spirit
	}
	if isWrath or isMainline then
		res_spells["DRUID"] = GetSpellInfo(50769)		-- Revive
	end
	if isMainline then
		res_spells["EVOKER"] = GetSpellInfo(361227)		-- Return
		res_spells["MONK"] = GetSpellInfo(115178)		-- Resuscitate
	end

	local player_spell = res_spells[player_class]
	local player_spell_icon = select(3, (GetSpellInfo(player_spell)))

	local icon = (player_spell and player_spell_icon) or default_icon
	return icon
end

-- Ace3 embedded functions
function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	db = self.db.profile
	gdb = self.db.global
	self:SetEnabledState(db.enabled)

	-- Broker display
	self.launcher = LDB:NewDataObject("SmartRes2", {
		type = "launcher",
		tocname = "SmartRes2",
		label = "SmartRes2",
		text = "SmartRes2",
		icon = (db.useClassIconForBroker and GetIconForBrokerDisplay(player_class)) or default_icon,
		OnClick = function(_, button)
			if UnitAffectingCombat("player") then
				if Dialog.OpenFrames["SmartRes2"] then
					Dialog:Close("SmartRes2")
				end
				return
			end
			if button == "RightButton" then
				if Dialog.OpenFrames["SmartRes2"] then
					Dialog:Close("SmartRes2")
				else
					Dialog:Open("SmartRes2")
				end
			end
		end,
		OnTooltipShow = function()
			GameTooltip:AddLine("SmartRes2", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			GameTooltip:AddLine(L["Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:Show()
		end
	})
	DBI:Register("SmartRes2", self.launcher, gdb.minimap)
end

function addon:OnEnable()
end

function addon:OnDisable()
end

function addon:RefreshConfig()
	db = self.db.profile
	gdb = self.db.global
	DBI:Refresh("SmartRes2", gdb.minimap)
	self:BrokerIconChanged("SmartRes2")
end

-- function to handle LDB callbacks
function addon:BrokerIconChanged(name, key)
	key = key or (db.useClassIconForBroker and GetIconForBrokerDisplay(player_class)) or default_icon
	if name == "SmartRes2" then
		self.launcher.icon = key
	end
end