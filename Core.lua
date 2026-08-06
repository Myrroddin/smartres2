-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Core
--
-- Responsibilities:
-- - Initialize saved variables, profiles, options, slash commands, and Broker.
-- - Coordinate addon and module lifecycle state.
-- - Create secure resurrection keybinding buttons and select smart targets.
-- - Provide shared icon, name, notification, and module-option services.
-- - Register SmartRes2 visual resources and the Bars skinning group.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local _G = _G
local CreateFrame = CreateFrame
local DEFAULT = DEFAULT
local GetNumGroupMembers = GetNumGroupMembers
local GetSpellInfo = C_Spell.GetSpellInfo
local GetSpellTexture = C_Spell.GetSpellTexture
local GetTime = GetTime
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsPlayerNeutral = IsPlayerNeutral
local IsSpellInRange = C_Spell.IsSpellInRange
local IsSpellKnown = C_SpellBook.IsSpellKnown
local IsSpellUsable = C_Spell.IsSpellUsable
local LibStub = LibStub
local math_floor = math.floor
local math_random = math.random
local NO = NO
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR
local OKAY = OKAY
local pairs = pairs
local POWER_TYPE = Enum.PowerType
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local Reload = C_UI.Reload
local StaticPopup_Show = StaticPopup_Show
local StaticPopupDialogs = StaticPopupDialogs
local string_format = string.format
local type = type
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitClassBase = UnitClassBase
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitGUID = UnitGUID
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitIsVisible = UnitIsVisible
local UnitLevel = UnitLevel
local UnitNameFromGUID = UnitNameFromGUID
local UnitNameUnmodified = UnitNameUnmodified
local UnitPowerMax = UnitPowerMax
local UnitTokenFromGUID = UnitTokenFromGUID
local UNKNOWN = UNKNOWN
local YES = YES

-- --------------------------------------------------------------------
-- Addon / libraries
-- --------------------------------------------------------------------

---@class SmartRes2LibDBIcon: LibDBIcon-1.0
---@field IsButtonCompartmentAvailable fun(self: SmartRes2LibDBIcon): boolean|nil

---@class SmartRes2: AceAddon, AceEvent-3.0, AceConsole-3.0, LibAboutPanel-2.0, LibResInfo-2.0
---@field db AceDBObject-3.0!
---@field GetOptions function
---@field LibDBIcon SmartRes2LibDBIcon
---@field LSM LibSharedMedia-3.0
---@field Masque table?
---@field MasqueAPIVersion number?
---@field MasqueBarsGroup table?
---@field PLAYER_GUID string?
local addon = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceEvent-3.0", "AceConsole-3.0", "LibAboutPanel-2.0", "LibResInfo-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
---@type SmartRes2LibDBIcon
addon.LibDBIcon = LibStub("LibDBIcon-1.0")
addon.LSM = LibStub("LibSharedMedia-3.0")
addon.Masque, addon.MasqueAPIVersion = LibStub("Masque", true)

-- Modules share event, console, and resurrection callback services.
addon:SetDefaultModuleLibraries("AceEvent-3.0", "AceConsole-3.0", "LibResInfo-2.0")

-- --------------------------------------------------------------------
-- Lifecycle constants and state
-- --------------------------------------------------------------------

local DB_RESET_POPUP = "SMARTRES2_DB_RESET"
local KEYBIND_TRIGGER_RELOAD_POPUP = "SMARTRES2_KEYBIND_TRIGGER_RELOAD"
local SMARTRES2_DB_VERSION = 1

local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

---@type table
local db
---@type table
local global
local options
local smartResButton, manualResButton, combatResButton, massResButton

-- --------------------------------------------------------------------
-- Static configuration and spell data
-- --------------------------------------------------------------------

local DEFAULT_ICON_SPELL_ID = 2006 -- Priest: Resurrection
local HUNTER_REVIVE_PET_SPELL_ID = 982 -- Revive Pet
local INVALID_UNIT = "SmartRes2InvalidUnit"
local MANA_POWER_TYPE = POWER_TYPE.Mana or 0
local MASS_RESURRECTION_MISTS_SPELL_ID = 83968 -- Mass Resurrection
local MASS_RESURRECTION_RETAIL_SPELL_ID = 212036 -- Mass Resurrection
local PLAYER_CLASS_FILENAME = UnitClassBase("player")

