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
-- Current boundary:
-- - This file creates the visible container frame.
-- - This file creates permanent preview/test bars for user styling.
-- - It does not consume LibResInfo callbacks yet.
--
-- Future responsibilities:
-- - Track active cast bars keyed by casterGUID.
-- - Track waiting-to-accept bars keyed by targetGUID.
-- - Keep hidden bars tracked when maxBars hides them.
-- - Apply individual user settings and future Themes presets.
--
-- LibResInfo-2.0 owns resurrection state. Bars only displays that state.
-- Themes will eventually copy preset batches into Bars settings, but Bars
-- remains the module that applies those settings to frames and bars.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local BackdropTemplateMixin = BackdropTemplateMixin
local CreateFrame = CreateFrame
local GetTime = GetTime
local QUEUED_STATUS_WAITING = QUEUED_STATUS_WAITING
local LibStub = LibStub
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_random = math.random
local next = next
local string_format = string.format
local table_concat = table.concat
local table_sort = table.sort
local UIParent = UIParent

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

---@class SmartRes2: AceAddon
---@field db SmartRes2DB
---@field LSM any
---@field Masque any|nil
---@field IsMasqueAvailable fun(self: SmartRes2): boolean
---@field GetMassResurrectionIcon fun(self: SmartRes2): number|string|nil
---@field GetResurrectionIconForClass fun(self: SmartRes2, classFilename: string|nil, useDefault?: boolean): number|string|nil
---@field RegisterModuleOptions fun(self: SmartRes2, optionsName: string, moduleOptions: table)
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

-- This frame is both a normal Frame and a BackdropTemplate frame. Plain frames
-- do not always expose SetBackdrop methods, so the container is explicitly
-- created with "BackdropTemplate" and annotated as such for WoWLua-LS.
---@alias SmartRes2_BackdropFrame Frame & BackdropTemplate

---@class SmartRes2_BarBorderFrame: Frame, BackdropTemplate

---@class SmartRes2_MasqueButton: Button
---@field Icon Texture
---@field Normal Texture

---@class SmartRes2_CandyBar: Frame
---@field icon Texture|nil
---@field Icon Texture|nil
---@field candyBarIcon Texture|nil
---@field Set fun(self: SmartRes2_CandyBar, key: string, data: any)
---@field Get fun(self: SmartRes2_CandyBar, key: string): any
---@field SetBackgroundColor fun(self: SmartRes2_CandyBar, r: number, g: number, b: number, a: number)
---@field SetColor fun(self: SmartRes2_CandyBar, r: number, g: number, b: number, a: number)
---@field SetDuration fun(self: SmartRes2_CandyBar, duration: number, isApproximate?: boolean)
---@field SetFill fun(self: SmartRes2_CandyBar, fill: boolean)
---@field SetFont fun(self: SmartRes2_CandyBar, fontFile: string, height: number, flags: string)
---@field SetIcon fun(self: SmartRes2_CandyBar, icon: string|number|nil, ...)
---@field SetIconPosition fun(self: SmartRes2_CandyBar, position: "LEFT"|"RIGHT")
---@field SetLabel fun(self: SmartRes2_CandyBar, text: string|nil)
---@field SetLabelVisibility fun(self: SmartRes2_CandyBar, bool: boolean)
---@field SetSize fun(self: SmartRes2_CandyBar, width: number, height: number)
---@field SetShadowColor fun(self: SmartRes2_CandyBar, r: number, g: number, b: number, a: number)
---@field SetShadowOffset fun(self: SmartRes2_CandyBar, offsetX: number, offsetY: number)
---@field SetTextColor fun(self: SmartRes2_CandyBar, r: number, g: number, b: number, a: number)
---@field SetTexture fun(self: SmartRes2_CandyBar, texture: string)
---@field SetTimeVisibility fun(self: SmartRes2_CandyBar, bool: boolean)
---@field Start fun(self: SmartRes2_CandyBar, maxValue?: number)
---@field Stop fun(self: SmartRes2_CandyBar, ...)

---@class SmartRes2_BarsColorDB
---@field r number
---@field g number
---@field b number
---@field a number

---@class SmartRes2_BarsInsetDB
---@field left number
---@field right number
---@field top number
---@field bottom number

---@class SmartRes2_BarsBackdropDB
---@field background string LibSharedMedia background key.
---@field border string LibSharedMedia border key.
---@field edgeSize number
---@field insets SmartRes2_BarsInsetDB
---@field backgroundColor SmartRes2_BarsColorDB
---@field borderColor SmartRes2_BarsColorDB

