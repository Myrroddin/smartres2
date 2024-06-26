local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:NewModule("Bars")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local LSM = addon.LSM
module.lwin = LibStub("LibWindow-1.1")
local lwin = module.lwin

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Bars:Print(...)

local db
local defaults = {
    enabled = true,
    fontType = "Friz Quadrata TT",
    fontSize = 10,
    fontFlags = "",
    clampToScreen = true,
    lockFrame = true,
    background = "Blizzard Tooltip",
    border = "Blizzard Tooltip",
    borderThickness = 5,
    statusBar = "Blizzard",
    leftInset = 0,
    rightInset = 0,
    topInset = 0,
    bottomInset = 0,
    theme = "Tooltip",
    -- note to self: any RGB codes found online must be divided by 255, EX: 174/255 rounded to 3 decimals is 0.682
    -- there are 256 (0 to 255) values; dividing 0/255 does nothing therefore use 0. Blizzard uses a 0 to 1 scale, hence dividing by 255
    goodSingleRes = {r = 0, g = 0.682, b = 0.345, a = 1},
    goodMassRes = {r = 0, g = 0.431, b = 0.2, a = 1},
    collisionSingleRes = {r = 0.839, g = 0, b = 0.11, a = 1},
    collisionMassRes = {r = 0.651, g = 0.039, b = 0.239, a = 1},
    -- frame position, controlled by LibWindow-1.1
    framePositioning = {
        x = -350,
        y = 350,
        scale = 1,
        point = "BOTTOMRIGHT"
    }
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
end

function module:OnEnable()
end

function module:OnDisable()
end

function module:RefreshConfig()
    db = self.db.profile
    --[[
    To Do: lwin.RegisterConfig(myFrame, db.framePositioning)
    lwin.RestorePosition(myFrame)
    ]]
end