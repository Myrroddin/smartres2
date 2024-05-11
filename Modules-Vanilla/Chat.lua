local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local module = addon:NewModule("Chat")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

-- local variables
module.singleRandomMessages = {}

local db
local defaults = {
    enabled = true,
    notifySelf = true,
    notifyCollision = "whisper",
    singleResOutput = "group",
    overrideSingleResMessage = nil,
    randomSingleMessages = {
        ["I am resurrecting %s."] = true,
        ["Hey %s! Stop being dead, lazy bones!"] = true,
        ["%s was mostly dead. Not totally dead like Vol'jin or Varian."] = true,
        ["%s, are you Exalted with the floor yet?"] = true,
        ["We can rebuild %s. Better. Stronger. Faster."] = true,
        ["Anyone want to experiment on %s's corpse? No? Okay, fine, I'll do the resurrection thing."] = true,
        ["-50 DKP for being dead, %s."] = true,
        ["Stop partying at the funeral, people. I'm bring %s back to life."] = true,
        ["Standing in the fire does not give you a Haste buff, %s."] = true,
        ["Going to the Shadowlands, %s? I don't think so!"] = true,
        ["Rumours of %s's demise have been greatly exaggerated."] = true,
        ["I am resurrecting %s. But, um, what do I do with this extra arm?"] = true,
        ["%s, can I tell you about our lords and saviours, the Light and the Void?"] = true,
        ["%s wanted to read another silly random resurrection message."] = true,
        ["And you thought the Scourge looked bad. In about 10 seconds, %s will want a comb, some soap, and a mirror."] = true,
        ["Think that was bad? I proudly show %s the scar tissue caused by Hogger."] = true,
        ["How was the dirt nap, %s?"] = true,
        ["You have about 10 more seconds of sleep time, %s."] = true,
    }
}

function module:OnInitialize()
    self.db = addon.db:RegisterNamespace(module:GetName(), {profile = defaults})
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
    addon.options.args[module:GetName()] = self:GetOptions()
    db = self.db.profile
    self:SetEnabledState(db.enabled)
end

function module:OnEnable()
end

function module:OnDisable()
end

function module:RefreshConfig()
    db = self.db.profile
end