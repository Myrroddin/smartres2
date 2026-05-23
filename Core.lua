---@diagnostic disable: undefined-field
---@class SmartRes2: AceAddon, AceConsole-3.0, AceEvent-3.0, LibAboutPanel20, LibResInfo20
-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2
--
-- Core responsibilities:
-- - Create the addon object.
-- - Initialize saved variables and profile callbacks.
-- - Register options, profiles, About panel, slash commands, and Broker.
-- - Manage module enable states.
-- - Expose the public data-only theme API.
--
-- Core does not:
-- - Track resurrection casts directly.
-- - Expose resurrection/cast-state APIs.
-- - Bind keys dynamically.
-- - Scan the full spellbook.
--
-- LibResInfo-2.0 owns resurrection state. SmartRes2 embeds it so Core
-- and modules can consume its APIs/callbacks.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local _G = _G
local error = error
local format = string.format
local pairs = pairs
local type = type

local LibStub = LibStub

local HIGHLIGHT_FONT_COLOR = HIGHLIGHT_FONT_COLOR
local NORMAL_FONT_COLOR = NORMAL_FONT_COLOR

-- --------------------------------------------------------------------
-- Libraries
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):NewAddon(
	"SmartRes2",
	"AceEvent-3.0",
	"AceConsole-3.0",
	"LibAboutPanel-2.0",
	"LibResInfo-2.0"
)

_G.SmartRes2 = addon

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

