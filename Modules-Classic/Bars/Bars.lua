---@diagnostic disable: duplicate-set-field, undefined-field
-- File Date: @file-date-iso@
---@class addon: AceAddon
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

---@class module: AceModule
local module = addon:NewModule("Bars")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- additional libraries
module.masque = LibStub("Masque", true)
local masque = module.masque
module.lsm = LibStub("LibSharedMedia-3.0")
local lsm = module.lsm

-- register media (fonts, borders, backgrounds, etc) with LibSharedMedia-3.0
local MediaType_FONT = lsm.MediaType.FONT or "font"
local MediaType_BACKGROUND = lsm.MediaType.BACKGROUND or "background"
local MediaType_BORDER = lsm.MediaType.BORDER or "border"
local MediaType_STATUSBAR = lsm.MediaType.STATUSBAR or "statusBar"
lsm:Register(MediaType_FONT, "Olde English", [[Interface\AddOns\SmartRes2\Media\Fonts\OldeEnglish.ttf]])

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Bars:Print(...)

local db
local defaults = {
    enabled = true,
    fontType = "Friz Quadrata TT",
    fontSize = 10,
    fontFlags = "",
    clampToScreen = true,
    lockFrame = false,
    supportMasque = true,
    iconPosition = "LEFT",
    background = "Blizzard Tooltip",
    border = "Blizzard Tooltip",
    borderThickness = 5,
    statusBar = "Blizzard",
    leftInset = 0,
    rightInset = 0,
    topInset = 0,
    bottomInset = 0,
    width = 250,
    height = 200,
    x = 0,
    y = 0,
    scale = 1,
    point = "CENTER",
    theme = "Tooltip",
    -- note to self: any RGB codes found online must be divided by 255, EX: 174/255 rounded to 3 decimals is 0.682
    -- there are 256 (0 to 255) values; dividing 0/255 does nothing therefore use 0. Blizzard uses a 0 to 1 scale, hence dividing by 255
    goodSingleRes = {r = 0, g = 0.682, b = 0.345, a = 1},
    collisionSingleRes = {r = 0.839, g = 0, b = 0.11, a = 1},
    waitingToAccept = {r = 0, g = 0.306, b = 1, a = 1},
}

function module:OnInitialize()
    self.db = addon.db:RegisterNamespace(module:GetName(), {profile = defaults})
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    db = self.db.profile
    self:SetEnabledState(db.enabled)

    local options = self:GetOptions()
    addon:RegisterModuleOptions(module:GetName(), options)
    self:CreateResFrame()
    self:GetResFramePosition()
end

function module:OnEnable()
    if self.resFrame and not self.resFrame:IsShown() then
        self.resFrame:Show()
    end
end

function module:OnDisable()
    if self.resFrame then
        if self.resFrame:IsShown() then
            self.resFrame:Hide()
        end
    end
end

function module:RefreshConfig()
    db = self.db.profile
    if self.resFrame and not self.resFrame:IsShown() then
        self.resFrame:Show()
    end
    self:SetResFramePosition()
end

function module:CreateResFrame()
    if not self.resFrame then
        local f = CreateFrame("Frame", "SmartRes2_ResFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetWidth(db.width)
        f:SetHeight(db.height)
        f:SetPoint(db.point, UIParent, db.point, db.x / db.scale, db.y / db.scale)
        f:SetScale(db.scale)
        f:SetClampedToScreen(db.clampToScreen)
        f:EnableMouse(false)
        f:SetBackdrop({
            bgFile = lsm:Fetch(MediaType_BACKGROUND, db.background),
            edgeFile = lsm:Fetch(MediaType_BORDER, db.border),
            tile = true,
            edgeSize = db.borderThickness,
            insets = {left = db.leftInset, right = db.rightInset, top = db.topInset, bottom = db.bottomInset}
        })
        self.resFrame = f
        self.resFrame:Hide()
    end
end

-- calculate resFrame's true position and update the saved variables
function module:GetResFramePosition()
    local parent = UIParent
    local s = self.resFrame:GetScale()
    local left, top = self.resFrame:GetLeft() * s, self.resFrame:GetTop() * s
    local right, bottom = self.resFrame:GetRight() * s, self.resFrame:GetBottom() * s
    local pWidth, pHeight = parent:GetWidth(), parent:GetHeight()

    local x, y, point
    if left > (pWidth - right) and left < abs((left + right) / 2 - pWidth /2) then
        x, point = left, "LEFT"
	elseif (pWidth - right) < abs((left + right)/2 - pWidth / 2) then
		x, point = right - pWidth, "RIGHT"
	else
		x, point = (left + right)/2 - pWidth / 2, ""
    end

    if bottom < (pHeight - top) and bottom < abs((bottom + top) / 2 - pHeight / 2) then
		y, point = bottom, "BOTTOM" .. point
	elseif (pHeight - top) < abs((bottom + top) / 2 - pHeight / 2) then
		y, point = top - pHeight, "TOP" .. point
	else
		y, point = (bottom + top) / 2 - pHeight / 2, ""
    end

    if point == "" then point = "CENTER" end

    db.x, db.y, db.point = x, y, point

    self.resFrame:ClearAllPoints()
    self.resFrame:SetPoint(db.point, parent, db.point, db.x / s, db.y / s)
end

-- set a new position for resFrame based on the user's saved variables
function module:SetResFramePosition()
    local x = db.x or 0
    local y = db.y or 0
    local point = db.point or "CENTER"
    local scale = db.scale or 1
    local width = db.width or 200
    local height = db.height or 400

    x, y = x / scale, y / scale

    self.resFrame:SetScale(scale)
    self.resFrame:SetWidth(width)
    self.resFrame:SetHeight(height)

    self.resFrame:ClearAllPoints()
    self.resFrame:SetPoint(point, UIParent, point, x, y)
end