local MASS_RESURRECTION_RETAIL_SPELL_INFO = GetSpellInfo(MASS_RESURRECTION_RETAIL_SPELL_ID)
local MASS_RESURRECTION_MISTS_SPELL_INFO = GetSpellInfo(MASS_RESURRECTION_MISTS_SPELL_ID)
local MASS_RESURRECTION_FALLBACK_SPELL_INFO = GetSpellInfo(DEFAULT_ICON_SPELL_ID)
local MASS_RESURRECTION_SPELL_INFO = MASS_RESURRECTION_RETAIL_SPELL_INFO
	or MASS_RESURRECTION_MISTS_SPELL_INFO
	or MASS_RESURRECTION_FALLBACK_SPELL_INFO
local MASS_RESURRECTION_ICON = MASS_RESURRECTION_SPELL_INFO and MASS_RESURRECTION_SPELL_INFO.iconID
local MASS_RESURRECTION_ICON_SPELL_ID = MASS_RESURRECTION_SPELL_INFO and MASS_RESURRECTION_SPELL_INFO.spellID

-- Broker and minimap icons use non-combat resurrection spells so the launcher
-- identity does not change with situational combat-resurrection priority.
local classResIconSpellIDs = {
	DRUID	= 50769,	-- Revive
	EVOKER	= 361227,	-- Return
	HUNTER	= 982,		-- Revive Pet
	MONK	= 115178,	-- Resuscitate
	PALADIN	= 7328,		-- Redemption
	PRIEST	= 2006,		-- Resurrection
	SHAMAN	= 2008,		-- Ancestral Spirit
}

local normalSingleResSpellIDs = {
	DRUID = {
		50769, -- Revive
	},
	EVOKER = {
		361227, -- Return
	},
	MONK = {
		115178, -- Resuscitate
	},
	PALADIN = {
		7328, -- Redemption Rank 1
		10322, -- Redemption Rank 2
		10324, -- Redemption Rank 3
		20772, -- Redemption Rank 4
		20773, -- Redemption Rank 5
		48949, -- Redemption Rank 6
		48950, -- Redemption Rank 7
	},
	PRIEST = {
		2006, -- Resurrection Rank 1
		2010, -- Resurrection Rank 2
		10880, -- Resurrection Rank 3
		10881, -- Resurrection Rank 4
		20770, -- Resurrection Rank 5
		25435, -- Resurrection Rank 6
		48171, -- Resurrection Rank 7
	},
	SHAMAN = {
		2008, -- Ancestral Spirit Rank 1
		20609, -- Ancestral Spirit Rank 2
		20610, -- Ancestral Spirit Rank 3
		20776, -- Ancestral Spirit Rank 4
		20777, -- Ancestral Spirit Rank 5
		25590, -- Ancestral Spirit Rank 6
		49277, -- Ancestral Spirit Rank 7
	},
}

local combatResSpellIDs = {
	DEATHKNIGHT = {
		61999, -- Raise Ally
	},
	DRUID = {
		20484, -- Rebirth Rank 1
		20739, -- Rebirth Rank 2
		20742, -- Rebirth Rank 3
		20747, -- Rebirth Rank 4
		20748, -- Rebirth Rank 5
		26994, -- Rebirth Rank 6
		48477, -- Rebirth Rank 7
	},
	PALADIN = {
		391054, -- Intercession
	},
	WARLOCK = {
		20707, -- Soulstone Resurrection Rank 1
		20762, -- Soulstone Resurrection Rank 2
		20763, -- Soulstone Resurrection Rank 3
		20764, -- Soulstone Resurrection Rank 4
		20765, -- Soulstone Resurrection Rank 5
		27239, -- Soulstone Resurrection Rank 6
		47883, -- Soulstone Resurrection Rank 7
	},
}

local massResSpellIDs = {
	DRUID = {
		212040, -- Revitalize
	},
	EVOKER = {
		361178, -- Mass Return
	},
	MONK = {
		212051, -- Reawaken
	},
	PALADIN = {
		212056, -- Absolution
	},
	PRIEST = {
		212036, -- Mass Resurrection
	},
	SHAMAN = {
		212048, -- Ancestral Vision
	},
}

