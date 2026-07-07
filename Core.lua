-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2
--
-- Core responsibilities:
-- - Create the addon object.
-- - Initialize saved variables and profile callbacks.
-- - Register options, profiles, About panel, slash commands, and Broker.
-- - Manage module lifecycle.
-- - Provide shared addon services used by modules.
-- - Register SmartRes2-owned media and bundled Masque skins.
-- - Provide future keybinding entry points.
--
-- Runtime boundary:
-- - LibResInfo-2.0 owns resurrection detection and cast state.
-- - Bars consumes LibResInfo callbacks and displays resurrection state.
-- - Chat will consume LibResInfo callbacks later for announcements.
-- - Smart keybinding logic will live in Core/additional files later, but
--   combat resurrection targeting must remain manually chosen by the player.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local _G = _G
local CreateFrame = CreateFrame
local GetNumGroupMembers = GetNumGroupMembers
local GetSpellInfo = C_Spell.GetSpellInfo
local GetSpellTexture = C_Spell.GetSpellTexture
local GetTime = GetTime
local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsSpellInRange = C_Spell.IsSpellInRange
local IsSpellKnown = C_SpellBook.IsSpellKnown
local IsSpellUsable = C_Spell.IsSpellUsable
local LibStub = LibStub
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR
local OKAY = OKAY
local pairs = pairs
local POWER_TYPE = Enum.PowerType
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Show = StaticPopup_Show
local type = type
local UIParent = UIParent
local UnitAffectingCombat = UnitAffectingCombat
local UnitClassBase = UnitClassBase
local UnitExists = UnitExists
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsConnected = UnitIsConnected
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitIsPlayer = UnitIsPlayer
local UnitIsUnit = UnitIsUnit
local UnitIsVisible = UnitIsVisible
local UnitPowerMax = UnitPowerMax

---@class SmartRes2LibDBIcon: LibDBIcon-1.0
---@field IsButtonCompartmentAvailable fun(self: SmartRes2LibDBIcon): boolean|nil

---@class SmartRes2: AceAddon, AceEvent-3.0, AceConsole-3.0, LibAboutPanel-2.0, LibResInfo-2.0
---@field GetOptions function
---@field db table
---@field LibDBIcon SmartRes2LibDBIcon
local addon = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceEvent-3.0", "AceConsole-3.0", "LibAboutPanel-2.0", "LibResInfo-2.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- --------------------------------------------------------------------
-- Libraries
-- --------------------------------------------------------------------

local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
---@type SmartRes2LibDBIcon
addon.LibDBIcon = LibStub("LibDBIcon-1.0")
addon.LSM = LibStub("LibSharedMedia-3.0")
addon.Masque, addon.MasqueAPIVersion = LibStub("Masque", true)

-- All modules should have AceEvent, AceConsole, and LibResInfo mixed in by
-- default. LibAboutPanel intentionally remains Core-only because modules do
-- not create About panels.
addon:SetDefaultModuleLibraries("AceEvent-3.0", "AceConsole-3.0", "LibResInfo-2.0")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

local DB_RESET_POPUP = "SMARTRES2_DB_RESET"
local DEFAULT_ICON_SPELL_ID = 2006 -- Priest: Resurrection
local HUNTER_REVIVE_PET_SPELL_ID = 982 -- Revive Pet
local MANA_POWER_TYPE = POWER_TYPE.Mana or 0
local MASS_RESURRECTION_RETAIL_SPELL_ID = 212036 -- Mass Resurrection
local MASS_RESURRECTION_MISTS_SPELL_ID = 83968 -- Mass Resurrection
local MASS_RESURRECTION_RETAIL_SPELL_INFO = GetSpellInfo(MASS_RESURRECTION_RETAIL_SPELL_ID) -- Mass Resurrection
local MASS_RESURRECTION_MISTS_SPELL_INFO = GetSpellInfo(MASS_RESURRECTION_MISTS_SPELL_ID) -- Mass Resurrection
local MASS_RESURRECTION_FALLBACK_SPELL_INFO = GetSpellInfo(DEFAULT_ICON_SPELL_ID) -- Resurrection

local MASS_RESURRECTION_SPELL_INFO = MASS_RESURRECTION_RETAIL_SPELL_INFO
	or MASS_RESURRECTION_MISTS_SPELL_INFO
	or MASS_RESURRECTION_FALLBACK_SPELL_INFO

