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
local DBI = LibStub("LibDBIcon-1.0")
local Dialog = LibStub("AceConfigDialog-3.0")

-- variables that are file scope
local _, default_icon, default_mass_res_icon, isMainline, isWrath, player_class
default_icon = "Interface\\Icons\\Spell_holy_resurrection"
default_mass_res_icon = "Interface\\Icons\\achievement_guildperk_massresurrection"
isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
player_class = UnitClassBase("player")

-- create the default user options and shortcut variable
local db
local defaults = {
	profile = {
		enabled = true,
		["**"] = {		-- addon.db.profile.char...
			massResKey = "/",
			resKey = "*"
		},
		modules = {
			["**"] = {
				themes = {
					["**"] = {}
				}
			}
		},
		minimap = {
			hide = false,
			lock = true,
			minimapPos = 190,
			radius = 80
		},
		useClassIconForBroker = true
	}
}

-- local function to open/close the UX panel; saves writing the code multiple times
local function OpenOrCloseUX()
	if Dialog.OpenFrames["SmartRes2"] then
		Dialog:Close("SmartRes2")
	else
		Dialog:Open("SmartRes2")
	end
end

-- local function to close UX panel when the player enters combat
local function CombatCloseUX()
	if Dialog.OpenFrames["SmartRes2"] then
		Dialog:Close("SmartRes2")
	end
end

-- Ace3 embedded functions
function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	db = self.db.profile
	self:SetEnabledState(db.enabled)

	-- get the options table from Options.lua
	local options = self:GetOptions()

	-- create Profiles
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)

	-- LibDualSpec enchancements
	LibStub("LibDualSpec-1.0"):EnhanceDatabase(self.db, "SmartRes2")
	LibStub("LibDualSpec-1.0"):EnhanceOptions(options.args.profiles, self.db)

	-- add "About" panel from LibAboutPanel-2.0
	options.args.aboutPanel = self:AboutOptionsTable("SmartRes2")
	options.args.aboutPanel.order = -1

	-- register the options table with AceConfig and add the options table to the Blizzard Options UI
	LibStub("AceConfig-3.0"):RegisterOptionsTable("SmartRes2", options)
	Dialog:AddToBlizOptions("SmartRes2")

	-- create slash commands
	addon:RegisterChatCommand("smartres", "ChatCommands")
	addon:RegisterChatCommand("sr", "ChatCommands")

	-- Broker display
	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject("SmartRes2", {
		type = "launcher",
		tocname = "SmartRes2",
		label = "SmartRes2",
		text = "SmartRes2",
		icon = (db.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon,
		OnClick = function(_, button)
			if UnitAffectingCombat("player") then
				CombatCloseUX()
				return
			end
			if button == "RightButton" then
				OpenOrCloseUX()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("SmartRes2", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			tooltip:AddLine(L["Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:Show()
		end
	})
	DBI:Register("SmartRes2", launcher, db.minimap)
end

function addon:OnEnable()
end

function addon:OnDisable()
end

function addon:RefreshConfig()
	db = self.db.profile
	DBI:Refresh("SmartRes2", db.minimap)
	DBI:IconCallback(_, "SmartRes2", "icon", (db.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon)
end

-- chat commands handler
function addon:ChatCommands()
	if UnitAffectingCombat("player") then
		CombatCloseUX()
		return
	end
	OpenOrCloseUX()
end

-- function that returns the player's class resurrection spell icon or default_icon
function addon:GetIconForBrokerDisplay(playerClass)
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

	local player_spell = res_spells[playerClass]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_icon
	return icon
end

-- function for options UI that returns the player's class mass res icon
function addon:GetClassMassResIcon(playerClass)
	if not isMainline then return end
	local mass_res_spells = {
		["DRUID"] = GetSpellInfo(212040),				-- Revitalize
		["EVOKER"] = GetSpellInfo(361178),				-- Mass Return
		["MONK"] = GetSpellInfo(212051),				-- Reawaken
		["PALADIN"] = GetSpellInfo(212056),				-- Absolution
		["PRIEST"] = GetSpellInfo(212036),				-- Mass Resurrection
		["SHAMAN"] = GetSpellInfo(212048),				-- Ancestral Vision
	}

	local player_spell = mass_res_spells[playerClass]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_mass_res_icon
	return icon
end