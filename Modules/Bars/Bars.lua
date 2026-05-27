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
--
-- Current boundary:
-- - This file creates the visible container frame only.
-- - It does not create LibCandyBar bars yet.
-- - It does not consume LibResInfo callbacks yet.
--
-- Future responsibilities:
-- - Track active cast bars keyed by casterGUID.
-- - Track waiting-to-accept bars keyed by targetGUID.
-- - Render visible bars with LibCandyBar-3.0.
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
local LibStub = LibStub
local math_floor = math.floor
local UIParent = UIParent

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

---@class SmartRes2: AceAddon
---@field db SmartRes2DB
---@field RegisterModuleOptions fun(self: SmartRes2, optionsName: string, moduleOptions: table)
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

-- This frame is both a normal Frame and a BackdropTemplate frame. Plain frames
-- do not always expose SetBackdrop methods, so the container is explicitly
-- created with "BackdropTemplate" and annotated as such for WoWLua-LS.
---@alias SmartRes2_BackdropFrame Frame & BackdropTemplate

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
---@field fontFlags string Required SetFont flags string; use "" for no effects.
---@field statusBar string LibSharedMedia statusbar key.

---@class SmartRes2_BarsBehaviorDB
---@field maxBars number
---@field transitionDuration number
---@field fill boolean
---@field showTime boolean
---@field showLabel boolean
---@field iconPosition "LEFT"|"RIGHT"|"NONE"

---@class SmartRes2_BarsProfileDB
---@field enabled boolean
---@field frame SmartRes2_BarsFrameDB
---@field media SmartRes2_BarsMediaDB
---@field behavior SmartRes2_BarsBehaviorDB
---@field activeTheme string

---@class SmartRes2_BarsDB: AceDBObject-3.0
---@field profile SmartRes2_BarsProfileDB

---@class SmartRes2_Bars: AceAddon, AceEvent-3.0, AceConsole-3.0, LibResInfo-2.0
---@field db SmartRes2_BarsDB
---@field containerFrame SmartRes2_BackdropFrame|nil
---@field GetOptions fun(self: SmartRes2_Bars): table
local module = addon:NewModule("Bars")

-- --------------------------------------------------------------------
-- Libraries
-- --------------------------------------------------------------------

local LibSharedMedia = LibStub("LibSharedMedia-3.0")
local Masque = LibStub("Masque", true)

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

-- The resurrection accept popup times out after 60 seconds. This is a game
-- mechanic, not user preference, so Bars treats waiting bars as expired after
-- this hard cap unless LibResInfo reports the target accepted/returned alive
-- first.
local PENDING_TIMEOUT_SECONDS = 60

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
				backgroundColor = {
					r = 0,
					g = 0,
					b = 0,
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
			fontFlags = "",
			statusBar = "Blizzard",
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

---@type boolean
local hasMasque = Masque ~= nil

-- --------------------------------------------------------------------
-- Media registration
-- --------------------------------------------------------------------

local function RegisterMedia()
	-- Register only SmartRes2-owned media here. LibSharedMedia already
	-- registers Blizzard defaults such as "Blizzard", "Solid",
	-- "Blizzard Tooltip", and locale-aware default fonts.
	--
	-- Example for later:
	-- LibSharedMedia:Register(
	--     LibSharedMedia.MediaType.FONT,
	--     "SmartRes2 Olde English",
	--     [[Interface\AddOns\SmartRes2\Media\Fonts\OldeEnglish.ttf]]
	-- )
end

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

	self.containerFrame = frame

	return frame
end

-- Applies the DB-driven backdrop to the container frame.
--
-- LibSharedMedia returns nil for the "None" key. That is useful here: a nil
-- bgFile or edgeFile simply means that part of the backdrop is not drawn.
function module:ApplyContainerBackdrop()
	if not db or not self.containerFrame or not self.containerFrame.SetBackdrop then
		return
	end

	local backdropSettings = db.frame.backdrop
	local backgroundColor = backdropSettings.backgroundColor
	local borderColor = backdropSettings.borderColor
	local insets = backdropSettings.insets

	local background = LibSharedMedia:Fetch(LibSharedMedia.MediaType.BACKGROUND, backdropSettings.background)
	local border = LibSharedMedia:Fetch(LibSharedMedia.MediaType.BORDER, backdropSettings.border)

	self.containerFrame:SetBackdrop({
		bgFile = background,
		edgeFile = border,
		edgeSize = backdropSettings.edgeSize,
		insets = {
			left = insets.left,
			right = insets.right,
			top = insets.top,
			bottom = insets.bottom,
		},
	})

	self.containerFrame:SetBackdropColor(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a)
	self.containerFrame:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
end

-- Applies profile frame settings to the container. This helper only handles
-- the container itself; future CandyBar positioning will happen in a separate
-- layout pass so hidden bars can still be tracked without being rendered.
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

-- Returns true when there is something meaningful to show inside the container.
-- At this stage no live bars exist yet, so this intentionally returns false.
-- Later this will check the tracked/visible bar state.
---@return boolean hasVisibleBars
function module:HasVisibleBars()
	return false
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

	RegisterMedia()

	addon:RegisterModuleOptions(self:GetName(), self:GetOptions())
end

function module:OnEnable()
	self:RefreshContainerFrame()

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
	if self.containerFrame then
		self.containerFrame:Hide()
	end

	-- Bars will unregister callbacks and hide/release bars here once rendering
	-- exists.
	--
	-- LibResInfo-2.0 provides UnregisterAllResInfoCallbacks through embedding,
	-- but wait to call it until Bars actually registers LibResInfo callbacks.
end

function module:RefreshConfig()
	db = self.db.profile

	if self:IsEnabled() then
		self:RefreshContainerFrame()
	end

	-- Later, this will also re-apply media, theme, color, text, and bar
	-- appearance settings.
end

-- --------------------------------------------------------------------
-- Public-to-addon helpers
-- --------------------------------------------------------------------

function module:IsMasqueAvailable()
	return hasMasque
end

---@return SmartRes2_BarsProfileDB|nil profile
function module:GetProfile()
	return db
end

---@return number timeoutSeconds
function module:GetPendingTimeout()
	return PENDING_TIMEOUT_SECONDS
end