local MASS_RESURRECTION_ICON = MASS_RESURRECTION_SPELL_INFO and MASS_RESURRECTION_SPELL_INFO.iconID
local MASS_RESURRECTION_ICON_SPELL_ID = MASS_RESURRECTION_SPELL_INFO and MASS_RESURRECTION_SPELL_INFO.spellID
local PLAYER_CLASS_FILENAME = UnitClassBase("player")
local SMARTRES2_DB_VERSION = 1

BINDING_HEADER_SMARTRES2 = "SmartRes2"
BINDING_NAME_SMARTRES2_SINGLE_RES = L["Single Target Res Key"]
BINDING_NAME_SMARTRES2_MANUAL_RES = L["Manual Target Res"]
BINDING_NAME_SMARTRES2_COMBAT_RES = L["Combat Res Key"]
BINDING_NAME_SMARTRES2_MASS_RES = L["Mass Res Key"]
_G["BINDING_NAME_CLICK SmartRes2SmartResButton:LeftButton"] = L["Single Target Res Key"]
_G["BINDING_NAME_CLICK SmartRes2ManualResButton:LeftButton"] = L["Manual Target Res"]
_G["BINDING_NAME_CLICK SmartRes2CombatResButton:LeftButton"] = L["Combat Res Key"]
_G["BINDING_NAME_CLICK SmartRes2MassResButton:LeftButton"] = L["Mass Res Key"]

StaticPopupDialogs[DB_RESET_POPUP] = {
	text = L["SmartRes2 settings were reset because this version uses a new settings layout."],
	button1 = OKAY,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

-- Broker/minimap icon spellIDs are intentionally non-combat resurrection
-- spell icons. Combat resurrection priority is situational and should not
-- influence the default launcher identity.
local classResIconSpellIDs = {
	DRUID	= 50769,	-- Revive
	EVOKER	= 361227,	-- Return
	HUNTER	= 982,		-- Revive Pet
	MONK	= 115178,	-- Resuscitate
	PALADIN	= 7328,		-- Redemption
	PRIEST	= 2006,		-- Resurrection
	SHAMAN	= 2008,		-- Ancestral Spirit
}

-- --------------------------------------------------------------------
-- Saved variable defaults
-- --------------------------------------------------------------------

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
		useMasque = true,
		waitingDelay = 7.5,
	},
}

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

local db

local global

local options

-- Forward declarations for local helpers that are defined later but called
-- during OnInitialize(). Lua resolves locals lexically, so these names must
-- exist before addon:OnInitialize() is compiled.
local RegisterMedia
local RegisterMasqueSkins
local CreateSecureButtons
local RefreshSecureButtonSpells

-- --------------------------------------------------------------------
-- Addon lifecycle
-- --------------------------------------------------------------------

-- Create SmartRes2's root AceDB database, perform one-time saved-variable
-- migration/reset work, register shared media/skins, and build the root options
-- table. Core owns global options; modules register their own option groups.
function addon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)

	local oldVersion = self.db.global.settingsVersion
	if (not oldVersion) or (oldVersion < SMARTRES2_DB_VERSION) then
		StaticPopup_Show(DB_RESET_POPUP)
		self.db:ResetDB(DEFAULT)
	end

	db = self.db.profile
	global = self.db.global

	global.settingsVersion = SMARTRES2_DB_VERSION

	RegisterMedia()
	RegisterMasqueSkins()
	CreateSecureButtons()
	RefreshSecureButtonSpells()

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	self:SetEnabledState(db.enabled)

	options = self:GetOptions()
	options.args = options.args or {}

	options.args.profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profiles.order = 900

	-- LibDualSpec augments the AceDB profile UI. Do not force-enable or
	-- force-disable dual spec here; users expect manual control over their
	-- profile behavior.
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

	self:InitializeBroker()
end

-- Keep module state in sync with the root addon enable state.
function addon:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "RefreshSecureButtons")
	self:RegisterEvent("SPELLS_CHANGED", "RefreshSecureButtons")
	self:RefreshSecureButtons()
	self:RefreshModules()
end

function addon:OnDisable()
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:UnregisterEvent("SPELLS_CHANGED")
	self:DisableModules()
end

-- Profile changes can reset global settings, enable/disable modules, refresh
-- module option state, update the minimap button, and repaint the broker icon.
function addon:RefreshConfig()
	db = self.db.profile

	if global and global.resetGlobalOnProfileChange then
		self.db:ResetDB(DEFAULT)

		db = self.db.profile
		global = self.db.global
		global.settingsVersion = SMARTRES2_DB_VERSION
	end

	if db.enabled then
		self:RefreshModules()
		self:RefreshModuleConfigs()
	else
		self:DisableModules()
	end

	if global then
		addon.LibDBIcon:Refresh("SmartRes2", global.minimap)
	end

	self:RefreshBrokerIcon()

	AceConfigRegistry:NotifyChange("SmartRes2")
