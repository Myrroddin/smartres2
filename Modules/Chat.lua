local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local module = addon:NewModule("Chat")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

local db
local defaults = {
    enabled = true,
    notifySelf = true,
    notifyCollision = true,
    singleResOutput = "group",
    massResOutput = "group",
}

function module:OnInitialize()
    addon:RegisterModuleDefaults(module:GetName(), defaults)
    local options = self:GetOptions()
    addon:RegisterModuleOptions(module:GetName(), options)
    db = addon.db.profile.modules[module:GetName()]
end

function module:OnEnable()
end

function module:OnDisable()
end

function module:RefreshConfig()
    db = addon.db.profile.modules[module:GetName()]
end