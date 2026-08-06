-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Bars
--
-- Responsibilities:
-- - Initialize the Bars settings namespace and lifecycle.
-- - Track preview, active-cast, and waiting-to-accept bar state.
-- - Create, style, sort, and lay out resurrection bars.
-- - Manage bar icons, borders, visibility, and runtime state updates.
-- - Refresh target waiting bars when newer resurrection offers complete.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local After = C_Timer.After
local BackdropTemplateMixin = BackdropTemplateMixin
local CreateFrame = CreateFrame
local GetNumGroupMembers = GetNumGroupMembers
local GetTime = GetTime
local IsInRaid = IsInRaid
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
local UnitClassBase = UnitClassBase
local UnitGUID = UnitGUID
local UNKNOWN = UNKNOWN

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

---@class LibCandyBar-3.0
---@field RegisterCallback fun(target: table, eventName: string, method: string, arg?: any)
---@field UnregisterCallback fun(target: table, eventName: string)

---@class Bars: AceAddon, AceEvent-3.0, AceConsole-3.0, LibResInfo-2.0
---@field LibCandyBar LibCandyBar-3.0
---@field db AceDBObject-3.0
local module = addon:NewModule("Bars")
module.LibCandyBar = LibStub("LibCandyBar-3.0")

-- --------------------------------------------------------------------
-- Lifecycle state and defaults
-- --------------------------------------------------------------------