end

-- --------------------------------------------------------------------
-- Shared media and bundled skins
-- --------------------------------------------------------------------

function RegisterMedia()
	-- Register only SmartRes2-owned media here. LibSharedMedia already registers
	-- Blizzard defaults such as "Blizzard", "Solid", "Blizzard Tooltip", and
	-- locale-aware default fonts.
	--
	-- Example for later:
	-- addon.LSM:Register(
	--     addon.LSM.MediaType.FONT,
	--     "SmartRes2 Olde English",
	--     [[Interface\AddOns\SmartRes2\Media\Fonts\OldeEnglish.ttf]]
	-- )
end

function RegisterMasqueSkins()
	if not addon.Masque then
		return
	end

	addon.Masque:AddSkin("SmartRes2: Neuron", {
		API_VERSION = addon.MasqueAPIVersion,
		Shape = "Square",

		-- Info
		Description = "The Neuron Masque skin bundled with SmartRes2.",
		Author = "Soyier; bundled with SmartRes2",
		Websites = {
			"https://www.curseforge.com/wow/addons/masque-neuron",
			"https://github.com/brittyazel/Masque_Neuron",
		},

		-- Skin
		Backdrop = {
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Backdrop]],
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
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Normal]],
			Width = 42,
			Height = 42,
			Color = {0.2, 0.2, 0.2, 1},
		},

		Pushed = {
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Overlay]],
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
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Border]],
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
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Border]],
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
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Gloss]],
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
			Texture = [[Interface\AddOns\SmartRes2\Media\Masque\Neuron\Highlight]],
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
	})
end

-- --------------------------------------------------------------------
-- Secure casting buttons
-- --------------------------------------------------------------------

local function ClearSecureSpellButton(button)
	button:SetAttribute("spell", nil)
	button:SetAttribute("unit", nil)
end

local function SetSecureSpellButton(button, spellID, unit)
	button:SetAttribute("spell", spellID)
	button:SetAttribute("unit", unit)
end

local function CreateSecureSpellButton(name, preClickMethod)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")

	-- These buttons exist only as secure keybinding targets. Keep the frames
	-- available for CLICK bindings, but make them visually absent and unable to
	-- receive normal mouse input.
	button:SetSize(1, 1)
	button:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	button:SetAlpha(0)
	button:EnableMouse(false)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("type", "spell")

	if preClickMethod then
		button:SetScript("PreClick", function(button)
			addon[preClickMethod](addon, button)
		end)
	end

	return button
end

function CreateSecureButtons()
	if not addon.smartResButton then
		if PLAYER_CLASS_FILENAME == "HUNTER" then
			addon.smartResButton = CreateSecureSpellButton("SmartRes2SmartResButton")
		else
			addon.smartResButton = CreateSecureSpellButton("SmartRes2SmartResButton", "PrepareSmartResurrectionButton")
		end
	end

	if not addon.manualResButton then
		addon.manualResButton = CreateSecureSpellButton("SmartRes2ManualResButton")
	end

	if not addon.combatResButton then
		addon.combatResButton = CreateSecureSpellButton("SmartRes2CombatResButton")
	end

	if not addon.massResButton then
		addon.massResButton = CreateSecureSpellButton("SmartRes2MassResButton")
	end
end

function addon:RefreshSecureButtons()
	RefreshSecureButtonSpells()
end

-- --------------------------------------------------------------------
-- Icon helpers
-- --------------------------------------------------------------------

local function GetSpellIcon(spellID)
	return GetSpellTexture(spellID)
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

-- --------------------------------------------------------------------
-- Module management
-- --------------------------------------------------------------------

-- AceDB namespaces are created by modules when those modules are written.
-- Until then, modules without namespaces are treated as enabled. Once Chat
-- and Bars exist, their own namespace defaults should include profile.enabled.
local function IsModuleProfileEnabled(moduleName)
	local moduleDB = addon.db:GetNamespace(moduleName, true)

	if moduleDB and moduleDB.profile and moduleDB.profile.enabled ~= nil then
		return moduleDB.profile.enabled
	end

	return true
end

