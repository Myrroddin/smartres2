---@diagnostic disable: duplicate-set-field, undefined-field
---@class addon: AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0
-- File Date: @file-date-iso@

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
local Registry = LibStub("AceConfigRegistry-3.0")

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

-- create the default user options and shortcut variable
local db, options
local defaults = {
	profile = {
		enabled = true,
		switchToCombatRes = true,
		minimap = {
			hide = false,
			lock = true,
			useClassIconForBroker = true,
			lockOnDegree = true,
			minimapPos = 60
		},
		-- ["Character - Realm"]
		["*"] = {
			resKey = "",
			manualResKey = ""
		}
	}
}

-- Ace3 embedded functions
function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	-- shortcut
	db = self.db.profile

	-- enable or disable the addon based on the profile
	self:SetEnabledState(db.enabled)

	-- populate the options table
	options = self:GetOptions()

	-- create Profiles
	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 200

	-- add "About" panel from LibAboutPanel-2.0
	options.args.aboutPanel = self:AboutOptionsTable("SmartRes2")
	options.args.aboutPanel.order = -1 -- last tab in the options panel

	-- register the options table with AceConfig and add the options table to the Blizzard Options UI
	LibStub("AceConfig-3.0"):RegisterOptionsTable("SmartRes2", options)
	Dialog:AddToBlizOptions("SmartRes2")

	-- create slash commands
	self:RegisterChatCommand("smartres2", "ChatCommands")
	self:RegisterChatCommand("smartres", "ChatCommands")
	self:RegisterChatCommand("sr", "ChatCommands")

	-- Broker display
	local launcher = LibStub("LibDataBroker-1.1"):NewDataObject("SmartRes2", {
		type = "launcher",
		tocname = "SmartRes2",
		label = "SmartRes2",
		text = "SmartRes2",
		icon = (db.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay()) or default_icon,
		OnClick = function(_, button)
			if button == "RightButton" then
				self:OpenOrCloseUX()
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
	self:RegisterEvent("SPELLS_CHANGED", "GetUpdatedSpells")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "EnteringCombat")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "LeavingCombat")
	self:GetUpdatedSpells()
	for moduleName, module in self:IterateModules() do
		-- verify a module exists before messing with its settings
		if moduleName then
			-- check if a module should be enabled, and if so, enable it
			local mns = self.db:GetNamespace(module:GetName(), true)
			local enabledStatus = mns and mns.profile.enabled
			if enabledStatus then
				if not module:IsEnabled() then
					self:EnableModule(moduleName)
				end
			end
		end
	end
end

function addon:OnDisable()
	self:UnregisterAllEvents()
	self:UnbindAllResAndMassResKeys()
	for moduleName in self:IterateModules() do
		-- verify a module exists before disabling it
		if moduleName then
			self:DisableModule(moduleName)
		end
	end
end

function addon:RefreshConfig()
	self.db:ResetProfile(false, true)
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
	local iconTexture = (db.minimap.useClassIconForBroker and self:GetIconForBrokerDisplay()) or default_icon
	button.icon:SetTexture(iconTexture)
	self:GetUpdatedSpells()
end

-- chat commands handler
function addon:ChatCommands()
	self:OpenOrCloseUX()
end

-- function to open/close the UX panel
function addon:OpenOrCloseUX()
	if Dialog.OpenFrames["SmartRes2"] then
		Dialog:Close("SmartRes2")
	else
		Dialog:Open("SmartRes2")
	end
end

-- combat status checks to swap between combat res spell and regular res spell
function addon:EnteringCombat()
	if not db.switchToCombatRes then return end
	if db[player_name].manualResKey == "" then return end
	if self.knownCombatResSpell then
		self:Print(L["Manual res key set to %s"], self.knownCombatResSpell)
		SetBindingSpell(db[player_name].manualResKey, self.knownCombatResSpell)
	end
end

function addon:LeavingCombat()
	if not db.switchToCombatRes then return end
	if db[player_name].manualResKey == "" then return end
	if self.knownResSpell then
		self:Print(L["Manual res key set to %s"], self.knownResSpell)
		SetBindingSpell(db[player_name].manualResKey, self.knownResSpell)
	end
end

-- function that returns the player's class resurrection spell icon or default_icon
local res_spells_by_class = {
	["PRIEST"] = GetSpellInfo(2006),		-- Resurrection
	["SHAMAN"] = GetSpellInfo(2008),		-- Ancestral Spirit
	["PALADIN"] = GetSpellInfo(7328),		-- Redemption
}

function addon:GetIconForBrokerDisplay()
	local player_spell = res_spells_by_class[player_class]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_icon
	return icon
end

-- table of res spells the player might know
local single_res_spells_by_name = {
	[GetSpellInfo(2006)]	= true, -- Resurrection
	[GetSpellInfo(2008)]	= true, -- Ancestral Spirit
	[GetSpellInfo(7328)]	= true, -- Redemption
}

