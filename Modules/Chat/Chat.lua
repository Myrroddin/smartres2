-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Chat
--
-- Core responsibilities:
-- - Register the Chat module.
-- - Own Chat module settings.
-- - Announce the player's single-target and mass resurrection casts.
-- - Notify players whose single-target resurrection casts will not finish first.
--
-- Runtime boundary:
-- - LibResInfo-2.0 owns resurrection detection and cast state.
-- - Chat consumes LibResInfo callbacks and emits chat output only.
-- - Bars owns visual resurrection state.
-- - Core owns local SmartRes2 system notifications through addon:NotifySelf().
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsPlayerNeutral = IsPlayerNeutral
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE
local LibStub = LibStub
local math_random = math.random
local pairs = pairs
local SendChatMessage = C_ChatInfo.SendChatMessage
local string_format = string.format
local string_sub = string.sub
local table_wipe = table.wipe
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitNameFromGUID = UnitNameFromGUID
local UNKNOWN = UNKNOWN

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
---@class Chat: AceAddon, AceEvent-3.0, AceConsole-3.0, LibResInfo-2.0
---@field db table
local module = addon:NewModule("Chat")

-- --------------------------------------------------------------------
-- Saved variable defaults
-- --------------------------------------------------------------------

local defaults = {
	profile = {
		enabled = true,
		notifyCollision = "WHISPER",
		singleResOutput = "WHISPER",
		massResOutput = "GROUP",
		overrideSingleResMessage = nil,
		overrideMassResMessage = nil,
		deletedSingleMessages = {},
		deletedMassMessages = {},
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
			["Resurrection, but make it efficient."] = true,
			["Everybody stay calm. I am restoring the group."] = true,
			["Group wipe recovery protocol initiated."] = true,
			["The floor has released its claim on you. For now."] = true,
			["Mass resurrection: because apparently one corpse was not enough."] = true,
			["Please keep all limbs inside the resurrection spell until casting is complete."] = true,
			["The afterlife denied your application. Welcome back."] = true,
			["I am pulling everyone back from the brink. Try not to sprint back there."] = true,
			["Rise, champions. The repair bill is not done with you yet."] = true,
			["I found the whole group in the lost and found. Resurrecting now."] = true,
		},
	},
}

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

local db

local PLAYER_GUID
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

local activeSingleCasts = {}

local collisionNotified = {}

module.randomSingleMessages = {}
module.randomMassMessages = {}

-- --------------------------------------------------------------------
-- Module lifecycle
-- --------------------------------------------------------------------

-- Create the Chat AceDB namespace and register the options table. Chat only
-- registers LibResInfo callbacks while enabled, so disabling the module also
-- stops all outgoing chat behavior.
function module:OnInitialize()
	self.db = addon.db:RegisterNamespace(self:GetName(), defaults)

	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

	db = self.db.profile
	PLAYER_GUID = UnitGUID("player")

	self:RefreshMessageCaches()
	self:SetEnabledState(db.enabled)

	addon:RegisterModuleOptions(self:GetName(), self:GetOptions())

	-- We must keep this event registered, even through disabling the module. Otherwise, we might miss the player's GUID changing with a faction change.
	if IsPlayerNeutral() and (isMists or isMainline) then
		self:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
	end
end

function module:OnEnable()
	self:RegisterCallback("ResCast_Started", "OnSingleResCastStarted")
	self:RegisterCallback("ResCast_Stopped", "OnSingleResCastStopped")
	self:RegisterCallback("ResCast_Finished", "OnSingleResCastFinished")
	self:RegisterCallback("MassResCast_Started", "OnMassResCastStarted")
	self:RegisterCallback("MassResCast_Stopped", "OnMassResCastStopped")
	self:RegisterCallback("MassResCast_Finished", "OnMassResCastFinished")
	self:RegisterCallback("FastestRes_Changed", "OnFastestResChanged")
end

function module:OnDisable()
	self:UnregisterAllResInfoCallbacks()

	table_wipe(activeSingleCasts)
	table_wipe(collisionNotified)
end

function module:RefreshConfig()
	db = self.db.profile

	self:RefreshMessageCaches()
end

-- --------------------------------------------------------------------
-- Message table helpers
-- --------------------------------------------------------------------

