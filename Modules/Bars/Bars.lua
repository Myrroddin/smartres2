-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Bars
--
-- Core responsibilities:
-- - Create the Bars module.
-- - Register the Bars AceDB namespace.
-- - Register Bars options with SmartRes2.
-- - Own the Bars settings model.
-- - Create and configure the Bars container frame.
-- - Create, style, sort, and lay out LibCandyBar preview/runtime bars.
--
-- Runtime boundary:
-- - LibResInfo-2.0 owns resurrection detection and cast state.
-- - Bars consumes LibResInfo callbacks and displays that state.
-- - Active single-target and mass resurrection bars are keyed by casterGUID.
-- - Waiting-to-accept bars are keyed by targetGUID and never reset/extend
--   once created.
-- - Preview/test bars share the same rendering path but remain independent
--   from live LibResInfo state.
--
-- Future responsibilities:
-- - Add any remaining live edge-case handling found during gameplay testing.
-- - Apply future Themes presets by copying batches into ordinary Bars settings.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local BackdropTemplateMixin = BackdropTemplateMixin
local CreateFrame = CreateFrame
local GetTime = GetTime
local LibStub = LibStub
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_random = math.random
local next = next
local QUEUED_STATUS_WAITING = QUEUED_STATUS_WAITING
local string_format = string.format
local table_sort = table.sort
local UIParent = UIParent
local UnitNameFromGUID = UnitNameFromGUID
local UNKNOWN = UNKNOWN

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
---@class Bars: AceAddon, AceEvent-3.0, AceConsole-3.0, LibResInfo-2.0
local module = addon:NewModule("Bars")

-- --------------------------------------------------------------------
-- Libraries
-- --------------------------------------------------------------------

---@class LibCandyBar-3.0
---@field RegisterCallback fun(target: table, eventName: string, method: string, arg?: any)
---@field UnregisterCallback fun(target: table, eventName: string)
local LibCandyBar = LibStub("LibCandyBar-3.0")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

-- The resurrection accept popup times out after 60 seconds. This is a game
-- mechanic, not user preference, so Bars treats waiting bars as expired after
-- this hard cap unless LibResInfo reports the target accepted/returned alive
-- first.
local PENDING_TIMEOUT_SECONDS = 60
local MIN_BAR_HEIGHT = 20
local BAR_VERTICAL_PADDING = 6
local BAR_BACKGROUND_R = 0
local BAR_BACKGROUND_G = 0
local BAR_BACKGROUND_B = 0
local BAR_BACKGROUND_A = 0.45

-- --------------------------------------------------------------------
-- Saved variable defaults
-- --------------------------------------------------------------------

local defaults = {
	profile = {
		enabled = true,

		-- Frame/container settings. The container is visible by default so a
		-- first-run user can see that the Bars module loaded before real bars
		-- exist. Users can later opt into hiding the empty frame.
		--
		-- Pixel Snap rounds SmartRes2's own frame size and position after the
		-- frame scale is applied. It does not change the player's global UI scale.
		frame = {
			width = 250,
			height = 200,
			scale = 1,
			point = "CENTER",
			x = 0,
			y = 0,
			clampToScreen = true,
			locked = true,
			hideWhenEmpty = false,
			pixelSnap = true,
			growDirection = "DOWN",
			backdrop = {
				-- These are LibSharedMedia keys. Do not register them from
				-- SmartRes2; LibSharedMedia already provides these defaults.
				background = "Solid",
				border = "Blizzard Tooltip",
				edgeSize = 12,
				insets = {
					left = 3,
					right = 3,
					top = 3,
					bottom = 3,
				},
				-- Do not default this to pure black. The Blizzard color picker can
				-- appear to ignore the color wheel when RGB starts at 0, 0, 0 until
				-- the brightness slider is moved.
				backgroundColor = {
					r = 0.05,
					g = 0.05,
					b = 0.05,
					a = 0.35,
				},
				borderColor = {
					r = 0.8,
					g = 0.8,
					b = 0.8,
					a = 1,
				},
			},
		},

		-- Media settings store LibSharedMedia keys, not direct file paths.
		-- Bars resolves these keys when applying settings to frames/bars.
		media = {
			font = "Friz Quadrata TT",
			fontSize = 10,
			-- Store the exact WoW font flag string so Bars can pass it directly
			-- to LibCandyBar's SetFont wrapper.
			fontStyle = "SLUG, OUTLINE",
			statusBar = "Blizzard",
			barBorder = "Blizzard Tooltip",
			barBorderThickness = 4,
		},

		-- Text settings apply to both the bar label and the remaining-time text.
		-- Font flags are built from these user-facing options before being passed
		-- to LibCandyBar's SetFont wrapper.
		text = {
			color = {
				r = 1,
				g = 1,
				b = 1,
				a = 1,
			},
			shadow = false,
			shadowColor = {
				r = 0,
				g = 0,
				b = 0,
				a = 0.75,
			},
			shadowOffsetX = 1,
			shadowOffsetY = -1,
		},

		-- maxBars limits only what is rendered, not what is tracked. Hidden
		-- bars will still receive updates, resolve UNKNOWN targets, expire,
		-- and become visible later if room opens.
		behavior = {
			maxBars = 10,
			transitionDuration = 0.2,
			fill = false,
			showTime = true,
			showLabel = true,
			iconPosition = "LEFT",
			useShortLabels = false,
			barSpacing = 0,
		},

		-- Bar state colors. These are intentionally distinct for quick scanning.
		colors = {
			good = {
				r = 0.486,
				g = 0.988,
				b = 0,
				a = 1,
			},
			goodMass = {
				r = 0.35,
				g = 1,
				b = 0.65,
				a = 1,
			},
			collision = {
				r = 0.9,
				g = 0,
				b = 0,
				a = 1,
			},
			waiting = {
				r = 0.54,
				g = 0.81,
				b = 0.94,
				a = 1,
			},
		},

		-- Themes will eventually copy complete preset batches into Bars
		-- settings. Bars stores the chosen key for display/debugging, but
		-- user overrides remain ordinary Bars settings.
		activeTheme = "default",
	},
}

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