-- Enable or disable loaded modules from their AceDB namespace state.
-- This is safe before modules exist: IterateModules() simply has nothing
-- useful to process.
function addon:RefreshModules()
	if not self:IsEnabled() then return end

	for moduleName, module in self:IterateModules() do
		local moduleEnabled = IsModuleProfileEnabled(moduleName)

		if moduleEnabled and not module:IsEnabled() then
			self:EnableModule(moduleName)
		elseif not moduleEnabled and module:IsEnabled() then
			self:DisableModule(moduleName)
		end
	end
end

-- Disable every loaded module when SmartRes2 itself is disabled. This keeps
-- module event handlers and callbacks from running while the parent addon is
-- disabled.
function addon:DisableModules()
	for moduleName, module in self:IterateModules() do
		if module:IsEnabled() then
			self:DisableModule(moduleName)
		end
	end
end

-- Give modules a chance to re-read their profile/global settings after
-- profile changes, copies, or resets. Modules can ignore this by not defining
-- :RefreshConfig().
function addon:RefreshModuleConfigs()
	for _, module in self:IterateModules() do
		local moduleObject = module
		local refreshConfig = moduleObject["RefreshConfig"]

		if type(refreshConfig) == "function" then
			refreshConfig(moduleObject)
		end
	end
end

-- Modules call this to add their AceConfig option tables to SmartRes2's main
-- options table. The module name is used as the options key, but the module
-- itself still owns its own defaults and DB namespace.
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

-- --------------------------------------------------------------------
-- Slash commands and preview bars
-- --------------------------------------------------------------------

function addon:ChatCommand()
	AceConfigDialog:Open("SmartRes2")
end

function addon:TogglePreviewBars()
	if not db or not db.enabled or not self:IsEnabled() then
		return
	end

	local barsModule = self:GetModule("Bars", true)

	if not barsModule or not barsModule.db or not barsModule.db.profile.enabled or not barsModule:IsEnabled() then
		return
	end

	if barsModule:HasTestBars() then
		barsModule:ClearTestBars()
	else
		barsModule:ShowTestBars()
	end
end

-- --------------------------------------------------------------------
-- Broker / minimap
-- --------------------------------------------------------------------

function addon:GetBrokerIcon()
	if global and global.useClassIconForBroker then
		return self:GetResurrectionIconForClass(PLAYER_CLASS_FILENAME)
	end

	return self:GetResurrectionIconForClass(nil)
end

function addon:RefreshBrokerIcon()
	local button = addon.LibDBIcon:GetMinimapButton("SmartRes2")
	if button and button.icon then
		button.icon:SetTexture(self:GetBrokerIcon())
	end
end

