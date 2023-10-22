--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Sygon_Paul of Lightbringer
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- upvalue Blizzard APIs for game version compatibility
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local GetSpellName = GetSpellBookItemName or GetSpellName
local SaveBindings = SaveBindings or AttemptToSaveBindings
local CastSpellByName = hooksecurefunc("CastSpellByName", CastSpellByName) -- reduce the game screaming at us with taint errors

-- create the main addon
local addon = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceEvent-3.0", "AceConsole-3.0", "AceComm-3.0", "LibAboutPanel-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
addon:SetDefaultModuleLibraries("AceEvent-3.0", "AceComm-3.0", "AceConsole-3.0")

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
local default_mass_res_icon = "Interface\\Icons\\achievement_guildperk_massresurrection"
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local isWrath = WOW_PROJECT_ID == WOW_PROJECT_WRATH_CLASSIC
local player_class = UnitClassBase("player")

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
local db
local defaults = {
	profile = {
		enabled = true,
		enableFeeback = true,
		["**"] = {		-- addon.db.profile.char...
		},
		minimap = {
			hide = false,
			lock = true,
			minimapPos = 190,
			radius = 80,
			showInCompartment = true
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

	-- get module options
	local moduleOrder = 100
	for moduleName, module in self:IterateModules() do
		options.args[moduleName] = module:GetOptions()
		options.args[moduleName].order = moduleOrder
		moduleOrder = moduleOrder + 10
	end

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
	self:SetEnabledState(db.enabled)
	self:RegisterEvent("SPELLS_CHANGED", "GetUpdatedSpells")
	self:BindResKeys()
	self:BindMassResKey()
	for moduleName, module in self:IterateModules() do
		if db[moduleName].enabled and not module:IsEnabled() then
			self:EnableModule(moduleName)
		end
	end
end

function addon:OnDisable()
	self:SetEnabledState(db.enabled)
	self:UnregisterEvent("SPELLS_CHANGED")
	self:UnbindAllResAndMassResKeys()
	for moduleName, module in self:IterateModules() do
		if module:IsEnabled() then
			self:DisableModule(moduleName)
		end
	end
end

function addon:RefreshConfig()
	db = self.db.profile
	DBI:Refresh("SmartRes2", db.minimap)
	DBI:IconCallback(_, "SmartRes2", "icon", (db.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon)
	for _, module in self:IterateModules() do
		if type(module.RefreshConfig) == "function" then
			module:RefreshConfig()
		end
	end
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
	["PALADIN"] = GetSpellInfo(7328),						-- Redemption
	["PRIEST"] = GetSpellInfo(2006),						-- Resurrection
	["SHAMAN"] = GetSpellInfo(2008),						-- Ancestral Spirit
}
if isWrath or isMainline then
	res_spells_by_class["DRUID"] = GetSpellInfo(50769)		-- Revive
end
if isMainline then
	res_spells_by_class["EVOKER"] = GetSpellInfo(361227)	-- Return
	res_spells_by_class["MONK"] = GetSpellInfo(115178)		-- Resuscitate
end

function addon:GetIconForBrokerDisplay(playerClass)
	local player_spell = res_spells_by_class[playerClass]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_icon
	return icon
end

-- function for options UI that returns the player's class mass res icon
local mass_res_spells_by_class = {}
if isMainline then
	mass_res_spells_by_class["DRUID"] = GetSpellInfo(212040)		-- Revitalize
	mass_res_spells_by_class["EVOKER"] = GetSpellInfo(361178)		-- Mass Return
	mass_res_spells_by_class["MONK"] = GetSpellInfo(212051)			-- Reawaken
	mass_res_spells_by_class["PALADIN"] = GetSpellInfo(212056)		-- Absolution
	mass_res_spells_by_class["PRIEST"] = GetSpellInfo(212036)		-- Mass Resurrection
	mass_res_spells_by_class["SHAMAN"] = GetSpellInfo(212048)		-- Ancestral Vision
end

function addon:GetClassMassResIcon(playerClass)
	if not isMainline then
		return "" -- empty string, in case Options.lua complains about a nil value
	end

	local player_spell = mass_res_spells_by_class[playerClass]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_mass_res_icon
	return icon
end

-- function to learn which res spell and spell rank the player knows
local single_res_spells_by_name = {
	-- paladin
	[GetSpellInfo(7328)]	= true, -- Redemption
	-- priest
	[GetSpellInfo(2006)]	= true, -- Resurrection
	-- shaman
	[GetSpellInfo(2008)]	= true, -- Ancestral Spirit
}
if isWrath or isMainline then
	-- druid
	single_res_spells_by_name[GetSpellInfo(50769)] = true -- Revive
end
if isMainline then
	-- monk
	single_res_spells_by_name[GetSpellInfo(115178)] = true -- Resuscitate
	-- evoker
	single_res_spells_by_name[GetSpellInfo(361227)] = true -- Return
end

function addon:GetUpdatedSpells()
	local newSpellName, newSpellID
	local i = 1

	-- first, determine if res spells and ranks are in the player's spellbook
	while true do
		newSpellName = GetSpellName(i, BOOKTYPE_SPELL)
		if not newSpellName then
			-- end of the spellbook; break the while loop
			break
		end

		if single_res_spells_by_name[newSpellName] then
			-- get the spellID here, where there is a table match
			newSpellID = select(7, GetSpellInfo(newSpellName))
			-- mainline has no spell ranks; break the while loop when we match
			if isMainline then
				break
			end
		end
		-- CE and Wrath have ranks; keep looping the spellbook until we run out of spells
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

	-- known mass res spell
	local newMassResName, newMassResSpellID
	if isMainline then
		newMassResName = mass_res_spells_by_class[player_class]
		newMassResSpellID = newMassResName and select(7, GetSpellInfo(newMassResName))
		knownMassResSpell = newMassResSpellID and IsSpellKnown(newMassResSpellID) and newMassResName
	end
end

-- bind the single res keys
function addon:BindResKeys()
	if not knownResSpell then
		if db.enableFeedback then
			self:Print(L["You do not know a single target res spell, cannot bind keys."])
		end
		db.char.resKey = nil
		db.char.manualResKey = nil
		return
	end
	local ok

	if db.char.resKey then
		ok = SetBindingClick(db.char.resKey, resButton:GetName(), "LeftClick")
		if ok then
			if db.enableFeedback then
				self:Print(L["Single target key bound."])
			end
		end
	end

	if db.char.manualResKey then
		ok = SetBindingSpell(db.char.manualResKey, knownResSpell)
		if ok then
			if db.enableFeedback then
				self:Print(L["Manual target key bound."])
			end
		end
	end

	-- save the bindings per characher so they persist through logout
	SaveBindings(CHARACTER_BINDINGS)
end

-- bind the mass res key
function addon:BindMassResKey()
	if not knownMassResSpell then
		if db.enableFeedback then
			self:Print(L["You do not know a mass res spell, cannot bind key."])
		end
		db.char.massResKey = nil
		return
	end
	local ok

	if db.char.massResKey then
		ok = SetBindingClick(db.char.massResKey, massResButton:GetName(), "LeftClick")
		if ok then
			if db.enableFeedback then
				self:Print(L["Mass res key bound."])
			end
		end
	end

	-- save the bindings per characher so they persist through logout
	SaveBindings(CHARACTER_BINDINGS)
end

-- unbind all the keys
function addon:UnbindAllResAndMassResKeys()
	if db.char.resKey then
		SetBinding(db.char.resKey)
	end
	if db.char.manualResKey then
		SetBinding(db.char.manualResKey)
	end
	if db.char.massResKey then
		SetBinding(db.char.massResKey)
	end
	SaveBindings(CHARACTER_BINDINGS)
end

-- smart res functions that pick dead targets intelligently
function addon:SingleResurrection()
end

-- smart mass res function
function addon:MassRessurection()
end