---@class SmartRes2_BarsFrameDB
---@field width number
---@field height number
---@field scale number
---@field point string
---@field x number
---@field y number
---@field clampToScreen boolean
---@field locked boolean
---@field hideWhenEmpty boolean
---@field pixelSnap boolean
---@field growDirection "DOWN"|"UP"
---@field backdrop SmartRes2_BarsBackdropDB

---@class SmartRes2_BarsMediaDB
---@field font string LibSharedMedia font key.
---@field fontSize number
---@field fontOutline "NONE"|"OUTLINE"|"THICKOUTLINE"
---@field fontSlug boolean
---@field fontMonochrome boolean
---@field statusBar string LibSharedMedia statusbar key.
---@field barBorder string LibSharedMedia border key.
---@field barBorderThickness number

---@class SmartRes2_BarsTextDB
---@field color SmartRes2_BarsColorDB
---@field shadow boolean
---@field shadowColor SmartRes2_BarsColorDB
---@field shadowOffsetX number
---@field shadowOffsetY number

---@class SmartRes2_BarsBehaviorDB
---@field maxBars number
---@field transitionDuration number
---@field fill boolean
---@field showTime boolean
---@field showLabel boolean
---@field iconPosition "LEFT"|"RIGHT"|"NONE"
---@field useShortLabels boolean
---@field barSpacing number

---@class SmartRes2_BarsColorsDB
---@field good SmartRes2_BarsColorDB
---@field goodMass SmartRes2_BarsColorDB
---@field collision SmartRes2_BarsColorDB
---@field waiting SmartRes2_BarsColorDB

---@class SmartRes2_BarsProfileDB
---@field enabled boolean
---@field frame SmartRes2_BarsFrameDB
---@field media SmartRes2_BarsMediaDB
---@field text SmartRes2_BarsTextDB
---@field behavior SmartRes2_BarsBehaviorDB
---@field colors SmartRes2_BarsColorsDB
---@field activeTheme string

---@class SmartRes2_BarsDB: AceDBObject-3.0
---@field profile SmartRes2_BarsProfileDB

---@class SmartRes2_BarState
---@field key string
---@field source "preview"|"runtime"
---@field kind "single"|"mass"|"waiting"
---@field casterGUID string|nil
---@field casterName string|nil
---@field targetGUID string|nil
---@field targetName string
---@field startTime number
---@field endTime number
---@field duration number
---@field isCollision boolean
---@field isMass boolean
---@field isWaiting boolean
---@field icon string|number|nil
---@field transitionToWaiting boolean|nil
---@field waitingKey string|nil

---@class SmartRes2_Bars: AceAddon, AceEvent-3.0, AceConsole-3.0, LibResInfo-2.0
---@field db SmartRes2_BarsDB
---@field containerFrame SmartRes2_BackdropFrame|nil
---@field containerBackground Texture|nil
---@field GetOptions fun(self: SmartRes2_Bars): table
---@field ShowTestBars fun(self: SmartRes2_Bars)
---@field ClearTestBars fun(self: SmartRes2_Bars)
---@field HasTestBars fun(self: SmartRes2_Bars): boolean
local module = addon:NewModule("Bars")

-- --------------------------------------------------------------------
-- Libraries
-- --------------------------------------------------------------------

---@class SmartRes2_LibCandyBar
---@field New fun(self: SmartRes2_LibCandyBar, texture: string, width: number, height: number): SmartRes2_CandyBar
---@field RegisterCallback fun(target: table, eventname: string, method: string, arg?: any)
---@field UnregisterCallback fun(target: table, eventname: string)

---@class SmartRes2_MasqueGroup
---@field AddButton fun(self: SmartRes2_MasqueGroup, button: table, regions?: table, buttonType?: string, strict?: boolean)
---@field RemoveButton fun(self: SmartRes2_MasqueGroup, button: table, skipRestore?: boolean)
---@field ReSkin fun(self: SmartRes2_MasqueGroup)

local LibCandyBar = LibStub("LibCandyBar-3.0") --[[@as SmartRes2_LibCandyBar]]
local LibSharedMedia = addon.LSM
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

-- The resurrection accept popup times out after 60 seconds. This is a game
-- mechanic, not user preference, so Bars treats waiting bars as expired after
-- this hard cap unless LibResInfo reports the target accepted/returned alive
-- first.
local PENDING_TIMEOUT_SECONDS = 60

local BAR_HEIGHT = 20
local BAR_SPACING = 4
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
			fontOutline = "NONE",
			fontSlug = false,
			fontMonochrome = false,
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

		-- Bar state colors. These are intentionally distinct for quick scanning
		-- and to remain usable for players with red/green color blindness.
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