function addon:InitializeBroker()
	local brokerObjectData = {
		type = "launcher",
		tocname = "SmartRes2",
		label = "SmartRes2",
		icon = (self:GetBrokerIcon() or ""),
		OnClick = function(_, button)
			if button == "RightButton" then
				AceConfigDialog:Open("SmartRes2")
			elseif button == "MiddleButton" then
				self:TogglePreviewBars()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("SmartRes2", HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			tooltip:AddLine(L["Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:AddLine(L["Middle click to show or clear test bars."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:Show()
		end,
	}

	local brokerObject = LibDataBroker:NewDataObject("SmartRes2", brokerObjectData)

	addon.LibDBIcon:Register("SmartRes2", brokerObject, self.db.global.minimap)
end

-- --------------------------------------------------------------------
-- Inform the player of useful or important information
-- --------------------------------------------------------------------

function addon:NotifySelf(message)
	if db and db.notifySelf then
		self:Print(message)
	end
end

-- --------------------------------------------------------------------
-- Smart resurrection spell selection
-- --------------------------------------------------------------------

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

	if not UnitIsConnected(unit) then
		return false
	end

	if not UnitIsVisible(unit) then
		return false
	end

	if not IsSpellInRange(spellID, unit) then
		return false
	end

	local isBeingResurrected = addon:IsUnitBeingResurrected(unit)
	if isBeingResurrected then
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
	local bestIndex
	local numGroupMembers = GetNumGroupMembers()

	if IsInRaid() then
		for index = 1, numGroupMembers do
			local unit = "raid" .. index

			if IsEligibleSmartResTarget(unit, spellID) then
				local priority = GetSmartResPriority(unit)

				if not bestPriority or priority < bestPriority or (priority == bestPriority and index < bestIndex) then
					bestUnit = unit
					bestPriority = priority
					bestIndex = index
				end
			end
		end
	else
		for index = 1, numGroupMembers - 1 do
			local unit = "party" .. index

			if IsEligibleSmartResTarget(unit, spellID) then
				local priority = GetSmartResPriority(unit)

				if not bestPriority or priority < bestPriority or (priority == bestPriority and index < bestIndex) then
					bestUnit = unit
					bestPriority = priority
					bestIndex = index
				end
			end
		end
	end

	return bestUnit
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

function RefreshSecureButtonSpells()
	if addon.smartResButton then
		if PLAYER_CLASS_FILENAME == "HUNTER" then
			SetSecureSpellButton(addon.smartResButton, GetPlayerNormalSingleResSpellID())
		else
			ClearSecureSpellButton(addon.smartResButton)
		end
	end

	if addon.manualResButton then
		if PLAYER_CLASS_FILENAME == "HUNTER" then
			ClearSecureSpellButton(addon.manualResButton)
		else
			SetSecureSpellButton(addon.manualResButton, GetPlayerNormalSingleResSpellID())
		end
	end

	if addon.combatResButton then
		SetSecureSpellButton(addon.combatResButton, GetPlayerCombatResurrectionSpellID())
	end

	if addon.massResButton then
		SetSecureSpellButton(addon.massResButton, GetPlayerMassResurrectionSpellID())
	end
end

-- --------------------------------------------------------------------
-- Keybinding entry points
-- --------------------------------------------------------------------

function addon:PreLoadCombatResurrection()
	RefreshSecureButtonSpells()
end

function addon:CastSmartResurrection(button)
	if PLAYER_CLASS_FILENAME == "HUNTER" then
		self:CastRevivePet(button)
		return
	end

	ClearSecureSpellButton(button)

	if InCombatLockdown() or UnitAffectingCombat("player") then
		return
	end

	if not IsInGroup() then
		self:NotifySelf(L["You are not in a group and cannot use this feature."])
		return
	end

	if self:IsMassResBeingCast() then
		self:NotifySelf(L["A mass resurrection is in progress. Exiting as there is nothing to do."])
		return
	end

	local spellID = GetPlayerNormalSingleResSpellID()
	if not spellID then
		self:NotifySelf(L["You do not know a resurrection spell."])
		return
	end

	if not IsUsableSpell(spellID) then
		return
	end

	local targetUnit = FindBestSmartResTarget(spellID)
	if not targetUnit then
		self:NotifySelf(L["No valid resurrection target found."])
		return
	end

	SetSecureSpellButton(button, spellID, targetUnit)
end

function addon:CastRevivePet(button)
	ClearSecureSpellButton(button)

	if not IsKnownSpell(HUNTER_REVIVE_PET_SPELL_ID) then
		self:NotifySelf(L["You do not know Revive Pet."])
		return
	end

	if UnitExists("pet") then
		self:NotifySelf(L["Your pet is already alive."])
		return
	end

	if not IsUsableSpell(HUNTER_REVIVE_PET_SPELL_ID) then
		return
	end

	SetSecureSpellButton(button, HUNTER_REVIVE_PET_SPELL_ID)
end

function addon:LoadManualResurrectionForTargeting(button)
	if PLAYER_CLASS_FILENAME == "HUNTER" then
		return
	end

	ClearSecureSpellButton(button)

	local spellID = GetPlayerNormalSingleResSpellID()

	if not spellID then
		self:NotifySelf(L["You do not know a resurrection spell."])
		return
	end

	if not IsUsableSpell(spellID) then
		return
	end

	SetSecureSpellButton(button, spellID)
end

function addon:CastCombatResurrection(button)
	ClearSecureSpellButton(button)

	local spellID = GetPlayerCombatResurrectionSpellID()
	if not spellID then
		self:NotifySelf(L["You do not know a resurrection spell."])
		return
	end

	if not IsUsableSpell(spellID) then
		return
	end

	SetSecureSpellButton(button, spellID)
end

function addon:CastMassResurrection(button)
	if InCombatLockdown() or UnitAffectingCombat("player") then
		return
	end

	ClearSecureSpellButton(button)

	if not IsInGroup() then
		self:NotifySelf(L["You are not in a group and cannot use this feature."])
		return
	end

	if self:IsMassResBeingCast() then
		self:NotifySelf(L["A mass resurrection is in progress. Exiting as there is nothing to do."])
		return
	end

	local spellID = GetPlayerMassResurrectionSpellID()
	if not spellID then
		self:NotifySelf(L["You do not know a mass resurrection spell."])
		return
	end

	if not IsUsableSpell(spellID) then
		return
	end

	SetSecureSpellButton(button, spellID)
end