--- SmartRes2
---@class file
---@name Core-Cata.lua
-- @author Sygon_Paul of Lightbringer
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- upvalue Lua and Blizzard APIs for faster lookups
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata
local GetSpellBookItemName = GetSpellBookItemName
local SaveBindings, UnitClassBase, UnitGUID = SaveBindings, UnitClassBase, UnitGUID
local UnitName, GetRealmName = UnitName, GetRealmName
local CreateFrame, LibStub = CreateFrame, LibStub

-- create the main addon
local addon = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceEvent-3.0", "AceConsole-3.0", "AceComm-3.0", "AceSerializer-3.0", "LibAboutPanel-2.0", "LibResInfo-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
addon:SetDefaultModuleLibraries("AceEvent-3.0", "AceConsole-3.0", "AceComm-3.0", "AceSerializer-3.0", "LibResInfo-2.0")

-- get the addon version
addon.version = GetAddOnMetadata("SmartRes2", "Version")
if addon.version:match("@") then
	addon.version = "Development"
end

-- additional libraries
local DBI = LibStub("LibDBIcon-1.0")
local Dialog = LibStub("AceConfigDialog-3.0")

-- variables that are file scope
local default_icon = "Interface\\Icons\\Spell_holy_resurrection"
local player_class = UnitClassBase("player")
local player_GUID = UnitGUID("player")
local player_name = UnitName("player") .. " - " .. GetRealmName()

-- res buttons to be fully created via Options.lua
local resButton = CreateFrame("Button", "SmartRes2_ResButton", UIParent, "SecureActionButtonTemplate")
resButton:SetAttribute("type", "spell")
resButton:SetScript("PreClick", function()
	addon:SingleResurrection()
end)

local massResButton = CreateFrame("Button", "SmartRes2_MassResButton", UIParent, "SecureActionButtonTemplate")
massResButton:SetAttribute("type", "spell")
massResButton:SetScript("PreClick", function()
	addon:MassRessurection()
end)