local function BuildEnabledMessageList(source, destination)
	table_wipe(destination)

	for message, enabled in pairs(source) do
		if enabled then
			destination[#destination + 1] = message
		end
	end
end

function module:RefreshMessageCaches()
	if not db then
		return
	end

	BuildEnabledMessageList(db.randomSingleMessages, self.randomSingleMessages)
	BuildEnabledMessageList(db.randomMassMessages, self.randomMassMessages)
end

local function GetRandomMessage(messages, fallback)
	local count = #messages

	if count == 0 then
		return fallback
	end

	return messages[math_random(count)]
end

function module:GetSingleResMessage(targetName)
	local message = db and db.overrideSingleResMessage
		or GetRandomMessage(self.randomSingleMessages, L["I am resurrecting %s."])

	return string_format(message, targetName)
end

function module:GetMassResMessage()
	return db and db.overrideMassResMessage
		or GetRandomMessage(self.randomMassMessages, L["I am casting mass resurrection."])
end

-- --------------------------------------------------------------------
-- Name and chat routing helpers
-- --------------------------------------------------------------------

local function GetNameFromGUID(unitGUID, includeRealm)
	if not unitGUID or unitGUID == "UNKNOWN" then
		return UNKNOWN
	end

	local name, realm = UnitNameFromGUID(unitGUID)

	if includeRealm and realm and realm ~= "" then
		return name .. "-" .. realm
	end

	return name or UNKNOWN
end

local function GetTargetName(targetGUID)
	return GetNameFromGUID(targetGUID, false)
end

local function GetGroupChatType()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

local function ResolveChatType(channelKey, allowWhisper)
	if not channelKey or channelKey == "NONE" then
		return nil
	end

	if channelKey == "GROUP" then
		return GetGroupChatType() or (allowWhisper and "WHISPER" or nil)
	end

	if channelKey == "INSTANCE_CHAT" then
		if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			return "INSTANCE_CHAT"
		end

		return GetGroupChatType() or (allowWhisper and "WHISPER" or nil)
	end

	if channelKey == "RAID" then
		if IsInRaid() then
			return "RAID"
		end

		return GetGroupChatType() or (allowWhisper and "WHISPER" or nil)
	end

	if channelKey == "PARTY" then
		if IsInGroup() then
			return "PARTY"
		end

		return allowWhisper and "WHISPER" or nil
	end

	if channelKey == "WHISPER" and allowWhisper then
		return "WHISPER"
	end
end

function module:SendConfiguredMessage(message, channelKey, fallbackWhisperGUID)
	local whisperTarget = fallbackWhisperGUID and GetNameFromGUID(fallbackWhisperGUID, true)
	local allowWhisper = whisperTarget ~= nil and whisperTarget ~= UNKNOWN
	local chatType = ResolveChatType(channelKey, allowWhisper)

	if not chatType then
		return
	end

	message = string_sub(message, 1, 255)

	if chatType == "WHISPER" then
		if allowWhisper then
			SendChatMessage(message, "WHISPER", nil, whisperTarget)
		end
	else
		SendChatMessage(message, chatType)
	end
end

-- --------------------------------------------------------------------
-- Collision notification helpers
-- --------------------------------------------------------------------

local function GetCollisionKey(casterGUID, targetGUID)
	return casterGUID .. ":" .. targetGUID
end

local function IsCollision(casterGUID, targetGUID, targetInfo)
	if not targetInfo or not targetInfo.fastestCasterGUID then
		return false
	end

	if targetGUID == "UNKNOWN" then
		return false
	end

	return targetInfo.fastestCasterGUID ~= casterGUID or targetInfo.fastestResType ~= "SINGLE"
end

function module:NotifyCollision(casterGUID, targetGUID, targetInfo)
	if not db or db.notifyCollision == "NONE" or not IsCollision(casterGUID, targetGUID, targetInfo) then
		return
	end

	local collisionKey = GetCollisionKey(casterGUID, targetGUID)

	if collisionNotified[collisionKey] then
		return
	end

	collisionNotified[collisionKey] = true

	local targetName = GetTargetName(targetGUID)
	local message = string_format(L["Your resurrection of %s will not finish first."], targetName)

	self:SendConfiguredMessage(message, db.notifyCollision, casterGUID)
end

function module:RefreshCollisionNotifications(targetGUID, targetInfo)
	if targetGUID == "UNKNOWN" then
		return
	end

	for casterGUID, casterInfo in pairs(activeSingleCasts) do
		if casterInfo.targetGUID == targetGUID then
			self:NotifyCollision(casterGUID, targetGUID, targetInfo)
		end
	end
end

-- --------------------------------------------------------------------
-- Update the player's GUID after a faction change, if necessary.
-- --------------------------------------------------------------------
function module:NEUTRAL_FACTION_SELECT_RESULT(_, success)
	if success then
		local factionGroup = UnitFactionGroup("player")

		if factionGroup == "Alliance" or factionGroup == "Horde" then
			PLAYER_GUID = UnitGUID("player")
			self:UnregisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
		end
	end
end

-- --------------------------------------------------------------------
-- LibResInfo callback handlers
-- --------------------------------------------------------------------

function module:OnSingleResCastStarted(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	if not db then
		return
	end

	activeSingleCasts[casterGUID] = casterInfo

	if casterGUID == PLAYER_GUID then
		local targetName = GetTargetName(targetGUID)

		self:SendConfiguredMessage(self:GetSingleResMessage(targetName), db.singleResOutput, targetGUID)
		addon:NotifySelf(string_format(L["I am resurrecting %s."], targetName))
	end

	self:NotifyCollision(casterGUID, targetGUID, targetInfo)
end

function module:OnSingleResCastStopped(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = nil

	if targetGUID then
		collisionNotified[GetCollisionKey(casterGUID, targetGUID)] = nil
	end
end

function module:OnSingleResCastFinished(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = nil

	if targetGUID then
		collisionNotified[GetCollisionKey(casterGUID, targetGUID)] = nil
	end
end

function module:OnMassResCastStarted(callback, casterGUID, casterInfo)
	if not db then
		return
	end

	if casterGUID == PLAYER_GUID then
		self:SendConfiguredMessage(self:GetMassResMessage(), db.massResOutput)
		addon:NotifySelf(L["I am casting mass resurrection."])
	end
end

function module:OnMassResCastStopped(callback, casterGUID, casterInfo)
end

function module:OnMassResCastFinished(callback, casterGUID, casterInfo)
end

function module:OnFastestResChanged(callback, targetGUID, targetInfo)
	self:RefreshCollisionNotifications(targetGUID, targetInfo)
end