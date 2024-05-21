local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:NewModule("Bars")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Bars:Print(...)

local db
local defaults = {
    enabled = true,
}

function module:OnInitialize()
    self.db = addon.db:RegisterNamespace(module:GetName(), {profile = defaults})
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    db = self.db.profile
    self:SetEnabledState(db.enabled)
    addon.options.args[module:GetName()] = self:GetOptions()
end

function module:OnEnable()
end

function module:OnDisable()
end

function module:RefreshConfig()
    db = self.db.profile
end