local db

-- All preview and live bars are tracked here. Active cast bars use casterGUID
-- keys; waiting bars use targetGUID keys. The source field separates preview
-- from runtime state without duplicating the rendering pipeline.
local barStates = {}

-- Runtime-only guard for waiting bars. Once a target is waiting to accept a
-- resurrection, later finished collision casts must not reset or extend that
-- 60 second waiting timer.
local waitingToAccept = {}

local candyBars = {}

local barBorderFrames = {}

local masqueButtons = {}

local masqueRegions = {}

local sortedBars = {}

local masqueGroup

-- --------------------------------------------------------------------
-- Module lifecycle
-- --------------------------------------------------------------------

-- Create the Bars AceDB namespace, cache the profile table, and register the
-- Bars options table with Core. This runs once after all Lua files are loaded,
-- so module:GetOptions() can live in BarsOptions.lua.
function module:OnInitialize()
	self.db = addon.db:RegisterNamespace(self:GetName(), defaults)

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	db = self.db.profile

	self:SetEnabledState(db.enabled)

	addon:RegisterModuleOptions(self:GetName(), self:GetOptions())
end

-- Enable visual rendering and live LibResInfo callback handling. Preview bars
-- and runtime bars use the same AddOrUpdateBar/StopBar path, so the callbacks
-- below only translate LibResInfo data into SmartRes2_BarState records.
function module:OnEnable()
	self:RefreshContainerFrame()

	LibCandyBar.RegisterCallback(self, "LibCandyBar_Stop", "OnCandyBarStopped")

	self:RegisterCallback("ResCast_Started", "OnSingleResCastStarted")
	self:RegisterCallback("ResCast_Stopped", "OnSingleResCastStopped")
	self:RegisterCallback("ResCast_Finished", "OnSingleResCastFinished")
	self:RegisterCallback("MassResCast_Started", "OnMassResCastStarted")
	self:RegisterCallback("MassResCast_Stopped", "OnMassResCastStopped")
	self:RegisterCallback("MassResCast_Finished", "OnMassResCastFinished")
	self:RegisterCallback("FastestRes_Changed", "OnFastestResChanged")
	self:RegisterCallback("ResTargetGUID_Resolved", "OnResTargetGUIDResolved")
	self:RegisterCallback("ResTargetGUID_IsAlive", "OnResTargetGUIDIsAlive")
end

-- Disable every visual/runtime hook owned by Bars. ClearBars() removes both
-- preview and live bars, while UnregisterAllResInfoCallbacks() prevents stale
-- LibResInfo callbacks after the module is disabled.
function module:OnDisable()
	self:ClearBars()

	LibCandyBar.UnregisterCallback(self, "LibCandyBar_Stop")
	self:UnregisterAllResInfoCallbacks()

	for key in next, masqueButtons do
		self:RemoveMasqueButton(key)
	end

	for targetGUID in next, waitingToAccept do
		waitingToAccept[targetGUID] = nil
	end

	if self.containerFrame then
		self.containerFrame:Hide()
	end
end

-- Re-read the current profile after profile changes/copies/resets and reapply
-- visual settings to existing bars. Live bars remain tracked while their style
-- changes; Masque can skin new/refreshing icons but may not reskin already
-- running icons in every client/addon combination.
function module:RefreshConfig()
	db = self.db.profile

	if self:IsEnabled() then
		self:RefreshContainerFrame()
		self:RefreshMasqueButtons()
	end
end

-- --------------------------------------------------------------------
-- Pixel snapping and layout math
-- --------------------------------------------------------------------

-- Rounds a frame-local value to the nearest whole pixel. SmartRes2 uses this
-- only for its own Bars frame; it never changes the player's global UI scale.
local function SnapPixelValue(value)
	return math_floor(value + 0.5)
end

local function GetProfileDB()
	return db
end

local function GetBarFrameWidth()
	local profile = GetProfileDB()
	local insets = profile.frame.backdrop.insets

	return math_max(1, profile.frame.width - insets.left - insets.right)
end

local function GetBarBorderThickness()
	local profile = GetProfileDB()
	local border = profile.media.barBorder

	if not border or border == "None" then
		return 0
	end

	return math_max(0, profile.media.barBorderThickness)
end

local function GetBarWidth()
	local borderThickness = GetBarBorderThickness()

	return math_max(1, GetBarFrameWidth() - (borderThickness * 2))
