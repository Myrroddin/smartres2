-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Chat
--
-- Responsibilities:
-- - Initialize the Chat settings namespace and lifecycle.
-- - Announce the player's single-target and mass resurrection casts.
-- - Notify casters whose single-target resurrection will not finish first.
-- - Resolve configured group and whisper destinations.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local GetNumGroupMembers = GetNumGroupMembers
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE
local LibStub = LibStub
local math_random = math.random
local pairs = pairs
local SendChatMessage = C_ChatInfo.SendChatMessage
local string_find = string.find
local string_format = string.format
local string_sub = string.sub
local table_wipe = table.wipe
local UnitClassBase = UnitClassBase
local UnitGUID = UnitGUID
local UNKNOWN = UNKNOWN

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
---@class Chat: AceAddon, AceEvent-3.0, AceConsole-3.0, LibResInfo-2.0
---@field db AceDBObject-3.0
local module = addon:NewModule("Chat")

-- --------------------------------------------------------------------
-- Lifecycle state and defaults
-- --------------------------------------------------------------------

local defaults = {
	profile = {
		enabled = true,
		useFullNameForMessages = true,
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

local UNKNOWN_TARGET_GUID = "UNKNOWN"

---@type table
local db
local activeSingleCasts = {}
local collisionNotified = {}
local randomSingleMessages = {}
local randomMassMessages = {}

-- --------------------------------------------------------------------
-- Message cache helpers
-- --------------------------------------------------------------------

local function BuildEnabledMessageList(source, destination)
	table_wipe(destination)

	for message, enabled in pairs(source) do
		if enabled then
			destination[#destination + 1] = message
		end
	end
end

local function RefreshMessageCaches()
	BuildEnabledMessageList(db.randomSingleMessages, randomSingleMessages)
	BuildEnabledMessageList(db.randomMassMessages, randomMassMessages)
end

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

	RefreshMessageCaches()
	self:SetEnabledState(db.enabled)

	addon:RegisterModuleOptions(self:GetName(), self:GetOptions())
end

function module:OnEnable()
	self:RegisterCallback("ResCast_Started", "OnSingleResCastStarted")
	self:RegisterCallback("ResCast_Stopped", "OnSingleResCastStopped")
	self:RegisterCallback("ResCast_Finished", "OnSingleResCastFinished")
	self:RegisterCallback("MassResCast_Started", "OnMassResCastStarted")
	self:RegisterCallback("FastestRes_Changed", "OnFastestResChanged")
	self:RegisterCallback("ResTargetGUID_Resolved", "OnResTargetGUIDResolved")
end

function module:OnDisable()
	self:UnregisterAllResInfoCallbacks()

	table_wipe(activeSingleCasts)
	table_wipe(collisionNotified)
end

function module:RefreshConfig()
	db = self.db.profile

	RefreshMessageCaches()
end

-- --------------------------------------------------------------------
-- Message selection
-- --------------------------------------------------------------------

local function GetRandomMessage(messages, fallback)
	local count = #messages

	if count == 0 then
		return fallback
	end

	return messages[math_random(count)]
end

local function ReplaceTargetPlaceholder(message, targetName)
	local placeholderStart, placeholderEnd = string_find(message, "%s", 1, true)

	if not placeholderStart then
		return message
	end

	return string_sub(message, 1, placeholderStart - 1)
		.. targetName
		.. string_sub(message, placeholderEnd + 1)
end

function module:GetLocalizedRandomMessage(message, isMass)
	local defaultMessages = isMass and defaults.profile.randomMassMessages or defaults.profile.randomSingleMessages

	if defaultMessages[message] then
		return L[message]
	end

	return message
end

local function GetSingleResMessage(targetName)
	local message = db.overrideSingleResMessage

	if not message then
		message = GetRandomMessage(randomSingleMessages, "I am resurrecting %s.")
		message = module:GetLocalizedRandomMessage(message, false)
	end

	return ReplaceTargetPlaceholder(message, targetName)
end

local function GetMassResMessage()
	local message = db.overrideMassResMessage

	if not message then
		message = GetRandomMessage(randomMassMessages, "I am casting mass resurrection.")
		message = module:GetLocalizedRandomMessage(message, true)
	end

	return message
end

-- --------------------------------------------------------------------
-- Name and chat routing helpers
-- --------------------------------------------------------------------

local function GetUnitClassByGUID(unitGUID)
	if not unitGUID or unitGUID == UNKNOWN_TARGET_GUID then
		return nil
	end

	if addon.PLAYER_GUID == unitGUID then
		return UnitClassBase("player")
	end

	local numGroupMembers = GetNumGroupMembers()

	if IsInRaid() then
		for index = 1, numGroupMembers do
			local unit = "raid" .. index

			if UnitGUID(unit) == unitGUID then
				return UnitClassBase(unit)
			end
		end
	else
		for index = 1, numGroupMembers - 1 do
			local unit = "party" .. index

			if UnitGUID(unit) == unitGUID then
				return UnitClassBase(unit)
			end
		end
	end
end

local function GetTargetName(targetGUID)
	return addon:GetUnitNameFromGUID(targetGUID, db.useFullNameForMessages)
end

local function GetSystemMessageTargetName(targetGUID)
	local profile = addon.db.profile
	local targetName = addon:GetUnitNameFromGUID(targetGUID, profile.useFullNameForSystemMessages)

	if not profile.useClassColorsForSystemMessages or targetName == UNKNOWN then
		return targetName
	end

	return addon:GetClassColoredName(targetName, GetUnitClassByGUID(targetGUID)) or targetName
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
		elseif IsInRaid() then
			return "RAID"
		elseif IsInGroup() then
			return "PARTY"
		end

		return allowWhisper and "WHISPER" or nil
	end

	if channelKey == "RAID" then
		if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			return "INSTANCE_CHAT"
		elseif IsInRaid() then
			return "RAID"
		elseif IsInGroup() then
			return "PARTY"
		end

		return allowWhisper and "WHISPER" or nil
	end

	if channelKey == "PARTY" then
		if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
			return "INSTANCE_CHAT"
		elseif IsInGroup() then
			return "PARTY"
		end

		return allowWhisper and "WHISPER" or nil
	end

	if channelKey == "WHISPER" and allowWhisper then
		return "WHISPER"
	end
end

local function SendConfiguredMessage(message, channelKey, fallbackWhisperGUID)
	local whisperTarget = fallbackWhisperGUID and addon:GetUnitNameFromGUID(fallbackWhisperGUID, true)
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

local function IsKnownTargetGUID(targetGUID)
	return targetGUID ~= nil and targetGUID ~= UNKNOWN_TARGET_GUID
end

local function GetCollisionKey(casterGUID, targetGUID)
	return casterGUID .. ":" .. targetGUID
end

local function ClearCollisionNotification(casterGUID, targetGUID)
	if not IsKnownTargetGUID(targetGUID) then
		return
	end

	collisionNotified[GetCollisionKey(casterGUID, targetGUID)] = nil
end

local function IsCollision(casterGUID, targetGUID, targetInfo)
	-- UNKNOWN is a staging marker, not a shared target identity. Never compare or
	-- notify unresolved casts because each UNKNOWN entry may represent a different
	-- actual target.
	if not IsKnownTargetGUID(targetGUID) then
		return false
	end

	if not targetInfo or not targetInfo.fastestCasterGUID then
		return false
	end

	return targetInfo.fastestCasterGUID ~= casterGUID or targetInfo.fastestResType ~= "SINGLE"
end

local function NotifyCollision(casterGUID, targetGUID, targetInfo)
	if db.notifyCollision == "NONE" or not IsCollision(casterGUID, targetGUID, targetInfo) then
		return
	end

	local collisionKey = GetCollisionKey(casterGUID, targetGUID)

	if collisionNotified[collisionKey] then
		return
	end

	collisionNotified[collisionKey] = true

	local targetName = GetTargetName(targetGUID)
	local message = string_format(L["Your resurrection of %s will not finish first."], targetName)

	SendConfiguredMessage(message, db.notifyCollision, casterGUID)
end

local function RefreshCollisionNotifications(targetGUID, targetInfo)
	if not IsKnownTargetGUID(targetGUID) then
		return
	end

	for casterGUID, casterInfo in pairs(activeSingleCasts) do
		if casterInfo.targetGUID == targetGUID then
			NotifyCollision(casterGUID, targetGUID, targetInfo)
		end
	end
end

-- --------------------------------------------------------------------
-- LibResInfo callback handlers
-- --------------------------------------------------------------------

local function AnnouncePlayerSingleRes(targetGUID)
	-- Defer all output until LibResInfo resolves a real target GUID. Besides making
	-- whispers possible, this prevents public messages from naming an ambiguous
	-- UNKNOWN target.
	if not IsKnownTargetGUID(targetGUID) then
		return
	end

	local messageTargetName = GetTargetName(targetGUID)
	local systemMessageTargetName = GetSystemMessageTargetName(targetGUID)

	SendConfiguredMessage(GetSingleResMessage(messageTargetName), db.singleResOutput, targetGUID)
	addon:NotifySelf(string_format(L["I am resurrecting %s."], systemMessageTargetName))
end

function module:OnSingleResCastStarted(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = casterInfo

	if casterGUID == addon.PLAYER_GUID then
		AnnouncePlayerSingleRes(targetGUID)
	end

	NotifyCollision(casterGUID, targetGUID, targetInfo)
end

function module:OnSingleResCastStopped(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = nil
	ClearCollisionNotification(casterGUID, targetGUID)
end

function module:OnSingleResCastFinished(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = nil
	ClearCollisionNotification(casterGUID, targetGUID)
end

function module:OnMassResCastStarted(callback, casterGUID, casterInfo)
	if casterGUID == addon.PLAYER_GUID then
		SendConfiguredMessage(GetMassResMessage(), db.massResOutput)
		addon:NotifySelf(L["I am casting mass resurrection."])
	end
end

function module:OnFastestResChanged(callback, targetGUID, targetInfo)
	RefreshCollisionNotifications(targetGUID, targetInfo)
end

function module:OnResTargetGUIDResolved(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = casterInfo

	if casterGUID == addon.PLAYER_GUID then
		AnnouncePlayerSingleRes(targetGUID)
	end

	RefreshCollisionNotifications(targetGUID, targetInfo)
end