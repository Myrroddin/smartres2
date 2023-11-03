local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local module = addon:NewModule("Chat")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

-- local variables
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
module.singleRandomMessages, module.massRandomMessages = {}, {}

local db
local defaults = {
    enabled = true,
    notifySelf = true,
    notifyCollision = "WHISPER",
    singleResOutput = "GROUP",
    massResOutput = "GROUP",
    overrideSingleResMessage = nil,
    overrideMassResMessage = nil,
    randomSingleMessages = {
        "I am resurrecting %s.",
        "Hey %s! Stop being dead, lazy bones!",
        "%s was mostly dead. Not totally dead like Vol'jin or Varian.",
        "%s, are you Exalted with the floor yet?",
        "We can rebuild %s. Better. Stronger. Faster.",
        "Anyone want to experiment on %s's corpse? No? Okay, fine, I'll do the resurrection thing.",
        "-50 DKP for being dead, %s.",
        "Stop partying at the funeral, people. I'm bring %s back to life.",
        "Standing in the fire does not give you a Haste buff, %s.",
        "Going to the Shadowlands, %s? I don't think so!",
        "Rumours of %s's demise have been greatly exaggerated.",
        "I am resurrecting %s. But, um, what do I do with this extra arm?",
        "%s, can I tell you about our lords and saviours, the Light and the Void?",
        "%s wanted to read another silly random resurrection message.",
        "And you thought the Scourge looked bad. In about 10 seconds, %s will want a comb, some soap, and a mirror.",
        "Think that was bad? I proudly show %s the scar tissue caused by Hogger.",
        "How is the dirt nap, %s?",
        "You have about 10 more seconds of sleep time, %s.",
    }
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
    wipe(module.singleRandomMessages)
    wipe(module.massRandomMessages)
    db = addon.db.profile.modules[module:GetName()]
end