end

local function GetBarHeight()
	local profile = GetProfileDB()

	-- Keep bars readable when users choose larger fonts, but do not shrink below
	-- SmartRes2's original compact 20px inner bar height.
	return math_max(MIN_BAR_HEIGHT, profile.media.fontSize + BAR_VERTICAL_PADDING)
end

local function GetBarFrameHeight()
	return GetBarHeight() + (GetBarBorderThickness() * 2)
end

local function GetBarSpacing()
	local profile = GetProfileDB()

	return profile.behavior.barSpacing + GetBarBorderThickness()
end

local function GetBarOffsetX()
	local profile = GetProfileDB()

	return profile.frame.backdrop.insets.left
end

local function GetFirstBarOffsetY()
	local profile = GetProfileDB()
	local insets = profile.frame.backdrop.insets

	if profile.frame.growDirection == "UP" then
		return insets.bottom
	end

	return -insets.top
end

local function GetMaxVisibleBars()
	local profile = GetProfileDB()
	local insets = profile.frame.backdrop.insets
	local innerHeight = math_max(1, profile.frame.height - insets.top - insets.bottom)
	local barFrameHeight = GetBarFrameHeight()
	local barSpacing = GetBarSpacing()
	local maxBarsByHeight = math_floor((innerHeight + barSpacing) / (barFrameHeight + barSpacing))

	return math_max(1, maxBarsByHeight)
end

local previewSingleResIconClasses = {
	"PRIEST",
	"SHAMAN",
	"PALADIN",
	"DRUID",
	"MONK",
	"EVOKER",
}

local previewSingleResIconFallbacks = {
	DRUID = [[Interface\Icons\Spell_Nature_Reincarnation]],
	EVOKER = [[Interface\Icons\Spell_Nature_WispSplode]],
	MONK = [[Interface\Icons\Spell_Holy_Renew]],
	PALADIN = [[Interface\Icons\Spell_Holy_SealOfSalvation]],
	PRIEST = [[Interface\Icons\Spell_Holy_Resurrection]],
	SHAMAN = [[Interface\Icons\Spell_Nature_Regenerate]],
}

local previewMassResIcons = {
	addon:GetMassResurrectionIcon(),
	[[Interface\Icons\Spell_Holy_PrayerOfHealing02]],
	[[Interface\Icons\Spell_Holy_PrayerOfHealing]],
}

local function GetPreviewSingleResIconForClass(classFilename)
	return addon:GetResurrectionIconForClass(classFilename, false) or previewSingleResIconFallbacks[classFilename]
end

local function GetPreviewSingleResIcon(avoidIcon)
	local firstIcon
	local count = #previewSingleResIconClasses
	local startIndex = math_random(count)

	for offset = 0, count - 1 do
		local index = ((startIndex + offset - 2) % count) + 1
		local icon = GetPreviewSingleResIconForClass(previewSingleResIconClasses[index])

		if icon then
			firstIcon = firstIcon or icon

			if icon ~= avoidIcon then
				return icon
			end
		end
	end

	return firstIcon
end

local function GetPreviewMassResIcon()
	local count = #previewMassResIcons

	if count == 0 then
		return nil
	end

	return previewMassResIcons[math_random(count)]
end

-- --------------------------------------------------------------------
-- Bar labels / colors
-- --------------------------------------------------------------------

local function FormatBarLabel(state)
	if state.isWaiting then
		if db and db.behavior.useShortLabels then
			return string_format(L["%s : %s"], state.targetName, QUEUED_STATUS_WAITING)
		end

		return string_format(L["%s is waiting to accept"], state.targetName)
	end

	local casterName = state.casterName or ""

	if db and db.behavior.useShortLabels then
		return string_format(L["%s : %s"], casterName, state.targetName)
	end

	return string_format(L["%s is resurrecting %s"], casterName, state.targetName)
end

local function GetBarColor(state)
	local profile = GetProfileDB()

	if state.isWaiting then
		return profile.colors.waiting
	end

	if state.isCollision then
		return profile.colors.collision
	end

	if state.isMass then
		return profile.colors.goodMass
	end

	return profile.colors.good
end

local function CompareBarStates(a, b)
	if a.isWaiting ~= b.isWaiting then
		return not a.isWaiting
	end

	if not a.isWaiting then
		if a.endTime ~= b.endTime then
			return a.endTime < b.endTime
		end

		if a.isMass ~= b.isMass then
			return a.isMass
		end

		return (a.casterGUID or a.key) < (b.casterGUID or b.key)
	end

	return (a.targetGUID or a.key) < (b.targetGUID or b.key)
end

-- --------------------------------------------------------------------
-- LibResInfo runtime state helpers
-- --------------------------------------------------------------------

-- LibResInfo gives Bars GUIDs, spell timing, and spell texture IDs. These
-- helpers keep that data translation in one place so the actual callbacks stay
-- short and easy to compare against API.md.

local function GetCasterName(casterGUID)
	-- LibResInfo callbacks always provide a real caster GUID. If this ever fails
	-- during gameplay testing, the bug is in name resolution, not bar state.
	return UnitNameFromGUID(casterGUID)
end