---@type SmartRes2_BarsProfileDB|nil
local db

---@type table<string, SmartRes2_BarState>
local barStates = {}

---@type table<string, SmartRes2_CandyBar>
local candyBars = {}

---@type table<string, SmartRes2_BarBorderFrame>
local barBorderFrames = {}

---@type table<string, SmartRes2_MasqueButton>
local masqueButtons = {}

---@type table<string, table>
local masqueRegions = {}

---@type SmartRes2_MasqueGroup|nil
local masqueGroup

---@type SmartRes2_BarState[]
local sortedBars = {}

-- --------------------------------------------------------------------
-- Pixel snapping
-- --------------------------------------------------------------------

-- Rounds a frame-local value to the nearest whole pixel. SmartRes2 uses this
-- only for its own Bars frame; it never changes the player's global UI scale.
---@param value number
---@return number value
local function SnapPixelValue(value)
	return math_floor(value + 0.5)
end

---@return SmartRes2_BarsProfileDB profile
local function GetProfileDB()
	return db --[[@as SmartRes2_BarsProfileDB]]
end

---@return number width
local function GetBarFrameWidth()
	local profile = GetProfileDB()
	local insets = profile.frame.backdrop.insets

	return math_max(1, profile.frame.width - insets.left - insets.right)
end

---@return number thickness
local function GetBarBorderThickness()
	local profile = GetProfileDB()
	local border = profile.media.barBorder

	if not border or border == "None" then
		return 0
	end

	return math_max(0, profile.media.barBorderThickness)
end

---@return number width
local function GetBarWidth()
	local borderThickness = GetBarBorderThickness()

	return math_max(1, GetBarFrameWidth() - (borderThickness * 2))
end

---@return number height
local function GetBarFrameHeight()
	return BAR_HEIGHT + (GetBarBorderThickness() * 2)
end

---@return number spacing
local function GetBarSpacing()
	local profile = GetProfileDB()

	return profile.behavior.barSpacing + GetBarBorderThickness()
end

---@return number offsetX
local function GetBarOffsetX()
	local profile = GetProfileDB()

	return profile.frame.backdrop.insets.left
end

---@return number offsetY
local function GetFirstBarOffsetY()
	local profile = GetProfileDB()
	local insets = profile.frame.backdrop.insets

	if profile.frame.growDirection == "UP" then
		return insets.bottom
	end

	return -insets.top
end

---@return number maxVisibleBars
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

---@param classFilename string
---@return number|string|nil icon
local function GetPreviewSingleResIconForClass(classFilename)
	return addon:GetResurrectionIconForClass(classFilename, false) or previewSingleResIconFallbacks[classFilename]
end

---@param avoidIcon number|string|nil
---@return number|string|nil icon
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

---@return number|string|nil icon
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

---@param state SmartRes2_BarState
---@return string label
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

---@param state SmartRes2_BarState
---@return SmartRes2_BarsColorDB color
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

---@param a SmartRes2_BarState
---@param b SmartRes2_BarState
---@return boolean before
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
-- Container frame
-- --------------------------------------------------------------------

