--- SmartRes2
---@class file
-- @name SmartRes2.lua
-- @author Sygon_Paul of Lightbringer
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- upvalue Blizzard APIs for game version compatibility
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata
local GetSpellBookItemName = GetSpellBookItemName
local SaveBindings = SaveBindings

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
local _, knownResSpell
local default_icon = "Interface\\Icons\\Spell_holy_resurrection"
local player_class = UnitClassBase("player")
local player_GUID = UnitGUID("player")
local realm_name = GetRealmName()
local player_name = UnitName("player") .. " - " .. realm_name

-- res buttons to be fully created via Options.lua
local resButton = CreateFrame("Button", "SmartRes2_ResButton", UIParent, "SecureActionButtonTemplate")
resButton:SetAttribute("type", "spell")
resButton:SetScript("PreClick", function()
	addon:SingleResurrection()
end)

-- create the default user options and shortcut variable
local db, options
local defaults = {
	profile = {
		enabled = true,
		enableFeedback = true,
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

	-- shortcut
	db = self.db.profile

	-- enable or disable the addon based on the profile
	self:SetEnabledState(db.enabled)

	-- get the options table from Options.lua
	options = self:GetOptions()

	-- create Profiles
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 0 -- first tab in the options panel

	-- LibDualSpec enchancements for Seasons == 2 (Season of Discovery)
	local isSoD = (WOW_PROJECT_ID == WOW_PROJECT_CLASSIC) and (C_Seasons and C_Seasons.GetActiveSeason() == 2)
	if isSoD then
		LibStub("LibDualSpec-1.0"):EnhanceDatabase(self.db, "SmartRes2")
		LibStub("LibDualSpec-1.0"):EnhanceOptions(options.args.profiles, self.db)
	end

	-- add "About" panel from LibAboutPanel-2.0
	options.args.aboutPanel = self:AboutOptionsTable("SmartRes2")
	options.args.aboutPanel.order = -1 -- last tab in the options panel

	-- need to add the options to the addon table so modules can add their options
	self.options = options

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
	self:BindResKeys()
	for moduleName, module in self:IterateModules() do
		local mdbe = module.db.profile.enabled
		if mdbe then
			if not module:IsEnabled() then
				self:EnableModule(moduleName)
			end
		end
	end
end

function addon:OnDisable()
	self:UnregisterEvent("SPELLS_CHANGED")
	self:UnbindAllResAndMassResKeys()
	for moduleName in self:IterateModules() do
		self:DisableModule(moduleName)
	end
end

function addon:RefreshConfig()
	self.db.profile[player_name] = {}
	db = self.db.profile
	for _, module in self:IterateModules() do
		if type(module.RefreshConfig) == "function" then
			module:RefreshConfig()
		end
	end
	DBI:Refresh("SmartRes2", db.minimap)
	local button = DBI:GetMinimapButton("SmartRes2")
	local iconTexture = (db.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon
	button.icon:SetTexture(iconTexture)
	self:BindResKeys()
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

-- function to learn which res spell and spell rank the player knows
local single_res_spells_by_name = {
	[GetSpellInfo(7328)]	= true, -- Redemption
	[GetSpellInfo(2006)]	= true, -- Resurrection
	[GetSpellInfo(2008)]	= true, -- Ancestral Spirit
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
		end
		-- Classic Era, hardcore, and seasons have ranks; keep looping the spellbook until we run out of spells
		-- newSpellID should be the highest ranked res spellID or nil
		i = i + 1
	end

	-- now determine if the player actualy knows the res spell, IE: the player can cast it
	if newSpellID and IsSpellKnown(newSpellID) then
		-- we need the spell name to pass into IsUsableSpell()
		-- there is no point in passing the spellID if the player can't cast the spell
		-- (usually the player is in the wrong spec)
		knownResSpell = GetSpellInfo(newSpellID)
	end
end

-- bind the single res keys
function addon:BindResKeys()
	-- clear the bindings if the player does not know a res spell
	if not knownResSpell then
		if db.enableFeedback then
			self:Print(L["You do not know a single target res spell, cannot bind keys."])
		end
		db[player_name].resKey, db[player_name].manualResKey = "", ""
		-- if the API SetBinding() is not passed a second arg then it unbinds the key
		SetBinding(db[player_name].resKey)
		SetBinding(db[player_name].manualResKey)
		SaveBindings(2)
		return
	end

	-- the user cleared the res spell keybind
	if db[player_name].resKey == "" then
		SetBinding(db[player_name].resKey)
		SaveBindings(2)
		return
	end

	-- the user cleared the manual res spell keybind
	if db[player_name].manualResKey == "" then
		SetBinding(db[player_name].manualResKey)
		SaveBindings(2)
		return
	end

	-- the user is setting a non-empty string for the keybinds
	local ok = SetBindingClick(db[player_name].resKey, resButton:GetName(), "LeftClick")
	if ok then
		if db.enableFeedback then
			self:Print(L["Single target key bound."])
		end
	end

	ok = SetBindingSpell(db[player_name].manualResKey, knownResSpell)
	if ok then
		if db.enableFeedback then
			self:Print(L["Manual target key bound."])
		end
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

	-- temporarily set the user keybinds to empty strings
	db[player_name].resKey = ""
	db[player_name].manualResKey = ""

	-- unbind the keys
	SetBinding(db[player_name].resKey)
	SetBinding(db[player_name].manualResKey)
	SaveBindings(2)

	-- restore the user settings
	db[player_name].resKey = tempResKey
	db[player_name].manualResKey = tempManualResKey
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