local function GetTargetName(targetGUID)
	-- LibResInfo uses the literal "UNKNOWN" placeholder until a single-target
	-- resurrection target can be resolved. Show Blizzard's localized UNKNOWN
	-- string until ResTargetGUID_Resolved provides a usable GUID.
	if not targetGUID or targetGUID == "UNKNOWN" then
		return UNKNOWN
	end

	return UnitNameFromGUID(targetGUID) or UNKNOWN
end

local function BuildSingleCastState(casterGUID, targetGUID, casterInfo, targetInfo)
	local endTime = casterInfo.endTime or GetTime()
	local duration = casterInfo.castTime or 1
	local fastestCasterGUID = targetInfo and targetInfo.fastestCasterGUID
	local fastestResType = targetInfo and targetInfo.fastestResType

	return {
		key = casterGUID,
		source = "runtime",
		kind = "single",
		casterGUID = casterGUID,
		casterName = GetCasterName(casterGUID),
		targetGUID = targetGUID,
		targetName = GetTargetName(targetGUID),
		startTime = endTime - duration,
		duration = duration,
		endTime = endTime,
		isCollision = fastestCasterGUID ~= nil and (fastestCasterGUID ~= casterGUID or fastestResType ~= "SINGLE"),
		isMass = false,
		isWaiting = false,
		icon = casterInfo.textureID,
	}
end

local function BuildMassCastState(casterGUID, casterInfo)
	local endTime = casterInfo.endTime or GetTime()
	local duration = casterInfo.castTime or 1

	return {
		key = casterGUID,
		source = "runtime",
		kind = "mass",
		casterGUID = casterGUID,
		casterName = GetCasterName(casterGUID),
		targetGUID = nil,
		targetName = L["Multiple Targets"],
		startTime = endTime - duration,
		duration = duration,
		endTime = endTime,
		isCollision = false,
		isMass = true,
		isWaiting = false,
		icon = casterInfo.textureID,
	}
end

local function BuildWaitingState(targetGUID, targetName)
	local now = GetTime()

	return {
		key = targetGUID,
		source = "runtime",
		kind = "waiting",
		casterGUID = nil,
		casterName = nil,
		targetGUID = targetGUID,
		targetName = targetName,
		startTime = now,
		duration = PENDING_TIMEOUT_SECONDS,
		endTime = now + PENDING_TIMEOUT_SECONDS,
		isCollision = false,
		isMass = false,
		isWaiting = true,
		icon = nil,
	}
end

-- --------------------------------------------------------------------
-- Container frame
-- --------------------------------------------------------------------

-- Creates the visual parent frame for future CandyBars.
--
-- The container intentionally remains an ordinary, non-secure frame parented
-- to UIParent. Future bar rendering must not anchor it to protected unit
-- frames, which keeps hide/show behavior safe during combat.
function module:CreateContainerFrame()
	if self.containerFrame then
		return self.containerFrame
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", nil, UIParent, template)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(100)
	frame:EnableMouse(false)

	-- Keep the fill/background texture separate from the backdrop border.
	-- SetBackdrop handles borders well, but a regular texture makes background
	-- media and color changes immediate and predictable across clients.
	self.containerBackground = frame:CreateTexture(nil, "BACKGROUND")

	self.containerFrame = frame

	return frame
end

-- Applies the DB-driven frame style.
--
-- The background uses a normal texture so media/color changes are predictable
-- across clients. The backdrop is reserved for the border, where Blizzard's
-- BackdropTemplate API is still the right fit.
function module:ApplyContainerBackdrop()
	if not db or not self.containerFrame then
		return
	end

	local backdropSettings = db.frame.backdrop
	local backgroundColor = backdropSettings.backgroundColor
	local borderColor = backdropSettings.borderColor
	local insets = backdropSettings.insets
	local backgroundTexture = self.containerBackground

	if backgroundTexture then
		local background = addon.LSM:Fetch(
			addon.LSM.MediaType.BACKGROUND,
			backdropSettings.background,
			true
		)

		backgroundTexture:ClearAllPoints()
		backgroundTexture:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", insets.left, -insets.top)
		backgroundTexture:SetPoint("BOTTOMRIGHT", self.containerFrame, "BOTTOMRIGHT", -insets.right, insets.bottom)

		if background then
			backgroundTexture:SetTexture(background)
			backgroundTexture:SetVertexColor(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a)
			backgroundTexture:Show()
		else
			backgroundTexture:Hide()
		end
	end

	if not self.containerFrame.SetBackdrop then
		return
	end

	local border = addon.LSM:Fetch(
		addon.LSM.MediaType.BORDER,
		backdropSettings.border,
		true
	)

	self.containerFrame:SetBackdrop({
		edgeFile = border,
		edgeSize = backdropSettings.edgeSize,
		insets = {
			left = insets.left,
			right = insets.right,
			top = insets.top,
			bottom = insets.bottom,
		},
	})

	if border then
		self.containerFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
	end
end