local db, options
local defaults = {
	profile = {
		enabled = true,
		minimap = {
			hide = false,
			lock = true,
			useClassIconForBroker = true,
			lockOnDegree = true,
			minimapPos = 45
		}
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

	-- we need character-baased key binds
	self.db.profile[player_name] = self.db.profile[player_name] or {}
	self.db.profile[player_name].resKey = self.db.profile[player_name].resKey or ""
	self.db.profile[player_name].manualResKey = self.db.profile[player_name].manualResKey or ""
	self.db.profile[player_name].massResKey = self.db.profile[player_name].massResKey or ""

	-- shortcut
	db = self.db.profile

	-- enable or disable the addon based on the profile
	self:SetEnabledState(db.enabled)

	-- get the options table from Options.lua
	options = self:GetOptions()

	-- create Profiles
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 200

	-- need to add the options to the addon table so modules can add their options
	self.options = options

	-- LibDualSpec enchancements
	LibStub("LibDualSpec-1.0"):EnhanceDatabase(self.db, "SmartRes2")
	LibStub("LibDualSpec-1.0"):EnhanceOptions(options.args.profiles, self.db)

	-- add "About" panel from LibAboutPanel-2.0
	options.args.aboutPanel = self:AboutOptionsTable("SmartRes2")
	options.args.aboutPanel.order = -1 -- last tab in the options panel

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
		icon = (db.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon,
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

	-- register events when player enters or leaves combat; these events are never unregistered
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "EnteringCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "EnteringCombat")
end

function addon:OnEnable()
	self:RegisterEvent("SPELLS_CHANGED", "GetUpdatedSpells")
	self:GetUpdatedSpells()
	local moduleOrder = 60
	for moduleName, module in self:IterateModules() do
		-- verify a module exists before messing with its settings
		if moduleName then
			-- assign modules an incremented order in the main options table
			self.options.args[moduleName].order = moduleOrder
			moduleOrder = moduleOrder + 10
			-- disable the module's tab if the core addon is disabled
			self.options.args[moduleName].disabled = function() return not db.enabled end
			-- check if a module should be enabled, and if so, enable it
			local mdbe = module.db.profile.enabled
			if mdbe then
				if not module:IsEnabled() then
					self:EnableModule(moduleName)
				end
			end
		end
	end
end

function addon:OnDisable()
	self:UnregisterEvent("SPELLS_CHANGED")
	self:UnbindAllResAndMassResKeys()
	for moduleName in self:IterateModules() do
		-- verify a module exists before disabling it
		if moduleName then
			self:DisableModule(moduleName)
		end
	end
end

function addon:RefreshConfig()
	self.db:ResetProfile()
	self.db.profile[player_name] = {}
	self.db.profile[player_name].resKey = ""
	self.db.profile[player_name].manualResKey = ""
	self.db.profile[player_name].massResKey = ""
	db = self.db.profile
	for moduleName, module in self:IterateModules() do
		-- verify a module exists before messing with its settings
		if moduleName then
			if type(module.RefreshConfig) == "function" then
				module:RefreshConfig()
			end
		end
	end
	DBI:Refresh("SmartRes2", db.minimap)
	local button = DBI:GetMinimapButton("SmartRes2")
	local iconTexture = (db.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon
	button.icon:SetTexture(iconTexture)
	self:GetUpdatedSpells()
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
local res_spells_by_class = {
	["DRUID"] = GetSpellInfo(50769),		-- Revive
	["PALADIN"] = GetSpellInfo(7328),		-- Redemption
	["PRIEST"] = GetSpellInfo(2006),		-- Resurrection
	["SHAMAN"] = GetSpellInfo(2008),		-- Ancestral Spirit
}

function addon:GetIconForBrokerDisplay(playerClass)
	local player_spell = res_spells_by_class[playerClass]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_icon
	return icon
end

-- function to learn which res spell the player knows
local single_res_spells_by_name = {
	[GetSpellInfo(2006)]		= true, -- Resurrection
	[GetSpellInfo(2008)]		= true, -- Ancestral Spirit
	[GetSpellInfo(7328)]		= true, -- Redemption
	[GetSpellInfo(50769)]		= true, -- Revive
}

function addon:GetUpdatedSpells()
	local newSpellName, newSpellID
	local i = 1

	-- first, determine if res spells and ranks are in the player's spellbook
	while true do
		newSpellName = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not newSpellName then
			-- end of the spellbook; break the while loop
			break
		end

		if single_res_spells_by_name[newSpellName] then
			-- get the spellID here, where there is a table match
			newSpellID = select(7, GetSpellInfo(newSpellName))
			-- Cataclysm Classic has no spell ranks; break the while loop when we match
			break
		end
		-- loop through the spellbook until the end or there is a match, whichever happens first
		i = i + 1
	end

	-- now determine if the player actualy knows the res spell, IE: the player can cast it
	if newSpellID and IsSpellKnown(newSpellID) then
		-- we need the spell name to pass into IsUsableSpell()
		-- there is no point in passing the spellID if the player can't cast the spell
		-- (usually the player is in the wrong spec)
		self.knownResSpell = GetSpellInfo(newSpellID)
	end

	-- known mass res spell
	self.knownMassResSpell = IsSpellKnown(83968) and GetSpellInfo(83968)

	self:BindResKeys()
	self:BindMassResKey()
end

-- bind the single res keys
function addon:BindResKeys()
	if self.knownResSpell then
		if db[player_name].resKey == "" then
			-- the user cleared the res spell keybind
			SetBinding(db[player_name].resKey)
		else
			-- there is a non-empty string to bind
			SetBindingClick(db[player_name].resKey, resButton:GetName(), "LeftClick")
		end

		if db[player_name].manualResKey == "" then
			-- the user cleared the manual res spell keybind
			SetBinding(db[player_name].manualResKey)
		else
			-- there is a non-empty string to bind
			SetBindingSpell(db[player_name].manualResKey, self.knownResSpell)
		end
	else
		-- the character does not know a res spell
		db[player_name].resKey, db[player_name].manualResKey = "", ""
		SetBinding(db[player_name].resKey)
		SetBinding(db[player_name].manualResKey)
	end

	-- save the bindings per character so they persist through logout
	SaveBindings(2)
end

-- bind the mass res key
function addon:BindMassResKey()
	local tempMassResKey = db[player_name].massResKey
	if self.knownMassResSpell then
		if db[player_name].massResKey == "" then
			-- the user has cleared the mass res key bind
			SetBinding(db[player_name].massResKey)
		else
			-- there is a non-empty string to bind
			SetBindingClick(db[player_name].massResKey, massResButton:GetName(), "LeftClick")
		end
	else
		-- the character does not know a mass res spell
		db[player_name].massResKey = ""
		SetBinding(db[player_name].massResKey)
		-- we don't want to change the user's keybinds every time the character learns/unlearns a mass res spell
		db[player_name].massResKey = tempMassResKey
	end

	-- save the bindings per character so they persist through logout
	SaveBindings(2)
end

-- unbind all the keys
function addon:UnbindAllResAndMassResKeys()
	-- if the API SetBinding() is not passed a second arg then it unbinds the key

	-- we do not want to override the user's settings for the keybinds, so create temp variables
	local tempResKey = db[player_name].resKey
	local tempManualResKey = db[player_name].manualResKey
	local tempMassResKey = db[player_name].massResKey

	-- temporarily set the user keybinds to empty strings
	db[player_name].resKey = ""
	db[player_name].manualResKey = ""
	db[player_name].massResKey = ""

	-- unbind the keys
	SetBinding(db[player_name].resKey)
	SetBinding(db[player_name].manualResKey)
	SetBinding(db[player_name].massResKey)
	SaveBindings(2)

	-- restore the user settings
	db[player_name].resKey = tempResKey
	db[player_name].manualResKey = tempManualResKey
	db[player_name].massResKey = tempMassResKey
end

-- translate input table and return localizations
function addon:TranslateTable(inputTable)
	-- inputTable's index is a string, value is a Boolean; therefore, we localize the index
    local outputTable = {}
    for index in pairs(inputTable) do
        outputTable[index] = L[index]
    end
    return outputTable
end

-- round to N decimals
function addon:Round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return floor(value * mult + 0.5) / mult
end

-- handle events
function addon:EnteringCombat()
	if UnitAffectingCombat("player") then
		CombatCloseUX()
	end
end

-- smart res functions that pick dead targets intelligently
function addon:SingleResurrection()
end

-- smart mass res function
function addon:MassRessurection()
	if not IsInGroup() then
		self:Print(L["You are not in a group."])
		return
	end
end