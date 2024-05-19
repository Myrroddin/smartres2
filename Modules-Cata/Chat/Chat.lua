local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:NewModule("Chat")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

-- local variables
module.randomSingleMessages, module.randomMassMessages = {}, {}

-- upvalue Lua APIs
local tinsert = table.insert
local tsort = table.sort

local db
local defaults = {
    enabled = true,
    notifySelf = true,
    notifyCollision = "whisper",
    singleResOutput = "group",
    massResOutput = "group",
    overrideSingleResMessage = nil,
    overrideMassResMessage = nil,
    randomSingleMessages = {
        ["I am resurrecting %s."] = true,
        ["Hey %s! Stop being dead, lazy bones!"] = true,
        ["%s was mostly dead. Not totally dead like Vol'jin or Varian."] = true,
        ["%s, are you Exalted with the floor yet?"] = true,
        ["We can rebuild %s. Better. Stronger. Faster."] = true,
        ["Anyone want to experiment on %s's corpse? No? Okay, fine, I'll do the resurrection thing."] = true,
        ["-50 DKP for being dead, %s."] = true,
        ["Stop partying at the funeral, people. I'm bringing %s back to life."] = true,
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
        ["My res cast time on %s is the fastest."] = true,
        ["%s, you better not let this res time out!"] = true,
    },
    randomMassMessages = {
        ["What's better than a resurrection spell? A mass resurrection spell!"] = true,
        ["All your resurrections are belong to me!"] = true,
        ["I am casting mass resurrection."] = true,
        ["You get a res, and you, and you. Mass resurrection for everybody!"] = true,
        ["This mass resurrection is brought to you by the Light."] = true,
        ["Terenas Menethil taught me mass resurrection. All of you benefit from his knowledge."] = true,
        ["Casting mass resurrection is like doing a jigsaw puzzle without the picture. I hope everyone's parts are correct!"] = true,
        ["If you are seeing this mass resurrection message, my cast time is the fastest."] = true,
        ["Of all the random mass resurrection messages, I get this one!?"] = true,
        ["Blame the healer for this mass res. Oh, wait..."] = true,
    }
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
    self.randomSingleMessages, self.randomMassMessages = {}, {}
    db = self.db.profile
end