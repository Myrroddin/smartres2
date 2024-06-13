---@class addon: AceAddon, AceConsole-3.0, AceEvent-3.0, AceComm-3.0, AceSerializer-3.0
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
addon.LSM = LibStub("LibSharedMedia-3.0")

-- register media (fonts, borders, backgrounds, etc) with LibSharedMedia-3.0
local MediaType_FONT = addon.LSM.MediaType.FONT or "font"
addon.LSM:Register(MediaType_FONT, "Olde English", [[Interface\AddOns\SmartRes2\Media\Fonts\OldeEnglish.ttf]])

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

-- create the default user options and shortcut variable
local db, options
local defaults = {
	profile = {
		enabled = true,
		switchToCombatRes = true,
		minimap = {
			hide = false,
			lock = true,
			showInCompartment = true,
			useClassIconForBroker = true,
			lockOnDegree = true,
			minimapPos = 60
		},
		-- ["Character - Realm"]
		["*"] = {
			resKey = "",
			manualResKey = "",
			massResKey = ""
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
	self:BindManualResKey(self.knownCombatResSpell)
end

function addon:LeavingCombat()
	if not db.switchToCombatRes then return end
	self:BindManualResKey(self.knownResSpell)
end

-- function that returns the player's class resurrection spell icon or default_icon
local res_spells_by_class = {
	["PRIEST"]					= GetSpellInfo(2006),	-- Resurrection
	["SHAMAN"]					= GetSpellInfo(2008),	-- Ancestral Spirit
	["PALADIN"]					= GetSpellInfo(7328),	-- Redemption
	["DRUID"]					= GetSpellInfo(50769),	-- Revive
	["MONK"]					= GetSpellInfo(115178),	-- Resuscitate
	["EVOKER"]					= GetSpellInfo(361227),	-- Return
}

function addon:GetIconForBrokerDisplay()
	local player_spell = res_spells_by_class[player_class]
	local player_spell_icon = select(3, GetSpellInfo(player_spell))

	local icon = (player_spell and player_spell_icon) or default_icon
	return icon
end

-- table of res spells the player might know
local single_res_spells_by_name = {
	[GetSpellInfo(2006)]		= true, -- Resurrection
	[GetSpellInfo(2008)]		= true, -- Ancestral Spirit
	[GetSpellInfo(7328)]		= true, -- Redemption
	[GetSpellInfo(50769)]		= true, -- Revive
	[GetSpellInfo(115178)]		= true, -- Resuscitate
	[GetSpellInfo(212051)]		= true, -- Reawaken
}

-- table of combat res spells the player might know
local combat_res_spells_by_name = {
	[GetSpellInfo(20484)]		= true, -- Rebirth (Druid)
	[GetSpellInfo(20707)]		= true, -- Soulstone (Warlock)
	[GetSpellInfo(61999)]		= true, -- Raise Ally (Death Knight)
	[GetSpellInfo(391054)]		= true, -- Intercession (Paladin)
	[GetSpellInfo(159931)]		= true, -- Gift of Chi-Ji (Hunter's crane pet)
	[GetSpellInfo(159956)]		= true, -- Dust of Life (Hunter's moth pet)
}

-- table of mass res spells the player might know
local mass_res_spells_by_name = {
	[GetSpellInfo(212036)]		= true, -- Mass Resurrection
	[GetSpellInfo(212040)]		= true, -- Revitalize
	[GetSpellInfo(212048)]		= true, -- Ancestral Vision
	[GetSpellInfo(212051)]		= true, -- Reawaken
	[GetSpellInfo(212056)]		= true, -- Absolution
	[GetSpellInfo(361178)]		= true, -- Mass Return
}

function addon:GetUpdatedSpells()
	self.knownResSpell, self.knownCombatResSpell, self.knownMassResSpell = nil, nil, nil
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

		if mass_res_spells_by_name[newSpellName] then
			self.knownMassResSpell = newSpellName
		end

		-- loop through the spellbook until the end
		i = i + 1
	end

	-- check for Hunter pets
	local numSpells = HasPetSpells()
	if numSpells then
		for index = 1, numSpells do
			newSpellName = GetSpellBookItemName(index, BOOKTYPE_PET)
			if combat_res_spells_by_name[newSpellName] then
				self.knownCombatResSpell = newSpellName
			end
		end
	end

	-- remind the player that keys can be found as we found spells
	if self.knownResSpell and db[player_name].resKey == "" then
		self:Print(L["Regular res spell known. You should bind the single target key."])
	end
	if self.knownCombatResSpell or self.knownResSpell and db[player_name].manualResKey == "" then
		self:Print(L["Regular or combat res spell known. You should bind the manual target key."])
	end
	if self.knownMassResSpell and db[player_name].massResKey == "" then
		self:Print(L["Mass res spell known. You should bind the mass res key."])
	end

	self:BindAutoResKey()
	self:BindManualResKey()
	self:BindMassResKey()
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
function addon:BindManualResKey(regularOrCombatResSpell)
	regularOrCombatResSpell = regularOrCombatResSpell or self.knownResSpell

	if regularOrCombatResSpell then
		if db[player_name].manualResKey == "" then
			-- the user cleared the manual res spell keybind
			SetBinding(db[player_name].manualResKey)
		else
			-- there is a non-empty string to bind
			SetBindingSpell(db[player_name].manualResKey, regularOrCombatResSpell)
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
	local tempMassResKey = db[player_name].massResKey

	-- temporarily set the user keybinds to empty strings
	db[player_name].resKey = ""
	db[player_name].manualResKey = ""
	db[player_name].massResKey = ""

	-- unbind the keys
	SetBinding(db[player_name].resKey)
	SetBinding(db[player_name].manualResKey)
	SetBinding(db[player_name].massResKey)

	if not UnitAffectingCombat("player") then
		-- save the bindings per character so they persist through logout
		SaveBindings(Enum.BindingSet.Character)
	end

	-- restore the user settings
	db[player_name].resKey = tempResKey
	db[player_name].manualResKey = tempManualResKey
	db[player_name].massResKey = tempMassResKey
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
	LibStub("AceConfigRegistry-3.0"):NotifyChange("SmartRes2")
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