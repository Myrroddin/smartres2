local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local module = addon:NewModule("Chat")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

local db
local defaults = {
    profile = {
        enabled = true,
    }
}

function module:OnInitialize()
    self.db = addon.db:RegisterNamespace("Chat", defaults)
    db = self.db.profile
    self:SetEnabledState(db.enabled)
end

function module:OnEnable()
    self:SetEnabledState(db.enabled)
end

function module:OnDisable()
    self:SetEnabledState(db.enabled)
end

function module:RefreshConfig()
    db = self.db.profile
end