-- Applies profile frame settings to the container. This helper only handles
-- the container itself; CandyBar positioning happens in a separate layout pass
-- so hidden bars can remain tracked without being visibly rendered.
function module:ApplyContainerFrameSettings()
	if not db then return end

	local frameSettings = db.frame
	local frame = self:CreateContainerFrame()

	local width = frameSettings.width
	local height = frameSettings.height
	local x = frameSettings.x
	local y = frameSettings.y

	-- Apply scale before snapping local dimensions/offsets. Snapping first and
	-- then scaling would reintroduce fractional placement.
	frame:SetScale(frameSettings.scale)

	if frameSettings.pixelSnap then
		width = SnapPixelValue(width)
		height = SnapPixelValue(height)
		x = SnapPixelValue(x)
		y = SnapPixelValue(y)
	end

	frame:ClearAllPoints()
	frame:SetPoint(frameSettings.point, UIParent, frameSettings.point, x, y)
	frame:SetSize(width, height)
	frame:SetClampedToScreen(frameSettings.clampToScreen)

	self:ApplyContainerBackdrop()
end

-- --------------------------------------------------------------------
-- Masque icon skinning
-- --------------------------------------------------------------------

local function IsMasqueEnabled()
	return addon.Masque ~= nil and addon.db and addon.db.profile and addon.db.profile.useMasque
end

function module:GetMasqueGroup()
	local Masque = addon.Masque

	if not Masque or not addon.db or not addon.db.profile.useMasque then
		return nil
	end

	if not masqueGroup then
		masqueGroup = Masque:Group("SmartRes2", "Bars")
	end

	return masqueGroup
end

local function HideCandyBarIconTexture(bar)
	local iconTexture = bar.icon or bar.Icon or bar.candyBarIcon

	if iconTexture then
		iconTexture:Hide()
	end
end

function module:GetOrCreateMasqueButton(key, parent)
	local button = masqueButtons[key]

	if button then
		button:SetParent(parent)
		return button
	end

	button = CreateFrame("Button", nil, parent)
	button:EnableMouse(false)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(111)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints(button)
	button.Icon = icon

	local normal = button:CreateTexture(nil, "BORDER")
	normal:SetAllPoints(button)
	button.Normal = normal
	button:SetNormalTexture(normal)

	masqueButtons[key] = button

	return button
end

function module:ApplyMasqueIcon(state, bar)
	local key = state.key
	local group = self:GetMasqueGroup()
	local button = masqueButtons[key]

	if not group or not state.icon or GetProfileDB().behavior.iconPosition == "NONE" then
		if button then
			self:RemoveMasqueButton(key)
		end

		return
	end

	HideCandyBarIconTexture(bar)

	button = self:GetOrCreateMasqueButton(key, bar)
	button:ClearAllPoints()
	button:SetSize(GetBarHeight(), GetBarHeight())

	if GetProfileDB().behavior.iconPosition == "RIGHT" then
		button:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	else
		button:SetPoint("LEFT", bar, "LEFT", 0, 0)
	end

	local icon = button.Icon
	local normal = button.Normal

	if not icon or not normal then
		return
	end

	icon:SetTexture(state.icon)
	icon:SetAllPoints(button)
	normal:SetAllPoints(button)
	button:Show()

	local regions = masqueRegions[key]
	if not regions then
		regions = {
			Icon = icon,
			Normal = normal,
		}
		masqueRegions[key] = regions
	else
		regions.Icon = icon
		regions.Normal = normal
	end

	group:AddButton(button, regions, "Item", true)
	group:ReSkin()
end

function module:RemoveMasqueButton(key)
	local button = masqueButtons[key]

	if not button then
		return
	end

	if masqueGroup then
		masqueGroup:RemoveButton(button)
	end

	masqueRegions[key] = nil
	masqueButtons[key] = nil

	button:Hide()
	button:SetParent(nil)
end

function module:RefreshMasqueButtons()
	if not IsMasqueEnabled() then
		for key in next, masqueButtons do
			self:RemoveMasqueButton(key)
		end

		return
	end

	for _, state in next, barStates do
		local bar = candyBars[state.key]

		if bar then
			self:ApplyMasqueIcon(state, bar)
		end
	end

	if masqueGroup then
		masqueGroup:ReSkin()
	end
end

-- --------------------------------------------------------------------
-- Individual bar border frames
-- --------------------------------------------------------------------

function module:GetOrCreateBarBorderFrame(key)
	local frame = barBorderFrames[key]

	if frame then
		return frame
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", nil, self:CreateContainerFrame(), template)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(109)
	frame:EnableMouse(false)

	barBorderFrames[key] = frame

	return frame
end

function module:ApplyBarBorderSettings(frame)
	local profile = GetProfileDB()
	local borderThickness = GetBarBorderThickness()

	frame:SetParent(self:CreateContainerFrame())
	frame:SetSize(GetBarFrameWidth(), GetBarFrameHeight())

	if not frame.SetBackdrop or borderThickness <= 0 then
		if frame.SetBackdrop then
			frame:SetBackdrop(nil)
		end
		return
	end

	local border = addon.LSM:Fetch(addon.LSM.MediaType.BORDER, profile.media.barBorder, true)

	if not border then
		frame:SetBackdrop(nil)
		return
	end

	frame:SetBackdrop({
		edgeFile = border,
		edgeSize = borderThickness,
		insets = {
			left = borderThickness,
			right = borderThickness,
			top = borderThickness,
			bottom = borderThickness,
		},
	})
	frame:SetBackdropBorderColor(1, 1, 1, 1)
end