-- Bundled Masque skin data
local masqueNeuronSkin = {
	API_VERSION = addon.MasqueAPIVersion,
	Shape = "Square",

	-- Info
	Description = L["The Neuron Masque skin bundled with SmartRes2."],
	Author = "Soyier",
	Websites = {
		"https://www.curseforge.com/wow/addons/masque-neuron",
		"https://github.com/brittyazel/Masque_Neuron",
	},

	-- Skin
	Backdrop = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Backdrop.png]],
		Width = 42,
		Height = 42,
		Color = {0, 0, 0, 0.6},
		DrawLayer = "BACKGROUND",
		DrawLevel = -1,
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
		UseColor = true,
	},

	Icon = {
		Width = 29,
		Height = 29,
		TexCoords = {0.08, 0.92, 0.08, 0.92},
		DrawLayer = "BACKGROUND",
		DrawLevel = 0,
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
	},

	SlotIcon = "Icon",

	Normal = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Normal.png]],
		Width = 42,
		Height = 42,
		Color = {0.2, 0.2, 0.2, 1},
	},

	Pushed = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Overlay.png]],
		Width = 42,
		Height = 42,
		BlendMode = "BLEND",
		DrawLayer = "ARTWORK",
		DrawLevel = 0,
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
		Color = {1, 1, 1, 0.5},
	},

	Flash = {
		Texture = [[Interface\Buttons\UI-QuickslotRed]],
		Width = 42,
		Height = 42,
		TexCoords = {0.2, 0.8, 0.2, 0.8},
		Color = {1, 1, 1, 0.75},
		BlendMode = "BLEND",
		DrawLayer = "ARTWORK",
		DrawLevel = 1,
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
	},

	HotKey = {
		JustifyH = "RIGHT",
		JustifyV = "MIDDLE",
		DrawLayer = "ARTWORK",
		Width = 42,
		Height = 10,
		Point = "TOPRIGHT",
		RelPoint = "TOPRIGHT",
		OffsetX = -3,
		OffsetY = -4,
	},

	Count = {
		JustifyH = "RIGHT",
		JustifyV = "MIDDLE",
		DrawLayer = "ARTWORK",
		Width = 42,
		Height = 10,
		Point = "BOTTOMRIGHT",
		RelPoint = "BOTTOMRIGHT",
		OffsetX = -3,
		OffsetY = 4,
	},

	Duration = {
		JustifyH = "CENTER",
		JustifyV = "MIDDLE",
		DrawLayer = "ARTWORK",
		Width = 42,
		Height = 10,
		Point = "TOP",
		RelPoint = "BOTTOM",
		OffsetX = 0,
		OffsetY = -2,
	},

	Checked = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Border.png]],
		Width = 42,
		Height = 42,
		BlendMode = "ADD",
		DrawLayer = "OVERLAY",
		DrawLevel = 0,
		Color = {1, 1, 1, 0.5},
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
	},

	SlotHighlight = "Checked",

	Name = {
		Width = 42,
		Height = 10,
		JustifyH = "CENTER",
		JustifyV = "BOTTOM",
		OffsetY = 3,
	},

	Border = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Border.png]],
		Width = 42,
		Height = 42,
		BlendMode = "ADD",
		DrawLayer = "OVERLAY",
		DrawLevel = 0,
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
	},

	DebuffBorder = "Border",
	EnchantBorder = "Border",
	IconBorder = "Border",

	Gloss = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Gloss.png]],
		Width = 42,
		Height = 42,
		BlendMode = "ADD",
		Color = {1, 1, 1, 0.15},
	},

	AutoCastable = {
		Texture = [[Interface\Buttons\UI-AutoCastableOverlay]],
		BlendMode = "BLEND",
		DrawLayer = "OVERLAY",
		DrawLevel = 1,
		Width = 42,
		Height = 42,
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0.5,
		OffsetY = -0.5,
	},

	Highlight = {
		Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Highlight.png]],
		Width = 37,
		Height = 37,
		BlendMode = "ADD",
		DrawLayer = "HIGHLIGHT",
		Color = {1, 1, 1, 0.75},
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0.5,
		OffsetY = -0.5,
	},

	AutoCastShine = {
		Width = 32,
		Height = 32,
		OffsetX = 1,
		OffsetY = -1,
		AboveNormal = true,
	},

	Cooldown = {
		Width = 28,
		Height = 28,
		Color = {0, 0, 0, 0.6},
		Point = "CENTER",
		RelPoint = "CENTER",
		OffsetX = 0,
		OffsetY = 0,
	},
}