-- table of combat res spells the player might know
local combat_res_spells_by_name = {
	[GetSpellInfo(20484)]		= true, -- Rebirth (Druid)
	[GetSpellInfo(20707)]		= true, -- Soulstone (Warlock)
}

function addon:GetUpdatedSpells()
	self.knownResSpell, self.knownCombatResSpell = nil, nil
	local newSpellName

	local i = 1
	-- determine if res spells are in the player's spellbook
	while GetSpellBookItemName(i, BOOKTYPE_SPELL) do
		newSpellName = GetSpellBookItemName(i, BOOKTYPE_SPELL)

		if single_res_spells_by_name[newSpellName] then
			self.knownResSpell = newSpellName
		end

		if combat_res_spells_by_name[newSpellName] then
			self.knownCombatResSpell = newSpellName
		end

		-- loop through the spellbook until the end
		i = i + 1
	end

	-- remind the player that keys can be found as we found spells
	if self.knownResSpell and db[player_name].resKey == "" then
		self:Print(L["Regular res spell known. You should bind the single target key."])
	end
	if self.knownCombatResSpell or self.knownResSpell and db[player_name].manualResKey == "" then
		self:Print(L["Regular or combat res spell known. You should bind the manual target key."])
	end

	self:BindAutoResKey()
	self:BindManualResKey()
end

-- bind the single auto res key
function addon:BindAutoResKey()
	if self.knownResSpell then
		if db[player_name].resKey == "" then
			-- the user cleared the res spell keybind
			SetBinding(db[player_name].resKey)
		else
			-- there is a non-empty string to bind
			SetBindingClick(db[player_name].resKey, resButton:GetName(), "LeftClick")
		end
	else
		-- the character does not know a res spell
		db[player_name].resKey = ""
		SetBinding(db[player_name].resKey)
	end

	if not UnitAffectingCombat("player") then
		-- save the bindings per character so they persist through logout
		SaveBindings(Enum.BindingSet.Character)
	end
end

-- bind the manual res key
function addon:BindManualResKey()
	if self.knownResSpell then
		if db[player_name].manualResKey == "" then
			-- the user cleared the manual res spell keybind
			SetBinding(db[player_name].manualResKey)
		else
			-- there is a non-empty string to bind
			SetBindingSpell(db[player_name].manualResKey, self.knownResSpell)
		end
	else
		-- the character does not know a res spell
		db[player_name].manualResKey = ""
		SetBinding(db[player_name].manualResKey)
	end

	if not UnitAffectingCombat("player") then
		-- save the bindings per character so they persist through logout
		SaveBindings(Enum.BindingSet.Character)
	end
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

	if not UnitAffectingCombat("player") then
		-- save the bindings per character so they persist through logout
		SaveBindings(Enum.BindingSet.Character)
	end

	-- restore the user settings
	db[player_name].resKey = tempResKey
	db[player_name].manualResKey = tempManualResKey
end

-- smart res functions that pick dead targets intelligently
function addon:SingleResurrection()
end

-------------------- Public APIs --------------------
-- modules register their options table with this function
function addon:RegisterModuleOptions(moduleName, moduleOptions)
	options = options or self:GetOptions()
	local errorText = ""
	if type(moduleName) ~= "string" then
		errorText = format("Arg 'moduleName' string expected, got type '%s'", type(moduleName))
		error(errorText, 2)
	end
	if type(moduleOptions) ~= "table" then
		errorText = format("Arg 'moduleOptions' table expected, got type '%s'", type(moduleOptions))
		error(errorText, 2)
	end
	options.args[moduleName] = options.args[moduleName] or moduleOptions
	options.args[moduleName].disabled = moduleOptions.disabled or function() return not addon.db.profile.enabled end
	Registry:NotifyChange("SmartRes2")
end

-- translate input table and return localizations for keys
function addon:LocalizeTableKeys(inputTable, myL)
	myL = myL or L
	local errorText, outputTable = "", {}
	-- check inputTable for validity
	if type(inputTable) ~= "table" then
		errorText = format("Arg 'inputTable' table expected, got type '%s'", type(inputTable))
		error(errorText, 2)
	end

    for key, value in pairs(inputTable) do
		-- localize key if value is not nil
		if value ~= nil then
			GetOrCreateTableEntry(outputTable, key, myL[key])
		end
    end
    return outputTable
end

-- round to N decimals
function addon:Round(value, decimals)
	local errorText = ""
	if type(value) ~= "number" then
		errorText = format("Arg 'value' number expected, got type %s", type(value))
		error(errorText, 2)
	end
	if decimals and type(decimals) ~= "number" then
		errorText = format("Arg 'decimals' nil or number expected, got type %s", type(decimals))
		error(errorText, 2)
	end
	local mult = 10 ^ (decimals or 0)
	return floor(value * mult + 0.5) / mult
end