---@type table
local db
local defaults = {
	profile = {
		enabled = true,
		useClassColorsForBars = true,
		useFullNameForBars = true,
		frame = {
			width = 250,
			height = 200,
			scale = 1,
			point = "CENTER",
			x = 0,
			y = 0,
			clampToScreen = true,
			locked = false,
			hideWhenEmpty = false,
			pixelSnap = true,
			growDirection = "DOWN",
			backdrop = {
				background = "Papyrus",
				border = "Blizzard Tooltip",
				edgeSize = 12,
				insets = {
					left = 3,
					right = 3,
					top = 3,
					bottom = 3,
				},
				-- Do not default this to pure black. Besides making textured
				-- backgrounds effectively invisible, Blizzard's color picker can appear
				-- to ignore the color wheel until the brightness slider is moved.
				backgroundColor = {
					r = 1,
					g = 1,
					b = 1,
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

		-- Media settings store registered media keys rather than file paths.
		media = {
			font = "Friz Quadrata TT",
			fontSize = 12,
			fontStyle = "SLUG, OUTLINE",
			statusBar = "Blizzard",
			barBorder = "Blizzard Tooltip",
			barBorderThickness = 4,
		},

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
			mirrorBars = false,
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
	},
}

-- --------------------------------------------------------------------
-- Static configuration
-- --------------------------------------------------------------------

-- Preview waiting bars use the base 60-second resurrection accept timeout.
-- Runtime waiting bars use LibResInfo's remaining time, which also accounts
-- for the player's corpse-recovery delay.
local PENDING_TIMEOUT_SECONDS = 60
local MIN_BAR_HEIGHT = 20
local BAR_VERTICAL_PADDING = 6
local BAR_BACKGROUND_R = 0
local BAR_BACKGROUND_G = 0
local BAR_BACKGROUND_B = 0
local BAR_BACKGROUND_A = 0.45
local UNKNOWN_NAME_COLOR = {r = 0.8, g = 0.8, b = 0.8}

-- --------------------------------------------------------------------
-- LibSharedMedia registration
-- --------------------------------------------------------------------

local function RegisterMedia()
	-- Backgrounds
	addon.LSM:Register(
		addon.LSM.MediaType.BACKGROUND,
		"Aged Leather",
		[[Interface\AddOns\SmartRes2\Media\Backgrounds\aged-leather.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.BACKGROUND,
		"Ancient Sandstone",
		[[Interface\AddOns\SmartRes2\Media\Backgrounds\ancient-sandstone.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.BACKGROUND,
		"Classical Marble",
		[[Interface\AddOns\SmartRes2\Media\Backgrounds\classical-marble.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.BACKGROUND,
		"Dragonflight Rock",
		[[Interface\AddOns\SmartRes2\Media\Backgrounds\Dragonflight-rock.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.BACKGROUND,
		"Papyrus",
		[[Interface\AddOns\SmartRes2\Media\Backgrounds\papyrus.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.BACKGROUND,
		"Volcanic Slate",
		[[Interface\AddOns\SmartRes2\Media\Backgrounds\volcanic-slate.png]]
	)

	-- Borders
	addon.LSM:Register(
		addon.LSM.MediaType.BORDER,
		"Glow",
		[[Interface\AddOns\SmartRes2\Media\Borders\GlowTex.png]]
	)

	-- Fonts
	addon.LSM:Register(
		addon.LSM.MediaType.FONT,
		"Cleopatra",
		[[Interface\AddOns\SmartRes2\Media\Fonts\Cleopatra.ttf]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.FONT,
		"Herculanum",
		[[Interface\AddOns\SmartRes2\Media\Fonts\Herculanum.ttf]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.FONT,
		"Norse",
		[[Interface\AddOns\SmartRes2\Media\Fonts\Norse-KaWl.ttf]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.FONT,
		"Norse Bold",
		[[Interface\AddOns\SmartRes2\Media\Fonts\NorseBold-2Kge.ttf]]
	)

	-- Sounds
	addon.LSM:Register(
		addon.LSM.MediaType.SOUND,
		"Click Select",
		[[Interface\AddOns\SmartRes2\Media\Sounds\clickselect2.ogg]]
	)

	-- Status bars
	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"Brushed Steel",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\brushed-steel.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"Dragonflight Health Bar",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\Dragonflight-Statusbar.png]]
	)

	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"Gloss",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\Gloss.png]]
	)

	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"LiteStep",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\LiteStep.png]]
	)

	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"LiteStep Lite",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\LiteStepLite.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"Hammered Bronze",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\hammered-bronze.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"Marble Stone",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\marble-stone.png]]
	)
	addon.LSM:Register(
		addon.LSM.MediaType.STATUSBAR,
		"Rune Stone",
		[[Interface\AddOns\SmartRes2\Media\Statusbars\rune-stone.png]]
	)
end

-- --------------------------------------------------------------------
-- Runtime state
-- --------------------------------------------------------------------

local containerFrame, containerBackground

-- All preview and live bars are tracked here. Active cast bars use casterGUID
-- keys; waiting bars use targetGUID keys. The source field separates preview
-- from runtime state without duplicating the rendering pipeline.
local barStates = {}

-- Tracks targets with active waiting bars so alive notifications can remove
-- the matching bar and runtime marker together.
local waitingToAccept = {}

-- Waiting bars may be delayed briefly after a cast finishes. Entries are
-- invalidated instead of cancelled because C_Timer.After has no timer handle.
local pendingWaitingTransitions = {}

local candyBars = {}
local barBorderFrames = {}
local masqueButtons = {}
local masqueRegions = {}
local sortedBars = {}

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
	local insets = profile.frame.backdrop.insets

	if profile.behavior.mirrorBars then
		return -insets.right
	end

	return insets.left
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

local function GetBarDisplayName(name, classFilename)
	if not db.useClassColorsForBars then
		return name
	end

	if name == UNKNOWN then
		return addon:GetClassColoredName(name, classFilename, UNKNOWN_NAME_COLOR)
	end

	return addon:GetClassColoredName(name, classFilename)
end

local function GetBarStateDisplayName(state, nameKey, classKey, guidKey)
	local name = state[nameKey]
	local guid = state[guidKey]

	if state.source == "runtime" and guid then
		name = addon:GetUnitNameFromGUID(guid, db.useFullNameForBars)
	end

	return GetBarDisplayName(name, state[classKey])
end

local function ClearWaitingTargets()
	for targetGUID in next, waitingToAccept do
		waitingToAccept[targetGUID] = nil
	end
end

local function ClearWaitingTransitions(source)
	for key, transition in next, pendingWaitingTransitions do
		if not source or transition.source == source then
			pendingWaitingTransitions[key] = nil
		end
	end
end

local previewSingleResIconClasses = {
	"PRIEST",
	"SHAMAN",
	"PALADIN",
	"DRUID",
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
	local firstClassFilename
	local count = #previewSingleResIconClasses
	local startIndex = math_random(count)

	for offset = 0, count - 1 do
		local index = ((startIndex + offset - 2) % count) + 1
		local classFilename = previewSingleResIconClasses[index]
		local icon = GetPreviewSingleResIconForClass(classFilename)

		if icon then
			firstIcon = firstIcon or icon
			firstClassFilename = firstClassFilename or classFilename

			if icon ~= avoidIcon then
				return icon, classFilename
			end
		end
	end

	return firstIcon, firstClassFilename
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
	local targetName = GetBarStateDisplayName(state, "targetName", "targetClass", "targetGUID")

	if state.isWaiting then
		if db.behavior.useShortLabels then
			return string_format(L["%s : %s"], targetName, QUEUED_STATUS_WAITING)
		end

		return string_format(L["%s is waiting to accept"], targetName)
	end

	local casterName = GetBarStateDisplayName(state, "casterName", "casterClass", "casterGUID")

	if db.behavior.useShortLabels then
		return string_format(L["%s : %s"], casterName, targetName)
	end

	return string_format(L["%s is resurrecting %s"], casterName, targetName)
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
-- Resurrection state builders
-- --------------------------------------------------------------------

-- Keep callback data translation separate from rendering and layout.

local function GetCasterName(casterGUID)
	return addon:GetUnitNameFromGUID(casterGUID, db.useFullNameForBars)
end

local function GetTargetName(targetGUID)
	-- Show Blizzard's localized UNKNOWN string until the target resolves.
	return addon:GetUnitNameFromGUID(targetGUID, db.useFullNameForBars)
end

local function GetUnitClassByGUID(unitGUID)
	if not unitGUID or unitGUID == "UNKNOWN" then
		return nil
	end

	if addon.PLAYER_GUID == unitGUID then
		return UnitClassBase("player")
	end

	local numGroupMembers = GetNumGroupMembers()

	if IsInRaid() then
		for index = 1, numGroupMembers do
			local unit = "raid" .. index

			if UnitGUID(unit) == unitGUID then
				return UnitClassBase(unit)
			end
		end
	else
		for index = 1, numGroupMembers - 1 do
			local unit = "party" .. index

			if UnitGUID(unit) == unitGUID then
				return UnitClassBase(unit)
			end
		end
	end
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
		casterClass = GetUnitClassByGUID(casterGUID),
		targetGUID = targetGUID,
		targetName = GetTargetName(targetGUID),
		targetClass = GetUnitClassByGUID(targetGUID),
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
		casterClass = GetUnitClassByGUID(casterGUID),
		targetGUID = nil,
		targetName = L["Multiple Targets"],
		targetClass = nil,
		startTime = endTime - duration,
		duration = duration,
		endTime = endTime,
		isCollision = false,
		isMass = true,
		isWaiting = false,
		icon = casterInfo.textureID,
	}
end

local function BuildWaitingState(targetGUID, targetName, duration)
	local now = GetTime()

	duration = duration or PENDING_TIMEOUT_SECONDS

	return {
		key = targetGUID,
		source = "runtime",
		kind = "waiting",
		casterGUID = nil,
		casterName = nil,
		casterClass = nil,
		targetGUID = targetGUID,
		targetName = targetName,
		targetClass = GetUnitClassByGUID(targetGUID),
		startTime = now,
		duration = duration,
		endTime = now + duration,
		isCollision = false,
		isMass = false,
		isWaiting = true,
		icon = nil,
	}
end

-- --------------------------------------------------------------------
-- Container frame
-- --------------------------------------------------------------------

local function SaveContainerPosition(frame)
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	if not point then
		return
	end

	local frameSettings = db.frame
	local scale = frame:GetScale() or 1

	-- GetPoint returns offsets in the frame's own scale. Store them in
	-- UIParent's scale so changing the frame scale does not move its anchor.
	x = (x or 0) * scale
	y = (y or 0) * scale

	if frameSettings.pixelSnap then
		x = SnapPixelValue(x)
		y = SnapPixelValue(y)
	end

	frameSettings.point = point
	frameSettings.relativePoint = relativePoint or point
	frameSettings.x = x
	frameSettings.y = y

	-- StartMoving replaces the original anchor with the nearest screen anchor.
	-- Normalize that anchor against UIParent while converting the stored
	-- UIParent-scale offsets back to the frame's local scale.
	frame:ClearAllPoints()
	frame:SetPoint(point, UIParent, frameSettings.relativePoint, x / scale, y / scale)
end

-- The container is an ordinary frame so its visibility remains safe in combat.
local function CreateContainerFrame()
	if containerFrame then
		return containerFrame
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", nil, UIParent, template)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(100)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if db and not db.frame.locked then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SaveContainerPosition(self)
		AceConfigRegistry:NotifyChange("SmartRes2")
	end)
	frame:EnableMouse(false)

	-- Keep the fill/background texture separate from the backdrop border.
	-- SetBackdrop handles borders well, but a regular texture makes background
	-- media and color changes immediate and predictable across clients.
	containerBackground = frame:CreateTexture(nil, "BACKGROUND")

	containerFrame = frame

	return frame
end

local function HideContainer()
	if containerFrame then
		containerFrame:Hide()
	end
end

-- The background uses a normal texture so media/color changes are predictable
-- across clients. The backdrop is reserved for the border, where Blizzard's
-- BackdropTemplate API is still the right fit.
local function ApplyContainerBackdrop()
	if not db or not containerFrame then
		return
	end

	local backdropSettings = db.frame.backdrop
	local backgroundColor = backdropSettings.backgroundColor
	local borderColor = backdropSettings.borderColor
	local insets = backdropSettings.insets
	local backgroundTexture = containerBackground

	if backgroundTexture then
		local background = addon.LSM:Fetch(
			addon.LSM.MediaType.BACKGROUND,
			backdropSettings.background,
			true
		)

		backgroundTexture:ClearAllPoints()
		backgroundTexture:SetPoint("TOPLEFT", containerFrame, "TOPLEFT", insets.left, -insets.top)
		backgroundTexture:SetPoint("BOTTOMRIGHT", containerFrame, "BOTTOMRIGHT", -insets.right, insets.bottom)

		if background then
			backgroundTexture:SetTexture(background)
			backgroundTexture:SetVertexColor(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a)
			backgroundTexture:Show()
		else
			backgroundTexture:Hide()
		end
	end

	if not containerFrame.SetBackdrop then
		return
	end

	local border = addon.LSM:Fetch(
		addon.LSM.MediaType.BORDER,
		backdropSettings.border,
		true
	)

	containerFrame:SetBackdrop({
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
		containerFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
	end
end

local function ApplyContainerFrameSettings()
	if not db then return end

	local frameSettings = db.frame
	local frame = CreateContainerFrame()

	local width = frameSettings.width
	local height = frameSettings.height
	local scale = frameSettings.scale or 1
	local x = frameSettings.x
	local y = frameSettings.y

	frame:SetScale(scale)

	if frameSettings.pixelSnap then
		width = SnapPixelValue(width)
		height = SnapPixelValue(height)
		x = SnapPixelValue(x)
		y = SnapPixelValue(y)
	end

	-- Position offsets are stored in UIParent's scale. SetPoint applies offsets
	-- in the frame's local scale, so divide by the frame scale to keep the chosen
	-- anchor and visual offsets fixed while scaling.
	frame:ClearAllPoints()
	frame:SetPoint(
		frameSettings.point,
		UIParent,
		frameSettings.relativePoint or frameSettings.point,
		x / scale,
		y / scale
	)
	frame:SetSize(width, height)
	frame:SetClampedToScreen(frameSettings.clampToScreen)
	frame:SetMovable(not frameSettings.locked)
	frame:EnableMouse(not frameSettings.locked)

	ApplyContainerBackdrop()
end

-- --------------------------------------------------------------------
-- Masque icon skinning
-- --------------------------------------------------------------------

local function GetMasqueGroup()
	if not addon.MasqueBarsGroup or not addon.db.profile.useMasque then
		return nil
	end

	return addon.MasqueBarsGroup
end

local function HideCandyBarIconTexture(bar)
	local iconTexture = bar.candyBarIconFrame

	if iconTexture then
		iconTexture:Hide()
	end
end

local function GetOrCreateMasqueButton(key, parent)
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

local function RemoveMasqueButton(key)
	local button = masqueButtons[key]

	if not button then
		return
	end

	if addon.MasqueBarsGroup then
		addon.MasqueBarsGroup:RemoveButton(button)
	end

	masqueRegions[key] = nil
	masqueButtons[key] = nil

	button:Hide()
	button:SetParent(nil)
end

local function ApplyMasqueIcon(state, bar)
	local key = state.key
	local group = GetMasqueGroup()
	local button = masqueButtons[key]
	local iconPosition = GetProfileDB().behavior.iconPosition

	if not group or not state.icon or iconPosition == "NONE" then
		if button then
			RemoveMasqueButton(key)
		end

		-- LibCandyBar still owns the icon slot when Masque is disabled.
		if state.icon and iconPosition ~= "NONE" and bar.candyBarIconFrame then
			bar.candyBarIconFrame:Show()
		end

		return
	end

	button = GetOrCreateMasqueButton(key, bar)
	button:ClearAllPoints()
	button:SetSize(GetBarHeight(), GetBarHeight())

	if iconPosition == "RIGHT" then
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

	-- AddButton applies the active skin. The explicit square size above gives
	-- Masque stable geometry instead of deriving it from LibCandyBar's texture.
	group:AddButton(button, regions, "Item", true)
	HideCandyBarIconTexture(bar)
end

local function ClearMasqueButtons()
	for key in next, masqueButtons do
		RemoveMasqueButton(key)
	end
end

-- --------------------------------------------------------------------
-- Individual bar border frames
-- --------------------------------------------------------------------

local function GetOrCreateBarBorderFrame(key)
	local frame = barBorderFrames[key]

	if frame then
		return frame
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", nil, CreateContainerFrame(), template)
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(109)
	frame:EnableMouse(false)

	barBorderFrames[key] = frame

	return frame
end

local function ApplyBarBorderSettings(frame)
	local profile = GetProfileDB()
	local borderThickness = GetBarBorderThickness()

	frame:SetParent(CreateContainerFrame())
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

-- Preview and runtime records share this rendering and layout pipeline.

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

local function GetOrCreateCandyBar(key)
	local bar = candyBars[key]

	if bar then
		return bar
	end

	bar = module.LibCandyBar:New(GetStatusBarTexture(), GetBarWidth(), GetBarHeight())
	bar:Set("SmartRes2Key", key)
	bar:SetParent(GetOrCreateBarBorderFrame(key))
	bar:SetFrameStrata("MEDIUM")
	bar:SetFrameLevel(110)
	bar:EnableMouse(false)

	candyBars[key] = bar

	return bar
end

local function ApplyCandyBarSettings(state, bar)
	local profile = GetProfileDB()
	local color = GetBarColor(state)
	local icon = state.icon

	local borderFrame = GetOrCreateBarBorderFrame(state.key)
	local borderThickness = GetBarBorderThickness()

	ApplyBarBorderSettings(borderFrame)

	bar:SetParent(borderFrame)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", borderFrame, "TOPLEFT", borderThickness, -borderThickness)
	bar:SetSize(GetBarWidth(), GetBarHeight())
	bar:SetTexture(GetStatusBarTexture())
	bar:SetFill(profile.behavior.fill)
	bar.candyBarBar:SetReverseFill(profile.behavior.mirrorBars)
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

	local iconPosition = profile.behavior.iconPosition

	if not icon or iconPosition == "NONE" then
		if bar:GetIcon() then
			bar:SetIcon(nil)
		end
	else
		if (bar:GetIconPosition() or "LEFT") ~= iconPosition then
			bar:SetIconPosition(iconPosition)
		end

		if bar:GetIcon() ~= icon then
			bar:SetIcon(icon)
		end
	end
end

local function RefreshCandyBar(state)
	local bar = candyBars[state.key]

	if not bar then
		return
	end

	ApplyCandyBarSettings(state, bar)
	ApplyMasqueIcon(state, bar)
end

local function RefreshCandyBars()
	for _, state in next, barStates do
		RefreshCandyBar(state)
	end
end

local function BuildSortedBars()
	for index in next, sortedBars do
		sortedBars[index] = nil
	end

	for _, state in next, barStates do
		sortedBars[#sortedBars + 1] = state
	end

	table_sort(sortedBars, CompareBarStates)
end

local function LayoutCandyBars()
	if not db or not containerFrame then
		return
	end

	local profile = GetProfileDB()

	BuildSortedBars()

	local previousBar
	local maxBars = math_min(profile.behavior.maxBars, GetMaxVisibleBars())
	local growUp = profile.frame.growDirection == "UP"
	local horizontalPoint = profile.behavior.mirrorBars and "RIGHT" or "LEFT"
	local topPoint = "TOP" .. horizontalPoint
	local bottomPoint = "BOTTOM" .. horizontalPoint
	local offsetX = GetBarOffsetX()
	local firstBarOffsetY = GetFirstBarOffsetY()

	for index, state in next, sortedBars do
		local bar = candyBars[state.key]
		local borderFrame = barBorderFrames[state.key]

		if bar and borderFrame then
			borderFrame:ClearAllPoints()

			if index <= maxBars then
				if not previousBar then
					if growUp then
						borderFrame:SetPoint(bottomPoint, containerFrame, bottomPoint, offsetX, firstBarOffsetY)
					else
						borderFrame:SetPoint(topPoint, containerFrame, topPoint, offsetX, firstBarOffsetY)
					end
				elseif growUp then
					borderFrame:SetPoint(bottomPoint, previousBar, topPoint, 0, GetBarSpacing())
				else
					borderFrame:SetPoint(topPoint, previousBar, bottomPoint, 0, -GetBarSpacing())
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

local function HasVisibleBars()
	return next(barStates) ~= nil
end

local function RefreshContainerVisibility()
	local frame = CreateContainerFrame()

	if not db then
		frame:Hide()
		return
	end

	if db.frame.hideWhenEmpty and not HasVisibleBars() then
		frame:Hide()
	else
		frame:Show()
	end
end

local function AddOrUpdateBar(state)
	if not db then
		return
	end

	local now = GetTime()

	state.startTime = state.startTime or now
	state.duration = state.duration or 1
	state.endTime = state.endTime or (state.startTime + state.duration)
	barStates[state.key] = state

	local bar = GetOrCreateCandyBar(state.key)
	ApplyCandyBarSettings(state, bar)
	bar:SetDuration(state.duration)
	bar:Start()

	-- LibCandyBar finalizes and shows its icon texture in Start(). Apply Masque
	-- afterward so the original texture can be hidden without using that texture
	-- as the Masque button's geometry.
	ApplyMasqueIcon(state, bar)

	RefreshContainerVisibility()
	LayoutCandyBars()
end

local function ScheduleWaitingBar(state)
	local key = state.key

	-- A newer completed resurrection offer replaces any pending transition and
	-- restarts an existing target waiting bar from the refreshed expiration time.
	local transition = {
		source = state.source,
	}

	pendingWaitingTransitions[key] = transition

	local function ShowWaitingBar()
		if pendingWaitingTransitions[key] ~= transition then
			return
		end

		pendingWaitingTransitions[key] = nil

		if state.source == "runtime" and not waitingToAccept[state.targetGUID] then
			return
		end

		local now = GetTime()
		local remainingDuration = state.endTime - now

		-- The visual transition delay is part of the target's refreshed waiting
		-- lifecycle; it must never extend the resurrection offer timer.
		if remainingDuration <= 0 then
			if state.source == "runtime" and state.targetGUID then
				waitingToAccept[state.targetGUID] = nil
			end

			return
		end

		state.startTime = now
		state.duration = remainingDuration
		AddOrUpdateBar(state)
	end

	local transitionDuration = math_max(0, db.behavior.transitionDuration or 0)

	if transitionDuration == 0 then
		ShowWaitingBar()
	else
		After(transitionDuration, ShowWaitingBar)
	end
end

local function StopBar(key)
	local state = barStates[key]
	local bar = candyBars[key]
	local borderFrame = barBorderFrames[key]

	pendingWaitingTransitions[key] = nil

	if state and state.isWaiting and state.targetGUID then
		waitingToAccept[state.targetGUID] = nil
	end

	barStates[key] = nil
	candyBars[key] = nil
	barBorderFrames[key] = nil

	if bar then
		bar:Stop("SmartRes2_StopBar")
	end

	RemoveMasqueButton(key)

	if borderFrame then
		borderFrame:Hide()
		borderFrame:SetParent(nil)
	end
end

local function ClearBars(source)
	local keys = {}

	ClearWaitingTransitions(source)

	for key, state in next, barStates do
		if not source or state.source == source then
			keys[#keys + 1] = key
		end
	end

	for index = 1, #keys do
		StopBar(keys[index])
	end

	RefreshContainerVisibility()
	LayoutCandyBars()
end

local function RefreshContainerFrame()
	ApplyContainerFrameSettings()
	RefreshCandyBars()
	LayoutCandyBars()
	RefreshContainerVisibility()
end

-- --------------------------------------------------------------------
-- Module lifecycle
-- --------------------------------------------------------------------

-- Initialize the Bars profile namespace and register its options table.
function module:OnInitialize()
	RegisterMedia()

	self.db = addon.db:RegisterNamespace(self:GetName(), defaults)

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	db = self.db.profile
	---@cast db -nil

	self:SetEnabledState(db.enabled)

	addon:RegisterModuleOptions(self:GetName(), self:GetOptions())
end

-- Enable rendering and resurrection-state callbacks.
function module:OnEnable()
	RefreshContainerFrame()

	module.LibCandyBar.RegisterCallback(self, "LibCandyBar_Stop", "OnCandyBarStopped")

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

-- Release rendered state and callback registrations owned by Bars.
function module:OnDisable()
	ClearBars()

	module.LibCandyBar.UnregisterCallback(self, "LibCandyBar_Stop")
	self:UnregisterAllResInfoCallbacks()

	ClearMasqueButtons()
	ClearWaitingTargets()
	HideContainer()
end

-- Rebind the active profile and reapply its visual settings.
function module:RefreshConfig()
	db = self.db.profile

	if self:IsEnabled() then
		RefreshContainerFrame()
	end
end

function module:SetFrameLocked(locked)
	db.frame.locked = locked == true

	if self:IsEnabled() then
		ApplyContainerFrameSettings()
	end

	return db.frame.locked
end

function module:ToggleFrameLock()
	return self:SetFrameLocked(not db.frame.locked)
end

-- --------------------------------------------------------------------
-- Preview bars
-- --------------------------------------------------------------------

local function HasTestBars()
	for _, state in next, barStates do
		if state.source == "preview" then
			return true
		end
	end

	return false
end

function module:ClearTestBars()
	ClearBars("preview")
end

function module:ToggleTestBars()
	if not self:IsEnabled() then
		return
	end

	if HasTestBars() then
		self:ClearTestBars()
	else
		self:ShowTestBars()
	end
end

function module:ShowTestBars()
	self:ClearTestBars()

	local now = GetTime()
	local alyndraIcon, alyndraClass = GetPreviewSingleResIcon()
	local caliaIcon, caliaClass = GetPreviewSingleResIcon(alyndraIcon)
	local maerinIcon = GetPreviewMassResIcon()
	AddOrUpdateBar({
		key = "SmartRes2_Preview_GoodSingle",
		source = "preview",
		kind = "single",
		casterGUID = "SmartRes2-Preview-Alyndra",
		casterName = "Alyndra",
		casterClass = alyndraClass,
		targetGUID = "SmartRes2-Preview-Brennor",
		targetName = "Brennor",
		targetClass = "WARRIOR",
		startTime = now,
		duration = 7,
		endTime = now + 7,
		isCollision = false,
		isMass = false,
		isWaiting = false,
		icon = alyndraIcon,
		transitionToWaiting = true,
		waitingKey = "SmartRes2_Preview_BrennorWaiting",
	})

	AddOrUpdateBar({
		key = "SmartRes2_Preview_CollisionSingle",
		source = "preview",
		kind = "single",
		casterGUID = "SmartRes2-Preview-Calia",
		casterName = "Calia",
		casterClass = caliaClass,
		targetGUID = "SmartRes2-Preview-Brennor",
		targetName = "Brennor",
		targetClass = "WARRIOR",
		startTime = now,
		duration = 10,
		endTime = now + 10,
		isCollision = true,
		isMass = false,
		isWaiting = false,
		icon = caliaIcon,
		transitionToWaiting = true,
		waitingKey = "SmartRes2_Preview_BrennorWaiting",
	})

	AddOrUpdateBar({
		key = "SmartRes2_Preview_GoodMass",
		source = "preview",
		kind = "mass",
		casterGUID = "SmartRes2-Preview-Maerin",
		casterName = "Maerin",
		casterClass = "PRIEST",
		targetGUID = nil,
		targetName = L["Multiple Targets"],
		targetClass = nil,
		startTime = now,
		duration = 10,
		endTime = now + 10,
		isCollision = false,
		isMass = true,
		isWaiting = false,
		icon = maerinIcon,
	})

	AddOrUpdateBar({
		key = "SmartRes2_Preview_Waiting",
		source = "preview",
		kind = "waiting",
		casterGUID = nil,
		casterName = nil,
		casterClass = nil,
		targetGUID = "SmartRes2-Preview-Tovin",
		targetName = "Tovin",
		targetClass = "MAGE",
		startTime = now,
		duration = PENDING_TIMEOUT_SECONDS,
		endTime = now + PENDING_TIMEOUT_SECONDS,
		isCollision = false,
		isMass = false,
		isWaiting = true,
		icon = nil,
	})
end

-- --------------------------------------------------------------------
-- CandyBar callback handling
-- --------------------------------------------------------------------

function module:OnCandyBarStopped(callback, bar, reason)
	local key = bar:Get("SmartRes2Key")

	local state

	if key then
		local borderFrame = barBorderFrames[key]

		state = barStates[key]

		if state and state.isWaiting and state.targetGUID and not pendingWaitingTransitions[key] then
			waitingToAccept[state.targetGUID] = nil
		end

		barStates[key] = nil
		candyBars[key] = nil
		barBorderFrames[key] = nil

		RemoveMasqueButton(key)

		if borderFrame then
			borderFrame:Hide()
			borderFrame:SetParent(nil)
		end
	end

	if state and state.transitionToWaiting and reason ~= "SmartRes2_StopBar" then
		local waitingKey = state.waitingKey or (state.key .. "_Waiting")
		local now = GetTime()

		ScheduleWaitingBar({
			key = waitingKey,
			source = state.source,
			kind = "waiting",
			casterGUID = nil,
			casterName = nil,
			casterClass = nil,
			targetGUID = state.targetGUID,
			targetName = state.targetName,
			targetClass = state.targetClass,
			startTime = now,
			duration = PENDING_TIMEOUT_SECONDS,
			endTime = now + PENDING_TIMEOUT_SECONDS,
			isCollision = false,
			isMass = false,
			isWaiting = true,
			icon = nil,
		})

		RefreshContainerVisibility()
		LayoutCandyBars()
		return
	end

	RefreshContainerVisibility()
	LayoutCandyBars()
end

function module:SetBarCollision(key, isCollision)
	local state = barStates[key]

	if not state then
		return
	end

	state.isCollision = isCollision
	RefreshCandyBar(state)
end

local function RefreshTargetCollisionStates(targetGUID, targetInfo)
	if not targetGUID or targetGUID == "UNKNOWN" or not targetInfo then
		return
	end

	for _, state in next, barStates do
		if state.source == "runtime" and not state.isWaiting and not state.isMass and state.targetGUID == targetGUID then
			state.isCollision = targetInfo.fastestCasterGUID ~= nil
				and (targetInfo.fastestCasterGUID ~= state.casterGUID or targetInfo.fastestResType ~= "SINGLE")
			RefreshCandyBar(state)
		end
	end
end

-- --------------------------------------------------------------------
-- Resurrection callback handlers
-- --------------------------------------------------------------------

-- Callback handlers translate state and delegate rendering to the common pipeline.

function module:OnSingleResCastStarted(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	AddOrUpdateBar(BuildSingleCastState(casterGUID, targetGUID, casterInfo, targetInfo))
end

function module:OnSingleResCastStopped(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	StopBar(casterGUID)
	RefreshTargetCollisionStates(targetGUID, targetInfo)
end

function module:OnSingleResCastFinished(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	StopBar(casterGUID)

	if targetGUID == "UNKNOWN" then
		return
	end

	local hasResWaiting, remainingTime = self:UnitHasResWaiting(targetGUID)
	if not hasResWaiting or not remainingTime then
		return
	end

	waitingToAccept[targetGUID] = true
	ScheduleWaitingBar(BuildWaitingState(targetGUID, GetTargetName(targetGUID), remainingTime))
end

function module:OnMassResCastStarted(callback, casterGUID, casterInfo)
	AddOrUpdateBar(BuildMassCastState(casterGUID, casterInfo))
end

function module:OnMassResCastStopped(callback, casterGUID, casterInfo)
	StopBar(casterGUID)
end

function module:OnMassResCastFinished(callback, casterGUID, casterInfo)
	StopBar(casterGUID)
end

function module:OnFastestResChanged(callback, targetGUID, targetInfo)
	RefreshTargetCollisionStates(targetGUID, targetInfo)
end

function module:OnResTargetGUIDResolved(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	-- Replace the temporary UNKNOWN target with the resolved target name/GUID,
	-- then recalculate collision color for all active single-target bars aimed
	-- at that target.
	local state = barStates[casterGUID]

	if state and state.source == "runtime" and not state.isMass and not state.isWaiting then
		state.targetGUID = targetGUID
		state.targetName = GetTargetName(targetGUID)
		state.targetClass = GetUnitClassByGUID(targetGUID)
		state.endTime = casterInfo.endTime
		state.duration = casterInfo.castTime
		state.startTime = casterInfo.endTime - casterInfo.castTime
		state.icon = casterInfo.textureID
		state.isCollision = targetInfo.fastestCasterGUID ~= nil
			and (targetInfo.fastestCasterGUID ~= casterGUID or targetInfo.fastestResType ~= "SINGLE")
		RefreshCandyBar(state)
	end

	RefreshTargetCollisionStates(targetGUID, targetInfo)
end

function module:OnResTargetGUIDIsAlive(callback, targetGUID)
	if waitingToAccept[targetGUID] then
		waitingToAccept[targetGUID] = nil
		StopBar(targetGUID)
	end
end
-- --------------------------------------------------------------------
-- Public accessors
-- --------------------------------------------------------------------

function module:GetProfile()
	return db
end

function module:GetPendingTimeout()
	return PENDING_TIMEOUT_SECONDS
end