-- --------------------------------------------------------------------
-- CandyBar rendering and bar lifecycle
-- --------------------------------------------------------------------

-- This section owns the shared rendering pipeline. Preview bars, live cast
-- bars, and waiting bars all become SmartRes2_BarState records and flow through
-- AddOrUpdateBar(), RefreshCandyBar(), LayoutCandyBars(), and StopBar().

local function GetStatusBarTexture()
	local profile = GetProfileDB()

	return addon.LSM:Fetch(addon.LSM.MediaType.STATUSBAR, profile.media.statusBar)
end

local function GetFontFile()
	local profile = GetProfileDB()

	return addon.LSM:Fetch(addon.LSM.MediaType.FONT, profile.media.font)
end

local function IsFontSlugStyle(fontStyle)
	return fontStyle == "SLUG" or fontStyle == "SLUG, OUTLINE"
end

local function GetFontFlags()
	return GetProfileDB().media.fontStyle
end

function module:GetOrCreateCandyBar(key)
	local bar = candyBars[key]

	if bar then
		return bar
	end

	bar = LibCandyBar:New(GetStatusBarTexture(), GetBarWidth(), GetBarHeight())
	bar:Set("SmartRes2Key", key)
	bar:SetParent(self:GetOrCreateBarBorderFrame(key))
	bar:SetFrameStrata("MEDIUM")
	bar:SetFrameLevel(110)
	bar:EnableMouse(false)

	candyBars[key] = bar

	return bar
end

function module:ApplyCandyBarSettings(state, bar)
	local profile = GetProfileDB()
	local color = GetBarColor(state)
	local icon = state.icon

	local borderFrame = self:GetOrCreateBarBorderFrame(state.key)
	local borderThickness = GetBarBorderThickness()

	self:ApplyBarBorderSettings(borderFrame)

	bar:SetParent(borderFrame)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", borderThickness, -borderThickness)
	bar:SetSize(GetBarWidth(), GetBarHeight())
	bar:SetTexture(GetStatusBarTexture())
	bar:SetFill(profile.behavior.fill)
	bar:SetColor(color.r, color.g, color.b, color.a)
	bar:SetBackgroundColor(BAR_BACKGROUND_R, BAR_BACKGROUND_G, BAR_BACKGROUND_B, BAR_BACKGROUND_A)
	bar:SetTextColor(profile.text.color.r, profile.text.color.g, profile.text.color.b, profile.text.color.a)
	bar:SetFont(GetFontFile(), profile.media.fontSize, GetFontFlags())
	bar:SetLabel(FormatBarLabel(state))
	bar:SetTimeVisibility(profile.behavior.showTime)
	bar:SetLabelVisibility(profile.behavior.showLabel)

	if profile.text.shadow and not IsFontSlugStyle(profile.media.fontStyle) then
		bar:SetShadowOffset(profile.text.shadowOffsetX, profile.text.shadowOffsetY)
		bar:SetShadowColor(
			profile.text.shadowColor.r,
			profile.text.shadowColor.g,
			profile.text.shadowColor.b,
			profile.text.shadowColor.a
		)
	else
		bar:SetShadowOffset(0, 0)
		bar:SetShadowColor(0, 0, 0, 0)
	end

	if not icon or profile.behavior.iconPosition == "NONE" then
		bar:SetIcon(nil)
	else
		bar:SetIcon(icon)
		bar:SetIconPosition(profile.behavior.iconPosition)
	end

	self:ApplyMasqueIcon(state, bar)
end

function module:RefreshCandyBar(state)
	local bar = candyBars[state.key]

	if not bar then
		return
	end

	self:ApplyCandyBarSettings(state, bar)
end

function module:RefreshCandyBars()
	for _, state in next, barStates do
		self:RefreshCandyBar(state)
	end
end

