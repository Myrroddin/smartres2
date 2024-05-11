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
local _, knownResSpell, knownMassResSpell
local default_icon = "Interface\\Icons\\Spell_holy_resurrection"
local player_class = UnitClassBase("player")
local player_GUID = UnitGUID("player")

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

-- create the default user options and shortcut variable
local cdb, gdb, pdb, options
local defaults = {,
	char = {
		manualResKey = nil,
		reskey = nil,
		massResKey = nil
	},
	global = {
		minimap = {
			hide = false,
			lock = true,
			showInCompartment = true,
			useClassIconForBroker = true,
			lockOnDegree = true,
			minimapPos = 45
		}
	},
	profile = {
		enabled = true,
		enableFeedback = true
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

	-- shortcuts
	cdb = self.db.char
	gdb = self.db.global
	pdb = self.db.profile

	-- enable or disable the addon based on the profile
	self:SetEnabledState(pdb.enabled)

	-- get the options table from Options.lua
	options = self:GetOptions()

	-- create Profiles
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 0 -- first tab in the options panel

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
		icon = (gdb.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon,
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
	DBI:Register("SmartRes2", launcher, gdb.minimap)

	-- register events when player enters or leaves combat; these events are never unregistered
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "EnteringCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "EnteringCombat")
end

function addon:OnEnable()
	self:RegisterEvent("SPELLS_CHANGED", "GetUpdatedSpells")
	self:GetUpdatedSpells()
	self:BindResKeys()
	self:BindMassResKey()
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
	cdb = self.db.char
	gdb = self.db.global
	pdb = self.db.profile
	for _, module in self:IterateModules() do
		if type(module.RefreshConfig) == "function" then
			module:RefreshConfig()
		end
	end
	DBI:Refresh("SmartRes2", gdb.minimap)
	local button = DBI:GetMinimapButton("SmartRes2")
	local iconTexture = (gdb.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon
	button.icon:SetTexture(iconTexture)
	self:BindResKeys()
	self:BindMassResKey()
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
	["EVOKER"] = GetSpellInfo(361227),		-- Return
	["MONK"] = GetSpellInfo(115178),		-- Resuscitate
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

-- used to determine if the player knows a mass res spell
local mass_res_spells_by_class = {
	["DRUID"] = GetSpellInfo(212040),		-- Revitalize
	["EVOKER"] = GetSpellInfo(361178),		-- Mass Return
	["MONK"] = GetSpellInfo(212051),		-- Reawaken
	["PALADIN"] = GetSpellInfo(212056),		-- Absolution
	["PRIEST"] = GetSpellInfo(212036),		-- Mass Resurrection
	["SHAMAN"] = GetSpellInfo(212048),		-- Ancestral Vision
}

-- function to learn which res spell the player knows
local single_res_spells_by_name = {
	[GetSpellInfo(2006)]		= true, -- Resurrection
	[GetSpellInfo(2008)]		= true, -- Ancestral Spirit
	[GetSpellInfo(7328)]		= true, -- Redemption
	[GetSpellInfo(50769)]		= true, -- Revive
	[GetSpellInfo(115178)]		= true, -- Resuscitate
	[GetSpellInfo(212051)]		= true, -- Reawaken
}

function addon:GetUpdatedSpells()
	local newSpellName, newSpellID
	local i = 1

	-- first, determine if res spells are in the player's spellbook
	while true do
		newSpellName = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not newSpellName then
			-- end of the spellbook; break the while loop
			break
		end

		if single_res_spells_by_name[newSpellName] then
			-- get the spellID here, where there is a table match
			newSpellID = select(7, GetSpellInfo(newSpellName))
			-- mainline has no spell ranks; break the while loop when we match
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
		knownResSpell = GetSpellInfo(newSpellID)
	end

	-- known mass res spell
	local newMassResName, newMassResSpellID
	newMassResName = mass_res_spells_by_class[player_class]
	newMassResSpellID = newMassResName and select(7, GetSpellInfo(newMassResName))
	knownMassResSpell = newMassResSpellID and IsSpellKnown(newMassResSpellID) and newMassResName
end

-- bind the single res keys
function addon:BindResKeys()
	if not knownResSpell then
		if pdb.enableFeedback then
			self:Print(L["You do not know a single target res spell, cannot bind keys."])
		end
		cdb.resKey = nil
		cdb.manualResKey = nil
		return
	end
	local ok

	if cdb.resKey then
		ok = SetBindingClick(cdb.resKey, resButton:GetName(), "LeftClick")
		if ok then
			if pdb.enableFeedback then
				self:Print(L["Single target key bound."])
			end
		end
	end

	if cdb.manualResKey then
		ok = SetBindingSpell(cdb.manualResKey, knownResSpell)
		if ok then
			if pdb.enableFeedback then
				self:Print(L["Manual target key bound."])
			end
		end
	end

	-- save the bindings per characher so they persist through logout
	SaveBindings(2)
end

-- bind the mass res key
function addon:BindMassResKey()
	if not knownMassResSpell then
		if pdb.enableFeedback then
			self:Print(L["You do not know a mass res spell, cannot bind key."])
		end
		cdb.massResKey = nil
		return
	end
	local ok

	if cdb.massResKey then
		ok = SetBindingClick(cdb.massResKey, massResButton:GetName(), "LeftClick")
		if ok then
			if pdb.enableFeedback then
				self:Print(L["Mass res key bound."])
			end
		end
	end

	-- save the bindings per characher so they persist through logout
	SaveBindings(2)
end

-- unbind all the keys
function addon:UnbindAllResAndMassResKeys()
	if cdb.resKey then
		SetBinding(cdb.resKey)
	end
	if cdb.manualResKey then
		SetBinding(cdb.manualResKey)
	end
	if cdb.massResKey then
		SetBinding(cdb.massResKey)
	end
	SaveBindings(2)
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
--------- end of APIs ----------

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