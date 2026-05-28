-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2
--
-- Core responsibilities:
-- - Create the addon object.
-- - Initialize saved variables and profile callbacks.
-- - Register options, profiles, About panel, slash commands, and Broker.
-- - Manage module lifecycle once modules exist.
-- - Provide shared addon services used by later files.
--
-- Core does not:
-- - Track resurrection casts directly.
-- - Expose resurrection/cast-state APIs.
-- - Bind keys dynamically.
-- - Scan the full spellbook.
--
-- LibResInfo-2.0 owns resurrection state. SmartRes2 embeds it so Core
-- and later files/modules can consume its APIs/callbacks.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

local C_Spell = C_Spell
local LibStub = LibStub
local pairs = pairs
local type = type
local UnitClassBase = UnitClassBase
local wipe = wipe

-- --------------------------------------------------------------------
-- Libraries
-- --------------------------------------------------------------------

local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceDB = LibStub("AceDB-3.0")

---@class SmartRes2: AceAddon, AceConsole-3.0, AceEvent-3.0, LibAboutPanel-2.0, LibResInfo-2.0
---@field db SmartRes2DB
---@field GetMassResurrectionIcon fun(self: SmartRes2): number|string|nil
---@field GetOptions fun(self: SmartRes2): table
---@field TogglePreviewBars fun(self: SmartRes2)
---@field GetResurrectionIconForClass fun(self: SmartRes2, classFilename: string|nil, useDefault?: boolean): number|string|nil
local addon = LibStub("AceAddon-3.0"):NewAddon(
	"SmartRes2",
	"AceEvent-3.0",
	"AceConsole-3.0",
	"LibAboutPanel-2.0",
	"LibResInfo-2.0"
)

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

---@class SmartRes2_Bars: AceAddon
---@field db SmartRes2_BarsDB
---@field ClearTestBars fun(self: SmartRes2_Bars)
---@field HasTestBars fun(self: SmartRes2_Bars): boolean
---@field ShowTestBars fun(self: SmartRes2_Bars)

-- All modules should have AceEvent, AceConsole, and LibResInfo mixed in by
-- default. LibAboutPanel intentionally remains Core-only because modules do
-- not create About panels.
addon:SetDefaultModuleLibraries(
	"AceEvent-3.0",
	"AceConsole-3.0",
	"LibResInfo-2.0"
)

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

local DEFAULT_ICON_SPELL_ID = 2006 -- Priest: Resurrection
local MASS_RESURRECTION_ICON_SPELL_ID = 83968 -- Mass Resurrection
local MASS_RESURRECTION_ICON = [[Interface\Icons\Spell_Holy_PrayerOfHealing02]]

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
			showInCompartment = true,
			lockOnDegree = true,
			minimapPos = 60,
		},
	},
	profile = {
		enabled = true,
	},
}

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

---@type table|nil
local db

---@type table|nil
local global

---@type table|nil
local options

-- --------------------------------------------------------------------
-- Local helpers
-- --------------------------------------------------------------------

---@param spellID number
---@return number|string|nil icon
local function GetSpellIcon(spellID)
	return C_Spell.GetSpellTexture(spellID)
end

---@param classFilename string|nil
---@param useDefault boolean|nil
---@return number|string|nil icon
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

---@return number|string|nil icon
function addon:GetMassResurrectionIcon()
	return GetSpellIcon(MASS_RESURRECTION_ICON_SPELL_ID) or MASS_RESURRECTION_ICON
end

---@param source table
---@param target table
local function CopyDefaults(source, target)
	for key, value in pairs(source) do
		if type(value) == "table" then
			target[key] = target[key] or {}
			CopyDefaults(value, target[key])
		else
			target[key] = value
		end
	end
end

-- Global settings are not profile-scoped AceDB data. When the user opts into
-- resetting globals alongside profile changes, preserve that opt-in so the
-- setting does not disable itself after the first reset.
local function ResetGlobalDB()
	if not global then return end

	local resetGlobalOnProfileChange = global.resetGlobalOnProfileChange

	wipe(global)
	CopyDefaults(defaults.global, global)

	global.resetGlobalOnProfileChange = resetGlobalOnProfileChange
end