addon:SetDefaultModuleLibraries(
	"AceEvent-3.0",
	"AceConsole-3.0",
	"LibResInfo-2.0"
)

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceDB = LibStub("AceDB-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibDBIcon = LibStub("LibDBIcon-1.0")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

local ADDON_NAME = "SmartRes2"
local DEFAULT_THEME_KEY = "default"
local DEFAULT_ICON = "Interface\\Icons\\Spell_holy_resurrection"

-- --------------------------------------------------------------------
-- Saved variable defaults
-- --------------------------------------------------------------------

local defaults = {
	global = {
		minimap = {
			hide = false,
			lock = true,
			showInCompartment = true,
			useClassIconForBroker = true,
			lockOnDegree = true,
			minimapPos = 60,
		},
	},
	profile = {
		enabled = true,
		activeTheme = DEFAULT_THEME_KEY,
		modules = {
			Chat = {
				enabled = true,
			},
			Bars = {
				enabled = true,
			},
		},
	},
}

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

---@type AceDBObject|nil
local db

---@type table|nil
local options

---@type table<string, table>
local registeredThemes = {}

---@type string[]
local registeredThemeKeys = {}

-- --------------------------------------------------------------------
-- Local helpers
-- --------------------------------------------------------------------

local function ThemeKeyExists(themeKey)
	return registeredThemes[themeKey] ~= nil
end

local function AddThemeKey(themeKey)
	for _, registeredThemeKey in pairs(registeredThemeKeys) do
		if registeredThemeKey == themeKey then
			return
		end
	end

	registeredThemeKeys[#registeredThemeKeys + 1] = themeKey
end

local function RemoveThemeKey(themeKey)
	for index, registeredThemeKey in pairs(registeredThemeKeys) do
		if registeredThemeKey == themeKey then
			registeredThemeKeys[index] = nil
			return
		end
	end
end

local function ValidateThemeKey(themeKey, argumentIndex)
	if type(themeKey) ~= "string" or themeKey == "" then
		error(format("bad argument #%d, expected non-empty string themeKey", argumentIndex), 3)
	end
end

local function ValidateThemeTable(themeTable, argumentIndex)
	if type(themeTable) ~= "table" then
		error(format("bad argument #%d, expected table themeTable", argumentIndex), 3)
	end

	if themeTable.name == nil then
		error(format("bad argument #%d, themeTable.name is required", argumentIndex), 3)
	end
end

local function GetModuleProfileEnabled(moduleName)
	local profile = db and db.profile
	local moduleSettings = profile and profile.modules and profile.modules[moduleName]

	if moduleSettings and moduleSettings.enabled ~= nil then
		return moduleSettings.enabled
	end

	return true
end

-- --------------------------------------------------------------------
-- Addon lifecycle
-- --------------------------------------------------------------------

function addon:OnInitialize()
	self.db = AceDB:New("SmartRes2DB", defaults, true)
	db = self.db

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	self:SetEnabledState(self.db.profile.enabled)

	options = self:GetOptions()
	options.args.profiles = AceDBOptions:GetOptionsTable(self.db)
	options.args.profiles.order = 900

	options.args.aboutPanel = self:AboutOptionsTable(ADDON_NAME)
	options.args.aboutPanel.order = 1000

	AceConfig:RegisterOptionsTable(ADDON_NAME, options)
	AceConfigDialog:AddToBlizOptions(ADDON_NAME)

	self:RegisterChatCommand("smartres2", "ChatCommand")
	self:RegisterChatCommand("smartres", "ChatCommand")
	self:RegisterChatCommand("sr", "ChatCommand")

	self:InitializeBroker()
end

function addon:OnEnable()
	self:RefreshModules()
end

function addon:OnDisable()
	self:DisableAllModules()
end

function addon:RefreshConfig()
	db = self.db

	self:SetEnabledState(self.db.profile.enabled)

	if self.db.profile.enabled and not self:IsEnabled() then
		self:Enable()
	elseif not self.db.profile.enabled and self:IsEnabled() then
		self:Disable()
	end

	self:RefreshModules()
	self:RefreshBroker()

	for _, module in self:IterateModules() do
		if type(module.RefreshConfig) == "function" then
			module:RefreshConfig()
		end
	end

	AceConfigRegistry:NotifyChange(ADDON_NAME)
end

-- --------------------------------------------------------------------
-- Modules
-- --------------------------------------------------------------------

function addon:RefreshModules()
	if not self:IsEnabled() then return end

	for moduleName, module in self:IterateModules() do
		local moduleEnabled = GetModuleProfileEnabled(moduleName)

		if moduleEnabled and not module:IsEnabled() then
			self:EnableModule(moduleName)
		elseif not moduleEnabled and module:IsEnabled() then
			self:DisableModule(moduleName)
		end
	end
end

function addon:RegisterModuleOptions(moduleName, moduleOptions)
	if type(moduleName) ~= "string" then
		error(format("bad argument #1, expected string moduleName, got %s", type(moduleName)), 2)
	end

	if type(moduleOptions) ~= "table" then
		error(format("bad argument #2, expected table moduleOptions, got %s", type(moduleOptions)), 2)
	end

	options = options or self:GetOptions()
	options.args[moduleName] = moduleOptions
	options.args[moduleName].disabled = moduleOptions.disabled or function()
		return not self.db.profile.enabled
	end

	AceConfigRegistry:NotifyChange(ADDON_NAME)
end

-- --------------------------------------------------------------------
-- Slash commands / options
-- --------------------------------------------------------------------

function addon:ChatCommand()
	self:ToggleOptions()
end

function addon:OpenOptions()
	AceConfigDialog:Open(ADDON_NAME)
end

function addon:CloseOptions()
	AceConfigDialog:Close(ADDON_NAME)
end

function addon:ToggleOptions()
	if AceConfigDialog.OpenFrames[ADDON_NAME] then
		self:CloseOptions()
	else
		self:OpenOptions()
	end
end

-- --------------------------------------------------------------------
-- Broker / minimap
-- --------------------------------------------------------------------

function addon:InitializeBroker()
	local brokerObject = LibDataBroker:NewDataObject(ADDON_NAME, {
		type = "launcher",
		tocname = ADDON_NAME,
		label = ADDON_NAME,
		text = ADDON_NAME,
		icon = self:GetBrokerIcon(),
		OnClick = function(_, button)
			if button == "RightButton" then
				self:ToggleOptions()
			else
				self:OpenOptions()
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine(ADDON_NAME, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			tooltip:AddLine(L["Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			tooltip:Show()
		end,
	})

	LibDBIcon:Register(ADDON_NAME, brokerObject, self.db.global.minimap)
end

function addon:RefreshBroker()
	if not self.db then return end

	LibDBIcon:Refresh(ADDON_NAME, self.db.global.minimap)

	local button = LibDBIcon:GetMinimapButton(ADDON_NAME)
	if button and button.icon then
		button.icon:SetTexture(self:GetBrokerIcon())
	end
end

function addon:GetBrokerIcon()
	return DEFAULT_ICON
end

-- --------------------------------------------------------------------
-- Public theme API
-- --------------------------------------------------------------------

function addon:RegisterTheme(themeKey, themeTable)
	ValidateThemeKey(themeKey, 1)
	ValidateThemeTable(themeTable, 2)

	if ThemeKeyExists(themeKey) then
		error(format("theme %q is already registered", themeKey), 2)
	end

	registeredThemes[themeKey] = themeTable
	AddThemeKey(themeKey)

	AceConfigRegistry:NotifyChange(ADDON_NAME)

	local barsModule = self:GetModule("Bars", true)
	if barsModule and type(barsModule.OnThemeRegistered) == "function" then
		barsModule:OnThemeRegistered(themeKey, themeTable)
	end
end

function addon:UnregisterTheme(themeKey)
	ValidateThemeKey(themeKey, 1)

	if not ThemeKeyExists(themeKey) then
		return
	end

	if self.db and self.db.profile.activeTheme == themeKey then
		self.db.profile.activeTheme = DEFAULT_THEME_KEY
	end

	registeredThemes[themeKey] = nil
	RemoveThemeKey(themeKey)

	AceConfigRegistry:NotifyChange(ADDON_NAME)

	local barsModule = self:GetModule("Bars", true)
	if barsModule and type(barsModule.OnThemeUnregistered) == "function" then
		barsModule:OnThemeUnregistered(themeKey)
	end
end

function addon:GetTheme(themeKey)
	ValidateThemeKey(themeKey, 1)

	return registeredThemes[themeKey]
end

function addon:GetRegisteredThemes()
	return registeredThemes
end

function addon:GetRegisteredThemeKeys()
	return registeredThemeKeys
end

function addon:SetActiveTheme(themeKey)
	ValidateThemeKey(themeKey, 1)

	if not ThemeKeyExists(themeKey) then
		error(format("theme %q is not registered", themeKey), 2)
	end

	self.db.profile.activeTheme = themeKey

	AceConfigRegistry:NotifyChange(ADDON_NAME)

	local barsModule = self:GetModule("Bars", true)
	if barsModule and type(barsModule.ApplyTheme) == "function" then
		barsModule:ApplyTheme(themeKey)
	end
end

function addon:GetActiveTheme()
	local themeKey = self.db and self.db.profile.activeTheme or DEFAULT_THEME_KEY

	return themeKey, registeredThemes[themeKey]
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