-- Database migration notice
StaticPopupDialogs[DB_RESET_POPUP] = {
	text = L["SmartRes2 settings were reset because this version uses a new settings layout."],
	button1 = OKAY,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs[KEYBIND_TRIGGER_RELOAD_POPUP] = {
	text = L["Changing this setting will reload your UI. Continue?"],
	button1 = OKAY,
	OnAccept = function()
		Reload()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = false,
	preferredIndex = 3,
}

-- Saved variable defaults
local defaults = {
	global = {
		resetGlobalOnProfileChange = false,
		useClassIconForBroker = true,
		minimap = {
			hide = false,
			lock = true,
			lockOnDegree = true,
			showInCompartment = true,
			minimapPos = 60,
		},
	},
	profile = {
		enabled = true,
		notifySelf = true,
		useClassColorsForSystemMessages = true,
		useFullNameForSystemMessages = true,
		useMasque = true,
		waitingDelay = 7.5,
		keybindTrigger = "AnyDown",
	},
}

-- --------------------------------------------------------------------
-- Shared utilities
-- --------------------------------------------------------------------

local function GetColorByte(value)
	return math_floor((value or 1) * 255 + 0.5)
end

local function GetSpellIcon(spellID)
	return GetSpellTexture(spellID)
end

local function GetClassColoredUnitName(unit, includeRealm)
	if not unit then
		return nil
	end

	local unitName, unitServer = UnitNameUnmodified(unit)
	if not unitName then
		return nil
	end

	if includeRealm and unitServer and unitServer ~= "" then
		unitName = unitName .. "-" .. unitServer
	end

	return addon:GetClassColoredName(unitName, UnitClassBase(unit))
end

function addon:GetResurrectionIconForClass(classFilename, useDefault)
	local spellID = classFilename and classResIconSpellIDs[classFilename]
	local icon = spellID and GetSpellIcon(spellID)

	if icon then
		return icon
	end

	if useDefault ~= false then
		return GetSpellIcon(DEFAULT_ICON_SPELL_ID)
	end
end

function addon:GetMassResurrectionIcon()
	return GetSpellIcon(MASS_RESURRECTION_ICON_SPELL_ID) or MASS_RESURRECTION_ICON
end

function addon:IsMasqueAvailable()
	return self.Masque ~= nil
end

function addon:GetClassColoredName(name, classFilename, fallbackColor)
	if not name then
		return nil
	end

	local classColor = classFilename and RAID_CLASS_COLORS[classFilename] or fallbackColor

	if classColor then
		return string_format(
			"|cff%02x%02x%02x%s|r",
			GetColorByte(classColor.r),
			GetColorByte(classColor.g),
			GetColorByte(classColor.b),
			name
		)
	end

	return name
end

function addon:GetUnitNameFromGUID(guid, includeRealm)
	if not guid or guid == "UNKNOWN" then
		return UNKNOWN
	end

	local unitName, unitServer

	if UnitNameFromGUID then
		unitName, unitServer = UnitNameFromGUID(guid)
	else
		local unitToken = UnitTokenFromGUID(guid)

		if unitToken then
			unitName, unitServer = UnitNameUnmodified(unitToken)
		end
	end

	if includeRealm and unitName and unitServer and unitServer ~= "" then
		return unitName .. "-" .. unitServer
	end

	return unitName or UNKNOWN
end

---@param message string
---@param unit string?
function addon:NotifySelf(message, unit)
	if not db.notifySelf then
		return
	end

	if unit then
		local unitName

		if db.useClassColorsForSystemMessages then
			unitName = GetClassColoredUnitName(unit, db.useFullNameForSystemMessages)
		else
			local unitServer

			unitName, unitServer = UnitNameUnmodified(unit)

			if db.useFullNameForSystemMessages and unitName and unitServer and unitServer ~= "" then
				unitName = unitName .. "-" .. unitServer
			end
		end

		if unitName then
			message = string_format(message, unitName)
		end
	end

	self:Print(message)
end

-- --------------------------------------------------------------------
-- Resurrection spell and target helpers
-- --------------------------------------------------------------------

local function IsKnownSpell(spellID)
	return IsSpellKnown(spellID) == true
end

local function GetHighestKnownSpell(spellIDs)
	if not spellIDs then
		return nil
	end

	for index = #spellIDs, 1, -1 do
		local spellID = spellIDs[index]

		if IsKnownSpell(spellID) then
			return spellID
		end
	end
end

local function IsUsableSpell(spellID)
	local isUsable, insufficientPower = IsSpellUsable(spellID)

	if insufficientPower then
		addon:NotifySelf(L["You do not have enough power to cast that spell."])
		return false
	end

	if not isUsable then
		addon:NotifySelf(L["You cannot cast that spell right now."])
		return false
	end

	return true
end

local function GetPlayerNormalSingleResSpellID()
	if PLAYER_CLASS_FILENAME == "HUNTER" then
		if IsKnownSpell(HUNTER_REVIVE_PET_SPELL_ID) then
			return HUNTER_REVIVE_PET_SPELL_ID
		end

		return nil
	end

	return GetHighestKnownSpell(normalSingleResSpellIDs[PLAYER_CLASS_FILENAME])
end

local function GetPlayerCombatResurrectionSpellID()
	return GetHighestKnownSpell(combatResSpellIDs[PLAYER_CLASS_FILENAME])
end

local function GetPlayerMassResurrectionSpellID()
	local spellID = GetHighestKnownSpell(massResSpellIDs[PLAYER_CLASS_FILENAME])
	if spellID then
		return spellID
	end

	if IsKnownSpell(MASS_RESURRECTION_MISTS_SPELL_ID) then
		return MASS_RESURRECTION_MISTS_SPELL_ID
	end
end

local function GetSmartResPriority(unit)
	local role = UnitGroupRolesAssigned(unit)

	if role == "HEALER" then
		return 1
	elseif role == "TANK" then
		return 2
	elseif role == "DAMAGER" then
		return 3
	elseif UnitPowerMax(unit, MANA_POWER_TYPE) > 0 then
		return 4
	end

	return 5
end

local function GetSelfResRemainingTime(optionInfo)
	if not optionInfo then
		return nil
	end

	if optionInfo.expirationTime then
		return optionInfo.expirationTime - GetTime()
	end

	for _, selfResOptionInfo in pairs(optionInfo) do
		if type(selfResOptionInfo) == "table" and selfResOptionInfo.expirationTime then
			local remainingTime = selfResOptionInfo.expirationTime - GetTime()

			if remainingTime > 0 then
				return remainingTime
			end
		end
	end
end

local function IsEligibleSmartResTarget(unit, spellID)
	if UnitIsUnit(unit, "player") then
		return false
	end

	if not UnitExists(unit) or not UnitIsPlayer(unit) then
		return false
	end

	if not UnitIsDead(unit) or UnitIsGhost(unit) then
		return false
	end

	if not UnitIsConnected(unit) or not UnitIsVisible(unit) then
		return false
	end

	if not IsSpellInRange(spellID, unit) then
		return false
	end

	if addon:IsUnitBeingResurrected(unit) then
		return false
	end

	local hasResWaiting, remainingTime = addon:UnitHasResWaiting(unit)
	if hasResWaiting and remainingTime > addon.db.profile.waitingDelay then
		return false
	end

	local canSelfRes, optionInfo = addon:UnitCanSelfResurrect(unit)
	local selfResRemainingTime = canSelfRes and GetSelfResRemainingTime(optionInfo)

	if selfResRemainingTime and selfResRemainingTime > addon.db.profile.waitingDelay then
		return false
	end

	return true
end

local function FindBestSmartResTarget(spellID)
	local bestUnit
	local bestPriority
	local bestLevel
	local bestTieCount = 0
	local groupType = "raid"
	local numGroupMembers = GetNumGroupMembers()

	if IsInGroup() and not IsInRaid() then
		groupType = "party"
		numGroupMembers = numGroupMembers - 1
	end

	for index = 1, numGroupMembers do
		local unit = groupType .. index

		if IsEligibleSmartResTarget(unit, spellID) then
			local priority = GetSmartResPriority(unit)
			local level = UnitLevel(unit)

			if not bestPriority
				or priority < bestPriority
				or (priority == bestPriority and level > bestLevel)
			then
				bestUnit = unit
				bestPriority = priority
				bestLevel = level
				bestTieCount = 1
			elseif priority == bestPriority and level == bestLevel then
				bestTieCount = bestTieCount + 1

				-- Reservoir sampling gives every tied candidate an equal chance
				-- without building a temporary list.
				if math_random(bestTieCount) == 1 then
					bestUnit = unit
				end
			end
		end
	end

	return bestUnit
end

-- --------------------------------------------------------------------
-- Secure resurrection buttons
-- --------------------------------------------------------------------

local function ClearSecureSpellButton(button)
	button:SetAttribute("spell", nil)
	button:SetAttribute("unit", nil)
end

local function SetSecureSpellButtonSpell(button, spellID)
	button:SetAttribute("spell", spellID)
	button:SetAttribute("unit", nil)
end

local function PrepareSmartResurrectionButton(button)
	if InCombatLockdown() or UnitAffectingCombat("player") then
		return
	end

	button:SetAttribute("unit", INVALID_UNIT)

	local spellID = GetPlayerNormalSingleResSpellID()
	if not spellID then
		addon:NotifySelf(L["You do not know a resurrection spell."])
		return
	end

	if not IsInGroup() then
		addon:NotifySelf(L["You are not in a group and cannot use this feature."])
		return
	end

	if addon:IsMassResBeingCast() then
		addon:NotifySelf(L["A mass resurrection is in progress. Exiting as there is nothing to do."])
		return
	end

	if not IsUsableSpell(spellID) then
		return
	end

	local targetUnit = FindBestSmartResTarget(spellID)
	if not targetUnit then
		addon:NotifySelf(L["No valid resurrection target found."])
		return
	end

	button:SetAttribute("unit", targetUnit)
end

local function PrepareRevivePetButton(button)
	if InCombatLockdown() or UnitAffectingCombat("player") then
		return
	end

	button:SetAttribute("spell", nil)
	button:SetAttribute("unit", nil)

	if not IsKnownSpell(HUNTER_REVIVE_PET_SPELL_ID) then
		addon:NotifySelf(L["You do not know Revive Pet."])
		return
	end

	if UnitExists("pet") and not UnitIsDead("pet") then
		addon:NotifySelf(L["Your pet is already alive."])
		return
	end

	if not IsUsableSpell(HUNTER_REVIVE_PET_SPELL_ID) then
		return
	end

	SetSecureSpellButtonSpell(button, HUNTER_REVIVE_PET_SPELL_ID)
end

local function PrepareManualResurrectionButton()
	local spellID = GetHighestKnownSpell(normalSingleResSpellIDs[PLAYER_CLASS_FILENAME])
	if not spellID then
		addon:NotifySelf(L["You do not know a resurrection spell."])
	end
end

local function PrepareCombatResurrectionButton()
	local spellID = GetPlayerCombatResurrectionSpellID()
	if not spellID then
		addon:NotifySelf(L["You do not know a combat resurrection spell."])
	end
end

local function PrepareMassResurrectionButton(button)
	if InCombatLockdown() or UnitAffectingCombat("player") then
		return
	end

	button:SetAttribute("spell", nil)
	button:SetAttribute("unit", nil)

	local spellID = GetPlayerMassResurrectionSpellID()
	if not spellID then
		addon:NotifySelf(L["You do not know a mass resurrection spell."])
		return
	end

	if not IsUsableSpell(spellID) then
		return
	end

	SetSecureSpellButtonSpell(button, spellID)
end

local function CreateSecureSpellButton(name, preClickFunction)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")

	-- The buttons exist only as secure CLICK-binding targets. They remain
	-- invisible and cannot receive ordinary mouse input.
	button:SetSize(1, 1)
	button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	button:SetAlpha(0)
	button:EnableMouse(false)

	local keybindTrigger = addon.db.profile.keybindTrigger
	button:RegisterForClicks(keybindTrigger)
	button:SetAttribute("registeredClickTrigger", keybindTrigger)
	button:SetAttribute("type", "spell")

	if preClickFunction then
		button:SetScript("PreClick", preClickFunction)
	end

	return button
end

local function CreateSecureButtons()
	if not smartResButton then
		if PLAYER_CLASS_FILENAME == "HUNTER" then
			smartResButton = CreateSecureSpellButton("SmartRes2SmartResButton", PrepareRevivePetButton)
		else
			smartResButton = CreateSecureSpellButton("SmartRes2SmartResButton", PrepareSmartResurrectionButton)
		end
	end

	if not manualResButton then
		manualResButton = CreateSecureSpellButton("SmartRes2ManualResButton", PrepareManualResurrectionButton)
	end

	if not combatResButton then
		combatResButton = CreateSecureSpellButton("SmartRes2CombatResButton", PrepareCombatResurrectionButton)
	end

	if not massResButton then
		massResButton = CreateSecureSpellButton("SmartRes2MassResButton", PrepareMassResurrectionButton)
	end
end

local function RefreshSecureButtonSpells()
	if InCombatLockdown() or UnitAffectingCombat("player") then
		return
	end

	if smartResButton then
		SetSecureSpellButtonSpell(smartResButton, GetPlayerNormalSingleResSpellID())
	end

	if manualResButton then
		if PLAYER_CLASS_FILENAME == "HUNTER" then
			ClearSecureSpellButton(manualResButton)
		else
			SetSecureSpellButtonSpell(manualResButton, GetPlayerNormalSingleResSpellID())
		end
	end

	if combatResButton then
		SetSecureSpellButtonSpell(combatResButton, GetPlayerCombatResurrectionSpellID())
	end

	if massResButton then
		SetSecureSpellButtonSpell(massResButton, GetPlayerMassResurrectionSpellID())
	end
end

-- --------------------------------------------------------------------
-- Masque registration
-- --------------------------------------------------------------------

local function RegisterMasque()
	if not addon.Masque then
		return
	end

	addon.Masque:AddSkin("SmartRes2: Neuron", masqueNeuronSkin)

	-- Creating the Bars group during Core initialization makes SmartRes2 visible
	-- in Masque's configuration before the Bars module creates its first icon.
	-- The static ID keeps the group identity stable if its display name changes.
	addon.MasqueBarsGroup = addon.Masque:Group("SmartRes2", L["Bars"], "Bars")
end

-- --------------------------------------------------------------------
-- Module management
-- --------------------------------------------------------------------

local function IsModuleProfileEnabled(moduleName)
	local moduleDB = addon.db:GetNamespace(moduleName, true)

	if moduleDB and moduleDB.profile.enabled ~= nil then
		return moduleDB.profile.enabled
	end

	return true
end

local function RefreshModules()
	if not addon:IsEnabled() then
		return
	end

	for moduleName, module in addon:IterateModules() do
		local moduleEnabled = IsModuleProfileEnabled(moduleName)

		if moduleEnabled and not module:IsEnabled() then
			addon:EnableModule(moduleName)
		elseif not moduleEnabled and module:IsEnabled() then
			addon:DisableModule(moduleName)
		end
	end
end

local function DisableModules()
	for moduleName, module in addon:IterateModules() do
		if module:IsEnabled() then
			addon:DisableModule(moduleName)
		end
	end
end

local function RefreshModuleConfigs()
	for _, module in addon:IterateModules() do
		local refreshConfig = module["RefreshConfig"]

		if type(refreshConfig) == "function" then
			refreshConfig(module)
		end
	end
end

-- --------------------------------------------------------------------
-- Broker / minimap
-- --------------------------------------------------------------------

local function GetBrokerIcon()
	if global.useClassIconForBroker then
		return addon:GetResurrectionIconForClass(PLAYER_CLASS_FILENAME)
	end

	return addon:GetResurrectionIconForClass(nil)
end

function addon:RefreshBrokerIcon()
	local button = self.LibDBIcon:GetMinimapButton("SmartRes2")

	if button and button.icon then
		button.icon:SetTexture(GetBrokerIcon())
	end
end

local function InitializeBroker()
	local brokerObjectData = {
		type = "launcher",
		tocname = "SmartRes2",
		label = "SmartRes2",
		icon = (GetBrokerIcon() or ""),
		OnClick = function(_, button)
			local barsModule = addon:GetModule("Bars", true)
			if button == "LeftButton" then
				if barsModule then
					local isLocked = barsModule:ToggleFrameLock()
					local lockedText = isLocked and YES or NO

					AceConfigRegistry:NotifyChange("SmartRes2")
					addon:NotifySelf(L["Bars are locked:"] .. " " .. lockedText)
				end
			elseif button == "MiddleButton" then
				if barsModule then
					barsModule:ToggleTestBars()
				end
			elseif button == "RightButton" then
				AceConfigDialog:Open("SmartRes2")
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("SmartRes2", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			tooltip:AddLine(L["Left click to toggle between locking/unlocking the bars."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:AddLine(L["Middle click to show or clear test bars."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:AddLine(L["Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:Show()
		end,
	}

	local brokerObject = LibDataBroker:NewDataObject("SmartRes2", brokerObjectData)

	addon.LibDBIcon:Register("SmartRes2", brokerObject, addon.db.global.minimap)
end

-- --------------------------------------------------------------------
-- Addon lifecycle
-- --------------------------------------------------------------------

-- Initialize the root database and Core-owned integrations before modules.
function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)

	local oldVersion = self.db.global.settingsVersion
	if (not oldVersion) or (oldVersion < SMARTRES2_DB_VERSION) then
		StaticPopup_Show(DB_RESET_POPUP)
		self.db:ResetDB(DEFAULT)
	end

	db = self.db.profile
	---@cast db -nil

	global = self.db.global
	---@cast global -nil

	global.settingsVersion = SMARTRES2_DB_VERSION

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	self:SetEnabledState(db.enabled)

	RegisterMasque()
	CreateSecureButtons()
	RefreshSecureButtonSpells()
	self.PLAYER_GUID = UnitGUID("player")

	options = self:GetOptions()
	options.args = options.args or {}

	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 900

	-- LibDualSpec augments the profile UI but remains under user control.
	local DualSpec = LibStub:GetLibrary("LibDualSpec-1.0", true)
	if DualSpec then
		DualSpec:EnhanceDatabase(self.db, "SmartRes2")
		DualSpec:EnhanceOptions(options.args.profiles, self.db)
	end

	options.args.aboutPanel = self:AboutOptionsTable("SmartRes2")
	options.args.aboutPanel.order = 1000

	LibStub("AceConfig-3.0"):RegisterOptionsTable("SmartRes2", options)
	AceConfigDialog:AddToBlizOptions("SmartRes2")

	self:RegisterChatCommand("smartres2", "ChatCommand")
	self:RegisterChatCommand("smartres", "ChatCommand")
	self:RegisterChatCommand("sr", "ChatCommand")

	InitializeBroker()

	-- Neutral characters can receive a new player GUID when choosing a faction.
	-- Register during initialization so this remains tracked while disabled.
	if (isMists or isMainline) and IsPlayerNeutral() then
		self:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
	end
end

function addon:OnEnable()
	self:RegisterEvent("SPELLS_CHANGED")
	RefreshModules()
end

function addon:OnDisable()
	self:UnregisterEvent("SPELLS_CHANGED")
	DisableModules()
end

-- Rebind cached database tables after profile operations. When requested, a
-- profile change resets the full database. The reset restores the toggle to
-- false, and the current settings schema version is reapplied afterward.
function addon:RefreshConfig(callback)
	local resetDatabase = global.resetGlobalOnProfileChange
	local registeredClickTrigger = smartResButton
		and smartResButton:GetAttribute("registeredClickTrigger")
		or db.keybindTrigger

	if resetDatabase then
		self.db:ResetDB(DEFAULT)
		global = self.db.global
		---@cast global -nil

		global.settingsVersion = SMARTRES2_DB_VERSION
		self.LibDBIcon:Refresh("SmartRes2", global.minimap)
		self:RefreshBrokerIcon()
	end

	db = self.db.profile
	---@cast db -nil

	if db.enabled then
		RefreshModules()
		RefreshModuleConfigs()
	else
		DisableModules()
	end

	AceConfigRegistry:NotifyChange("SmartRes2")

	if (callback == "OnProfileReset" or resetDatabase)
		and registeredClickTrigger ~= db.keybindTrigger
	then
		StaticPopup_Show(KEYBIND_TRIGGER_RELOAD_POPUP)
	end
end

function addon:ChatCommand()
	AceConfigDialog:Open("SmartRes2")
end

-- --------------------------------------------------------------------
-- Event handlers
-- --------------------------------------------------------------------

function addon:SPELLS_CHANGED()
	RefreshSecureButtonSpells()
end

function addon:NEUTRAL_FACTION_SELECT_RESULT(event, success)
	if not success then
		return
	end

	local factionGroup = UnitFactionGroup("player")

	if factionGroup == "Alliance" or factionGroup == "Horde" then
		self.PLAYER_GUID = UnitGUID("player")
		self:UnregisterEvent(event)
	end
end

-- --------------------------------------------------------------------
-- Keybinding labels
-- --------------------------------------------------------------------

BINDING_HEADER_SMARTRES2 = "SmartRes2"
BINDING_NAME_SMARTRES2_SINGLE_RES = L["Single Target Res Key"]
BINDING_NAME_SMARTRES2_MANUAL_RES = L["Manual Target Res"]
BINDING_NAME_SMARTRES2_COMBAT_RES = L["Combat Res Key"]
BINDING_NAME_SMARTRES2_MASS_RES = L["Mass Res Key"]
_G["BINDING_NAME_CLICK SmartRes2SmartResButton:LeftButton"] = L["Single Target Res Key"]
_G["BINDING_NAME_CLICK SmartRes2ManualResButton:LeftButton"] = L["Manual Target Res"]
_G["BINDING_NAME_CLICK SmartRes2CombatResButton:LeftButton"] = L["Combat Res Key"]
_G["BINDING_NAME_CLICK SmartRes2MassResButton:LeftButton"] = L["Mass Res Key"]

-- --------------------------------------------------------------------
-- Module options registration
-- --------------------------------------------------------------------

function addon:RegisterModuleOptions(moduleName, moduleOptions)
	if type(moduleName) ~= "string" then
		error(("bad argument #1, expected string 'moduleName', got %s"):format(type(moduleName)), 2)
	end

	if type(moduleOptions) ~= "table" then
		error(("bad argument #2, expected table 'moduleOptions', got %s"):format(type(moduleOptions)), 2)
	end

	options = options or self:GetOptions()
	options.args[moduleName] = moduleOptions

	if moduleOptions.disabled == nil then
		options.args[moduleName].disabled = function()
			return not self.db.profile.enabled
		end
	end

	AceConfigRegistry:NotifyChange("SmartRes2")
end