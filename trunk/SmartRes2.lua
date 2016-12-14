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

-- declare addon --------------------------------------------------------------
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

local version = GetAddOnMetadata("SmartRes2", "Version")
if version:match("@") then
	version = "Development"
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
			["*"] = true
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

-- options table --------------------------------------------------------------
function SmartRes2:GetOptions()
	local options = {
		name = "SmartRes2 " .. version,
		handler = SmartRes2,
		type = "group",
		childGroups = "tab",
		args = {
			general = {
				order = 1,
				name = COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL,
				type = "group",
				args = {
					enableAddOn = {
						order = 10,
						type = "toggle",
						name = ENABLE,
						desc = L["Toggle SmartRes2 and all modules on/off."],
						get = function() return self.db.profile.enableAddOn end,
						set = function(info, value)
							self.db.profile.enableAddOn = value
							if value then
								self:Enable()
							else
								self:Disable()
							end
						end
					},
					minimap = {
						type = "toggle",
						order = 20,
						name = MINIMAP_LABEL,
						desc = L["Show or hide the minimap icon."],
						get = function() return not self.db.global.minimap.hide end,
						set = function(_, value)
							self.db.global.minimap.hide = not value
							if value then
								DBI:Show("SmartRes2")
							else
								DBI:Hide("SmartRes2")
							end
						end
					},
					buttonLock = {
						type = "toggle",
						order = 30,
						name = L["Lock Button"],
						desc = L["Lock minimap button and prevent moving."],
						get = function() return self.db.global.minimap.lock end,
						set = function(_, value)
							self.db.global.minimap.lock = value
							if value then
								DBI:Lock("SmartRes2")
							else
								DBI:Unlock("SmartRes2")
							end
						end
					}
				}
			}
		}
	}
	return options
end

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

	local options = self:GetOptions()
	Registry:RegisterOptionsTable("SmartRes2", options)

	options.args.profile = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profile.order = -1	

	-- dual spec the options
	LDS:EnhanceDatabase(self.db, "SmartRes2")
	LDS:EnhanceOptions(options.args.profile, self.db)	

	Dialog:AddToBlizOptions("SmartRes2", nil, nil, "general")

	-- now embed module options into SmartRes2's options
	for name, module in self:IterateModules() do
		if type(module.GetOptions) == "function" then
			options.args[name] = module:GetOptions()
			local displayName = options.args[name].name
			Dialog:AddToBlizOptions(name, displayName, "SmartRes2", name)
		end
	end

	-- add console commands
	self:RegisterChatCommand("sr", "SlashHandler")
	self:RegisterChatCommand("smartres", "SlashHandler")

	-- create LDB Launcher
	self.launcher = LDB:NewDataObject("SmartRes2 ".. version, {
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
			GameTooltip:AddLine("SmartRes2 " .. version, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
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

	for name, module in self:IterateModules() do
		local isEnabled, shouldEnable = module:IsEnabled(), self:GetModuleEnabled(name)
		if shouldEnable and not isEnabled then
			self:EnableModule(name)
		elseif isEnabled and not shouldEnable then
			self:DisableModule(name)
		end

		if type(module.Refresh) == "function" then
			module:Refresh()
		end
	end
end

-- handle modules -------------------------------------------------------------
function SmartRes2:GetModuleEnabled(moduleName)
	return db.modules[moduleName]
end

function SmartRes2:SetModuleEnabled(moduleName, newState)
	local oldState = db.modules[moduleName]
	if oldState == newState then return end
	if newState then
		self:EnableModule(moduleName)
	else
		self:DisableModule(moduleName)
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