function module:BuildSortedBars()
	for index in next, sortedBars do
		sortedBars[index] = nil
	end

	for _, state in next, barStates do
		sortedBars[#sortedBars + 1] = state
	end

	table_sort(sortedBars, CompareBarStates)
end

function module:LayoutCandyBars()
	if not db or not self.containerFrame then
		return
	end

	local profile = GetProfileDB()

	self:BuildSortedBars()

	local previousBar
	local maxBars = math_min(profile.behavior.maxBars, GetMaxVisibleBars())
	local growUp = profile.frame.growDirection == "UP"
	local offsetX = GetBarOffsetX()
	local firstBarOffsetY = GetFirstBarOffsetY()

	for index, state in next, sortedBars do
		local bar = candyBars[state.key]
		local borderFrame = barBorderFrames[state.key]

		if bar and borderFrame then
			borderFrame:ClearAllPoints()
			borderFrame:SetSize(GetBarFrameWidth(), GetBarFrameHeight())
			bar:SetSize(GetBarWidth(), GetBarHeight())

			if index <= maxBars then
				if not previousBar then
					if growUp then
						borderFrame:SetPoint("BOTTOMLEFT", self.containerFrame, "BOTTOMLEFT", offsetX, firstBarOffsetY)
					else
						borderFrame:SetPoint("TOPLEFT", self.containerFrame, "TOPLEFT", offsetX, firstBarOffsetY)
					end
				elseif growUp then
					borderFrame:SetPoint("BOTTOMLEFT", previousBar, "TOPLEFT", 0, GetBarSpacing())
				else
					borderFrame:SetPoint("TOPLEFT", previousBar, "BOTTOMLEFT", 0, -GetBarSpacing())
				end

				borderFrame:Show()
				bar:Show()
				previousBar = borderFrame
			else
				bar:Hide()
				borderFrame:Hide()
			end
		end
	end
end

function module:AddOrUpdateBar(state)
	if not db then
		return
	end

	local now = GetTime()

	state.startTime = state.startTime or now
	state.duration = state.duration or 1
	state.endTime = state.endTime or (state.startTime + state.duration)
	barStates[state.key] = state

	local bar = self:GetOrCreateCandyBar(state.key)
	self:ApplyCandyBarSettings(state, bar)
	bar:SetDuration(state.duration)
	bar:Start()

	self:RefreshContainerVisibility()
	self:LayoutCandyBars()
end

function module:StopBar(key)
	local state = barStates[key]
	local bar = candyBars[key]
	local borderFrame = barBorderFrames[key]

	if state and state.isWaiting and state.targetGUID then
		waitingToAccept[state.targetGUID] = nil
	end

	barStates[key] = nil
	candyBars[key] = nil
	barBorderFrames[key] = nil

	if bar then
		bar:Stop("SmartRes2_StopBar")
	end

	self:RemoveMasqueButton(key)

	if borderFrame then
		borderFrame:Hide()
		borderFrame:SetParent(nil)
	end
end

function module:ClearBars(source)
	local keys = {}

	for key, state in next, barStates do
		if not source or state.source == source then
			keys[#keys + 1] = key
		end
	end

	for index = 1, #keys do
		self:StopBar(keys[index])
	end

	self:RefreshContainerVisibility()
	self:LayoutCandyBars()
end

function module:ClearTestBars()
	self:ClearBars("preview")
end

function module:ShowTestBars()
	self:ClearTestBars()

	local now = GetTime()
	local alyndraIcon = GetPreviewSingleResIcon()
	local caliaIcon = GetPreviewSingleResIcon(alyndraIcon)
	local maerinIcon = GetPreviewMassResIcon()

	self:AddOrUpdateBar({
		key = "SmartRes2_Preview_GoodSingle",
		source = "preview",
		kind = "single",
		casterGUID = "SmartRes2-Preview-Alyndra",
		casterName = "Alyndra",
		targetGUID = "SmartRes2-Preview-Brennor",
		targetName = "Brennor",
		startTime = now,
		duration = 8,
		endTime = now + 8,
		isCollision = false,
		isMass = false,
		isWaiting = false,
		icon = alyndraIcon,
		transitionToWaiting = true,
		waitingKey = "SmartRes2_Preview_BrennorWaiting",
	})

	self:AddOrUpdateBar({
		key = "SmartRes2_Preview_CollisionSingle",
		source = "preview",
		kind = "single",
		casterGUID = "SmartRes2-Preview-Calia",
		casterName = "Calia",
		targetGUID = "SmartRes2-Preview-Brennor",
		targetName = "Brennor",
		startTime = now,
		duration = 10,
		endTime = now + 10,
		isCollision = true,
		isMass = false,
		isWaiting = false,
		icon = caliaIcon,
	})

	self:AddOrUpdateBar({
		key = "SmartRes2_Preview_GoodMass",
		source = "preview",
		kind = "mass",
		casterGUID = "SmartRes2-Preview-Maerin",
		casterName = "Maerin",
		targetGUID = nil,
		targetName = L["Multiple Targets"],
		startTime = now,
		duration = 10,
		endTime = now + 10,
		isCollision = false,
		isMass = true,
		isWaiting = false,
		icon = maerinIcon,
	})

	self:AddOrUpdateBar({
		key = "SmartRes2_Preview_Waiting",
		source = "preview",
		kind = "waiting",
		casterGUID = nil,
		casterName = nil,
		targetGUID = "SmartRes2-Preview-Tovin",
		targetName = "Tovin",
		startTime = now,
		duration = PENDING_TIMEOUT_SECONDS,
		endTime = now + PENDING_TIMEOUT_SECONDS,
		isCollision = false,
		isMass = false,
		isWaiting = true,
		icon = nil,
	})
end

function module:OnCandyBarStopped(callback, bar, reason)
	local key = bar:Get("SmartRes2Key")

	local state

	if key then
		local borderFrame = barBorderFrames[key]

		state = barStates[key]

		if state and state.isWaiting and state.targetGUID then
			waitingToAccept[state.targetGUID] = nil
		end

		barStates[key] = nil
		candyBars[key] = nil
		barBorderFrames[key] = nil

		self:RemoveMasqueButton(key)

		if borderFrame then
			borderFrame:Hide()
			borderFrame:SetParent(nil)
		end
	end

	if state and state.transitionToWaiting and reason ~= "SmartRes2_StopBar" then
		local waitingKey = state.waitingKey or (state.key .. "_Waiting")

		if barStates[waitingKey] then
			self:RefreshContainerVisibility()
			self:LayoutCandyBars()
			return
		end

		local now = GetTime()

		self:AddOrUpdateBar({
			key = waitingKey,
			source = state.source,
			kind = "waiting",
			casterGUID = nil,
			casterName = nil,
			targetGUID = state.targetGUID,
			targetName = state.targetName,
			startTime = now,
			duration = PENDING_TIMEOUT_SECONDS,
			endTime = now + PENDING_TIMEOUT_SECONDS,
			isCollision = false,
			isMass = false,
			isWaiting = true,
			icon = nil,
		})

		return
	end

	self:RefreshContainerVisibility()
	self:LayoutCandyBars()
end

function module:SetBarCollision(key, isCollision)
	local state = barStates[key]

	if not state then
		return
	end

	state.isCollision = isCollision
	self:RefreshCandyBar(state)
end

function module:HasTestBars()
	for _, state in next, barStates do
		if state.source == "preview" then
			return true
		end
	end

	return false
end

-- Returns true when there is something meaningful to show inside the container.
function module:HasVisibleBars()
	return next(barStates) ~= nil
end

-- Centralizes container visibility so hideWhenEmpty is applied consistently.
-- With the default hideWhenEmpty = false, first-run users see the frame and
-- know the Bars module loaded correctly.
function module:RefreshContainerVisibility()
	local frame = self:CreateContainerFrame()

	if not db then
		frame:Hide()
		return
	end

	if db.frame.hideWhenEmpty and not self:HasVisibleBars() then
		frame:Hide()
	else
		frame:Show()
	end
end

function module:RefreshContainerFrame()
	self:ApplyContainerFrameSettings()
	self:RefreshCandyBars()
	self:LayoutCandyBars()
	self:RefreshContainerVisibility()
end

-- --------------------------------------------------------------------
-- LibResInfo callback handlers
-- --------------------------------------------------------------------

-- These callbacks should stay thin: translate LibResInfo callback arguments
-- into bar state changes, then delegate all visual work to the common bar
-- lifecycle/rendering helpers above.

function module:OnSingleResCastStarted(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	self:AddOrUpdateBar(BuildSingleCastState(casterGUID, targetGUID, casterInfo, targetInfo))
end

function module:OnSingleResCastStopped(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	self:StopBar(casterGUID)
	self:RefreshTargetCollisionStates(targetGUID, targetInfo)
end

function module:OnSingleResCastFinished(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	self:StopBar(casterGUID)

	-- Waiting bars are target-lifecycle bars. Once created, they must not be
	-- reset, extended, or replaced by later finished collision casts.
	if targetGUID == "UNKNOWN" or waitingToAccept[targetGUID] then
		return
	end

	waitingToAccept[targetGUID] = true
	self:AddOrUpdateBar(BuildWaitingState(targetGUID, GetTargetName(targetGUID)))
end

function module:OnMassResCastStarted(callback, casterGUID, casterInfo)
	self:AddOrUpdateBar(BuildMassCastState(casterGUID, casterInfo))
end

function module:OnMassResCastStopped(callback, casterGUID, casterInfo)
	self:StopBar(casterGUID)
end

function module:OnMassResCastFinished(callback, casterGUID, casterInfo)
	self:StopBar(casterGUID)
end

function module:RefreshTargetCollisionStates(targetGUID, targetInfo)
	if not targetGUID or targetGUID == "UNKNOWN" or not targetInfo then
		return
	end

	for _, state in next, barStates do
		if state.source == "runtime" and not state.isWaiting and not state.isMass and state.targetGUID == targetGUID then
			state.isCollision = targetInfo.fastestCasterGUID ~= nil
				and (targetInfo.fastestCasterGUID ~= state.casterGUID or targetInfo.fastestResType ~= "SINGLE")
			self:RefreshCandyBar(state)
		end
	end
end

function module:OnFastestResChanged(callback, targetGUID, targetInfo)
	self:RefreshTargetCollisionStates(targetGUID, targetInfo)
end

function module:OnResTargetGUIDResolved(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	-- Replace the temporary UNKNOWN target with the resolved target name/GUID,
	-- then recalculate collision color for all active single-target bars aimed
	-- at that target.
	local state = barStates[casterGUID]

	if state and state.source == "runtime" and not state.isMass and not state.isWaiting then
		state.targetGUID = targetGUID
		state.targetName = GetTargetName(targetGUID)
		state.endTime = casterInfo.endTime
		state.duration = casterInfo.castTime
		state.startTime = casterInfo.endTime - casterInfo.castTime
		state.icon = casterInfo.textureID
		state.isCollision = targetInfo.fastestCasterGUID ~= nil
			and (targetInfo.fastestCasterGUID ~= casterGUID or targetInfo.fastestResType ~= "SINGLE")
		self:RefreshCandyBar(state)
	end

	self:RefreshTargetCollisionStates(targetGUID, targetInfo)
end

function module:OnResTargetGUIDIsAlive(callback, targetGUID)
	if waitingToAccept[targetGUID] then
		self:StopBar(targetGUID)
	end
end

-- --------------------------------------------------------------------
-- Public-to-addon helpers
-- --------------------------------------------------------------------

-- These are intentionally tiny accessors for Core, options, and later modules.
-- Keep gameplay/rendering logic above so public surface area stays obvious.

function module:GetProfile()
	return db
end

function module:GetPendingTimeout()
	return PENDING_TIMEOUT_SECONDS
end