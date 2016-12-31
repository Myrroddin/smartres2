--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Myrroddin of Llane
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- upvalue globals ------------------------------------------------------------
local _G = getfenv(0)
local LibStub = _G.LibStub
local GetSpellInfo = _G.GetSpellInfo
local UnitClass = _G.UnitClass
local COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL = _G.COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL
local ENABLE = _G.ENABLE
local GameTooltip = _G.GameTooltip
local HIGHLIGHT_FONT_COLOR = _G.HIGHLIGHT_FONT_COLOR
local MINIMAP_LABEL = _G.MINIMAP_LABEL
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local select = _G.select
local type = _G.type
local UnitAffectingCombat = _G.UnitAffectingCombat
local GetAddOnMetadata = _G.GetAddOnMetadata

-- declare addon --------------------------------------------------------------
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

SmartRes2.version = GetAddOnMetadata("SmartRes2", "Version")
if SmartRes2.version:match("@") then
	SmartRes2.version = "Development"
end

-- additional libraries -------------------------------------------------------
local LDB = LibStub("LibDataBroker-1.1")
local DBI = LibStub("LibDBIcon-1.0")
local LDS = LibStub("LibDualSpec-1.0")
local Dialog = LibStub("AceConfigDialog-3.0")
local Registry = LibStub("AceConfigRegistry-3.0")
local Command = LibStub("AceConfigCmd-3.0")

-- declare variables ----------------------------------------------------------
local db

-- defaults table -------------------------------------------------------------
local defaults = {
	profile = {
		enableAddOn = true,
		modules = {
			['*'] = true
		}
	},
	global = {
		minimap = {
			hide = false,
            lock = true,
            minimapPos = 190,
            radius = 80
		}
	}
}

-- returns proper LDB icon ----------------------------------------------------
local function GetIcon()
	local default_icon = select(3, GetSpellInfo(2006))

	local resSpells = { -- getting the spell names
		PRIEST = GetSpellInfo(2006), -- Resurrection
		SHAMAN = GetSpellInfo(2008), -- Ancestral Spirit
		DRUID = GetSpellInfo(50769), -- Revive
		PALADIN = GetSpellInfo(7328), -- Redemption
		MONK = GetSpellInfo(115178) -- Resuscitate
	}

	local _, player_class = UnitClass("player")
	local playerSpell = resSpells[player_class]

	local icon = playerSpell and select(3, GetSpellInfo(playerSpell)) or default_icon
	return icon
end

-- standard methods -----------------------------------------------------------
function SmartRes2:OnInitialize()
	-- register saved variables with AceDB
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)
	db = self.db.profile

	-- db update callbacks
	self.db.RegisterCallback(self, "OnProfileChanged", "Refresh")
	self.db.RegisterCallback(self, "OnProfileCopied", "Refresh")
	self.db.RegisterCallback(self, "OnProfileReset", "Refresh")

	self:SetupOptions()

	-- add console commands
	self:RegisterChatCommand("sr", "SlashHandler")
	self:RegisterChatCommand("smartres", "SlashHandler")

	-- create LDB Launcher
	self.launcher = LDB:NewDataObject("SmartRes2 ".. SmartRes2.version, {
		type = "launcher",
		icon = GetIcon(),
		OnClick = function(clickedframe, button)
			if UnitAffectingCombat("player") then
				if Dialog.OpenFrames["SmartRes2"] then
					Dialog:Close("SmartRes2")
				end
				return
			end
			if button == "RightButton" then
				if Dialog.OpenFrames["SmartRes2"] then
					Dialog:Close("SmartRes2")
				else
					Dialog:Open("SmartRes2")
				end
			end
		end,
		OnTooltipShow = function(self)
			GameTooltip:AddLine("SmartRes2 " .. SmartRes2.version, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			GameTooltip:AddLine(L["Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:Show()
		end
	})
	DBI:Register("SmartRes2", self.launcher, self.db.global.minimap)

	-- OnEnable/OnDisable as appropriate
	self:SetEnabledState(self.db.profile.enableAddOn)
end

function SmartRes2:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function SmartRes2:OnDisable()
	self:UnregisterAllEvents()
end

-- update our database --------------------------------------------------------
function SmartRes2:Refresh()
	db = self.db.profile

	for k, v in self:IterateModules() do
		if self:GetModuleEnabled(k) and not v:IsEnabled() then
			self:EnableModule(k)
		elseif not self:GetModuleEnabled(k) and v:IsEnabled() then
			self:DisableModule(k)
		end
		if type(v.Refresh) == "function" then
			v:Refresh()
		end
	end
end

function SmartRes2:GetModuleEnabled(module)
	return db.modules[module]
end

function SmartRes2:SetModuleEnabled(module, value)
	local old = db.modules[module]
	db.modules[module] = value
	if old ~= value then
		if value then
			self:EnableModule(module)
		else
			self:DisableModule(module)
		end
	end
end

-- process slash commands -----------------------------------------------------
function SmartRes2:SlashHandler(input)
	if UnitAffectingCombat("player") then
		return
	end

	if Dialog.OpenFrames["SmartRes2"] then
		Dialog:Close("SmartRes2")
	else
		Dialog:Open("SmartRes2")
	end
end

function SmartRes2:PLAYER_REGEN_DISABLED()
	if Dialog.OpenFrames["SmartRes2"] then
		Dialog:Close("SmartRes2")
	end
end