-- AceDB namespaces are created by modules when those modules are written.
-- Until then, modules without namespaces are treated as enabled. Once Chat
-- and Bars exist, their own namespace defaults should include profile.enabled.
---@param moduleName string
---@return boolean enabled
local function IsModuleProfileEnabled(moduleName)
	local moduleDB = addon.db:GetNamespace(moduleName, true)

	if moduleDB and moduleDB.profile and moduleDB.profile.enabled ~= nil then
		return moduleDB.profile.enabled
	end

	return true
end

-- --------------------------------------------------------------------
-- Addon lifecycle
-- --------------------------------------------------------------------

function addon:OnInitialize()
	self.db = AceDB:New("SmartRes2DB", defaults, true) --[[@as SmartRes2DB]]

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	db = self.db.profile
	global = self.db.global

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

function addon:OnEnable()
	self:RefreshModules()
end

function addon:OnDisable()
	self:DisableModules()
end

function addon:RefreshConfig()
	db = self.db.profile
	global = self.db.global

	if global and global.resetGlobalOnProfileChange then
		ResetGlobalDB()
	end

	if db.enabled then
		self:RefreshModules()
		self:RefreshModuleConfigs()
	else
		self:DisableModules()
	end

	if global then
		LibDBIcon:Refresh("SmartRes2", global.minimap)
	end

	self:RefreshBrokerIcon()

	AceConfigRegistry:NotifyChange("SmartRes2")
end

-- --------------------------------------------------------------------
-- Modules
-- --------------------------------------------------------------------

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
		local moduleObject = module --[[@as table]]
		local refreshConfig = moduleObject["RefreshConfig"]

		if type(refreshConfig) == "function" then
			refreshConfig(moduleObject)
		end
	end
end

-- Modules call this to add their AceConfig option tables to SmartRes2's main
-- options table. The module name is used as the options key, but the module
-- itself still owns its own defaults and DB namespace.
---@param optionsName string
---@param moduleOptions table
function addon:RegisterModuleOptions(optionsName, moduleOptions)
	if type(optionsName) ~= "string" then
		error(("bad argument #1, expected string optionsName, got %s"):format(type(optionsName)), 2)
	end

	if type(moduleOptions) ~= "table" then
		error(("bad argument #2, expected table moduleOptions, got %s"):format(type(moduleOptions)), 2)
	end

	options = options or self:GetOptions()
	options.args[optionsName] = moduleOptions

	if moduleOptions.disabled == nil then
		options.args[optionsName].disabled = function()
			return not self.db.profile.enabled
		end
	end

	AceConfigRegistry:NotifyChange("SmartRes2")
end

-- --------------------------------------------------------------------
-- Slash commands
-- --------------------------------------------------------------------

function addon:ChatCommand()
	AceConfigDialog:Open("SmartRes2")
end

function addon:TogglePreviewBars()
	if not db or not db.enabled or not self:IsEnabled() then
		return
	end

	local barsModule = self:GetModule("Bars", true) --[[@as SmartRes2_Bars|nil]]

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

function addon:InitializeBroker()
	---@type LibDataBroker.QuickLauncher
	local brokerObjectData = {
		type = "launcher" --[[@as "launcher"]],
		tocname = "SmartRes2",
		label = "SmartRes2",
		icon = (self:GetBrokerIcon() or "") --[[@as string]],
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

	LibDBIcon:Register("SmartRes2", brokerObject, self.db.global.minimap)
end

---@return number|string|nil icon
function addon:GetBrokerIcon()
	if global and global.useClassIconForBroker then
		return self:GetResurrectionIconForClass(UnitClassBase("player"))
	end

	return self:GetResurrectionIconForClass(nil)
end

function addon:RefreshBrokerIcon()
	local button = LibDBIcon:GetMinimapButton("SmartRes2")
	if button and button.icon then
		button.icon:SetTexture(self:GetBrokerIcon())
	end
end

-- --------------------------------------------------------------------
-- Future keybinding entry points
-- --------------------------------------------------------------------

function addon:CastSmartResurrection()
	-- Implemented later in the keybinding/spell-selection pass.
end

function addon:PrepareCombatResurrection()
	-- Implemented later. This must preload the combat resurrection spell
	-- onto the cursor and must not auto-select a target.
end

function addon:CastMassResurrection()
	-- Implemented later in the keybinding/spell-selection pass.
end