-- Creates the visual parent frame for future CandyBars.
--
-- The container intentionally remains an ordinary, non-secure frame parented
-- to UIParent. Future bar rendering must not anchor it to protected unit
-- frames, which keeps hide/show behavior safe during combat.
---@return SmartRes2_BackdropFrame frame
function module:CreateContainerFrame()
	if self.containerFrame then
		return self.containerFrame
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local frame = CreateFrame("Frame", nil, UIParent, template) --[[@as SmartRes2_BackdropFrame]]
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
		local background = LibSharedMedia:Fetch(
			LibSharedMedia.MediaType.BACKGROUND,
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

	local border = LibSharedMedia:Fetch(
		LibSharedMedia.MediaType.BORDER,
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

---@return boolean enabled
local function IsMasqueEnabled()
	return addon.Masque ~= nil and addon.db and addon.db.profile and addon.db.profile.useMasque
end

---@return SmartRes2_MasqueGroup|nil group
function module:GetMasqueGroup()
	local Masque = addon.Masque

	if not Masque or not addon.db or not addon.db.profile.useMasque then
		return nil
	end

	if not masqueGroup then
		masqueGroup = Masque:Group("SmartRes2", "Bars") --[[@as SmartRes2_MasqueGroup]]
	end

	return masqueGroup
end

---@param bar SmartRes2_CandyBar
local function HideCandyBarIconTexture(bar)
	local iconTexture = bar.icon or bar.Icon or bar.candyBarIcon

	if iconTexture then
		iconTexture:Hide()
	end
end

---@param key string
---@param parent Frame
---@return SmartRes2_MasqueButton button
function module:GetOrCreateMasqueButton(key, parent)
	local button = masqueButtons[key]

	if button then
		button:SetParent(parent)
		return button
	end

	button = CreateFrame("Button", nil, parent) --[[@as SmartRes2_MasqueButton]]
	button:EnableMouse(false)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(111)

	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAllPoints(button)

	button.Normal = button:CreateTexture(nil, "BORDER")
	button.Normal:SetAllPoints(button)
	button:SetNormalTexture(button.Normal)

	masqueButtons[key] = button

	return button
end

---@param state SmartRes2_BarState
---@param bar SmartRes2_CandyBar
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
	button:SetSize(BAR_HEIGHT, BAR_HEIGHT)

	if GetProfileDB().behavior.iconPosition == "RIGHT" then
		button:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
	else
		button:SetPoint("LEFT", bar, "LEFT", 0, 0)
	end

	button.Icon:SetTexture(state.icon)
	button.Icon:SetAllPoints(button)
	button.Normal:SetAllPoints(button)
	button:Show()

	local regions = masqueRegions[key]
	if not regions then
		regions = {
			Icon = button.Icon,
			Normal = button.Normal,
		}
		masqueRegions[key] = regions
	else
		regions.Icon = button.Icon
		regions.Normal = button.Normal
	end

	group:AddButton(button, regions, "Item", true)
	group:ReSkin()
end

---@param key string
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

---@param key string
---@return SmartRes2_BarBorderFrame frame
function module:GetOrCreateBarBorderFrame(key)
	local frame = barBorderFrames[key]

	if frame then
		return frame
	end

	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	frame = CreateFrame("Frame", nil, self:CreateContainerFrame(), template) --[[@as SmartRes2_BarBorderFrame]]
	frame:SetFrameStrata("MEDIUM")
	frame:SetFrameLevel(109)
	frame:EnableMouse(false)

	barBorderFrames[key] = frame

	return frame
end

---@param frame SmartRes2_BarBorderFrame
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

	local border = LibSharedMedia:Fetch(LibSharedMedia.MediaType.BORDER, profile.media.barBorder, true)

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
-- CandyBar rendering
-- --------------------------------------------------------------------

---@return string texture
local function GetStatusBarTexture()
	local profile = GetProfileDB()

	return LibSharedMedia:Fetch(LibSharedMedia.MediaType.STATUSBAR, profile.media.statusBar) --[[@as string]]
end

---@return string fontFile
local function GetFontFile()
	local profile = GetProfileDB()

	return LibSharedMedia:Fetch(LibSharedMedia.MediaType.FONT, profile.media.font) --[[@as string]]
end

---@return string flags
local function GetFontFlags()
	local profile = GetProfileDB()
	local media = profile.media
	local flags = {}

	if media.fontSlug then
		flags[#flags + 1] = "SLUG"
	end

	if media.fontMonochrome then
		flags[#flags + 1] = "MONOCHROME"
	end

	if media.fontOutline == "OUTLINE" then
		flags[#flags + 1] = "OUTLINE"
	elseif media.fontOutline == "THICKOUTLINE" then
		flags[#flags + 1] = "THICKOUTLINE"
	end

	return table_concat(flags, ",")
end

---@param key string
---@return SmartRes2_CandyBar bar
function module:GetOrCreateCandyBar(key)
	local bar = candyBars[key]

	if bar then
		return bar
	end

	bar = LibCandyBar:New(GetStatusBarTexture(), GetBarWidth(), BAR_HEIGHT) --[[@as SmartRes2_CandyBar]]
	bar:Set("SmartRes2Key", key)
	bar:SetParent(self:GetOrCreateBarBorderFrame(key))
	bar:SetFrameStrata("MEDIUM")
	bar:SetFrameLevel(110)
	bar:EnableMouse(false)

	candyBars[key] = bar

	return bar
end

---@param state SmartRes2_BarState
---@param bar SmartRes2_CandyBar
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
	bar:SetSize(GetBarWidth(), BAR_HEIGHT)
	bar:SetTexture(GetStatusBarTexture())
	bar:SetFill(profile.behavior.fill)
	bar:SetColor(color.r, color.g, color.b, color.a)
	bar:SetBackgroundColor(BAR_BACKGROUND_R, BAR_BACKGROUND_G, BAR_BACKGROUND_B, BAR_BACKGROUND_A)
	bar:SetTextColor(profile.text.color.r, profile.text.color.g, profile.text.color.b, profile.text.color.a)
	bar:SetFont(GetFontFile(), profile.media.fontSize, GetFontFlags())
	bar:SetLabel(FormatBarLabel(state))
	bar:SetTimeVisibility(profile.behavior.showTime)
	bar:SetLabelVisibility(profile.behavior.showLabel)

	if profile.text.shadow then
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

---@param state SmartRes2_BarState
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
			bar:SetSize(GetBarWidth(), BAR_HEIGHT)

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

---@param state SmartRes2_BarState
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

---@param key string
function module:StopBar(key)
	local bar = candyBars[key]
	local borderFrame = barBorderFrames[key]

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

---@param source "preview"|"runtime"|nil
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
		duration = 9.1,
		endTime = now + 9.1,
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

---@param callback string
---@param bar SmartRes2_CandyBar
---@param reason string|nil
function module:OnCandyBarStopped(callback, bar, reason)
	local key = bar:Get("SmartRes2Key") --[[@as string|nil]]

	---@type SmartRes2_BarState|nil
	local state

	if key then
		local borderFrame = barBorderFrames[key]

		state = barStates[key]
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

---@param key string
---@param isCollision boolean
function module:SetBarCollision(key, isCollision)
	local state = barStates[key]

	if not state then
		return
	end

	state.isCollision = isCollision
	self:RefreshCandyBar(state)
end

---@return boolean hasTestBars
function module:HasTestBars()
	for _, state in next, barStates do
		if state.source == "preview" then
			return true
		end
	end

	return false
end

-- Returns true when there is something meaningful to show inside the container.
---@return boolean hasVisibleBars
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
-- Module lifecycle
-- --------------------------------------------------------------------

function module:OnInitialize()
	self.db = addon.db:RegisterNamespace(self:GetName(), defaults) --[[@as SmartRes2_BarsDB]]

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	db = self.db.profile

	self:SetEnabledState(db.enabled)

	addon:RegisterModuleOptions(self:GetName(), self:GetOptions())
end

function module:OnEnable()
	self:RefreshContainerFrame()

	LibCandyBar.RegisterCallback(self, "LibCandyBar_Stop", "OnCandyBarStopped")

	-- LibResInfo separates single-target and mass resurrection callbacks
	-- because the data and lifecycle differ. Keep callback handlers explicit
	-- for readability, then delegate shared bar creation, sorting, visibility,
	-- and rendering work to common helpers.
	--
	-- Future examples:
	-- self:RegisterCallback("ResCast_Started", "OnResCastStarted")
	-- self:RegisterCallback("ResCast_Stopped", "OnResCastStopped")
	-- self:RegisterCallback("ResCast_Finished", "OnResCastFinished")
	-- self:RegisterCallback("MassResCast_Started", "OnMassResCastStarted")
	-- self:RegisterCallback("MassResCast_Stopped", "OnMassResCastStopped")
	-- self:RegisterCallback("MassResCast_Finished", "OnMassResCastFinished")
	-- self:RegisterCallback("FastestRes_Changed", "OnFastestResChanged")
	-- self:RegisterCallback("ResTargetGUID_Resolved", "OnResTargetGUIDResolved")
	-- self:RegisterCallback("ResTargetGUID_IsAlive", "OnResTargetGUIDIsAlive")
end

function module:OnDisable()
	self:ClearBars()

	LibCandyBar.UnregisterCallback(self, "LibCandyBar_Stop")

	for key in next, masqueButtons do
		self:RemoveMasqueButton(key)
	end

	if self.containerFrame then
		self.containerFrame:Hide()
	end

	-- Bars will unregister LibResInfo callbacks and hide/release bars here once
	-- real resurrection rendering exists.
	--
	-- LibResInfo-2.0 provides UnregisterAllResInfoCallbacks through embedding,
	-- but wait to call it until Bars actually registers LibResInfo callbacks.
end

function module:RefreshConfig()
	db = self.db.profile

	if self:IsEnabled() then
		self:RefreshContainerFrame()
		self:RefreshMasqueButtons()
	end

	-- Later, this will also re-apply theme and additional text/font appearance
	-- settings.
end

-- --------------------------------------------------------------------
-- Public-to-addon helpers
-- --------------------------------------------------------------------

---@return SmartRes2_BarsProfileDB|nil profile
function module:GetProfile()
	return db
end

---@return number timeoutSeconds
function module:GetPendingTimeout()
	return PENDING_TIMEOUT_SECONDS
end