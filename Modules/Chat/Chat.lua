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
			["-50 DKP for being dead, %s."] = true,
			["%s, are you Exalted with the floor yet?"] = true,
			["%s, can I tell you about our lords and saviours, the Light and the Void?"] = true,
			["%s, you better not let this res time out!"] = true,
			["%s, you have been resurrected. Welcome back!"] = true,
			["%s wanted to read another silly random resurrection message."] = true,
			["%s was mostly dead. Not totally dead like Vol'jin or Varian."] = true,
			["A cleric, a corpse, and a miracle walk into a dungeon. Get up, %s."] = true,
			["A quick rollback should fix this whole being-dead problem, %s."] = true,
			["According to the combat log, %s has made a small tactical error."] = true,
			["Achievement unlocked, %s: Not Dead Anymore."] = true,
			["After careful review, %s's application to the afterlife has been declined."] = true,
			["Alert: %s has fallen and cannot get up. Assistance is on the way."] = true,
			["All right, %s, you've had your dramatic pause. Back to work."] = true,
			["And you thought the Scourge looked bad. In about 10 seconds, %s will want a comb, some soap, and a mirror."] = true,
			["Anyone want to experiment on %s's corpse? No? Okay, fine, I'll do the resurrection thing."] = true,
			["Arise, %s, and try to look surprised."] = true,
			["Azeroth needs %s. Apparently nobody else was available."] = true,
			["Bolvar says there must always be a living %s."] = true,
			["BRB, retrieving %s from the Shadowlands."] = true,
			["Bwonsamdi sent %s back. The invoice will arrive later."] = true,
			["By the power of questionable medical practices, I resurrect %s!"] = true,
			["Calling %s. Your regularly scheduled existence is ready to resume."] = true,
			["Chromie found a timeline where %s survived. Close enough."] = true,
			["Come back, %s. The boss still has plenty of mechanics left for you to ignore."] = true,
			["Contrary to popular belief, %s is not a permanent floor decoration."] = true,
			["Death is merely a setback, %s. A very inconvenient setback."] = true,
			["Do not adjust your monitor. %s will be alive shortly."] = true,
			["Don't go into the Light, %s. I'm using it over here."] = true,
			["Emergency maintenance on %s is now in progress."] = true,
			["Error 404: %s not found among the living. Restoring from backup."] = true,
			["Everybody gets one, %s. Try not to need two."] = true,
			["Good news, %s: your corpse run has been cancelled."] = true,
			["Great news, %s! Your death was only a limited-time event."] = true,
			["Hey %s! Stop being dead, lazy bones!"] = true,
			["Hold still, %s. This probably won't hurt twice."] = true,
			["How was the dirt nap, %s?"] = true,
			["I am resurrecting %s. But, um, what do I do with this extra arm?"] = true,
			["I am resurrecting %s."] = true,
			["I asked the Light for a refund on %s. It offered store credit."] = true,
			["I have altered the afterlife. Pray I do not alter it further, %s."] = true,
			["I hope %s kept the receipt for that death."] = true,
			["I see dead people. Specifically %s. Let's fix that."] = true,
			["I would leave %s dead, but then who would stand in the fire?"] = true,
			["I've seen enough. Put %s back in the raid."] = true,
			["If at first %s doesn't succeed, resurrect and try again."] = true,
			["If %s can read this, the resurrection is working as intended."] = true,
			["In the name of the Light, stop making this weird and get up, %s."] = true,
			["It appears %s tried turning life off and forgot to turn it on again."] = true,
			["Just a moment, %s. Your health bar is buffering."] = true,
			["Keep calm and accept the resurrection, %s."] = true,
			["Khadgar misplaced %s. Fortunately, I found the restore button."] = true,
			["Life finds a way, %s. This spell is the shortcut."] = true,
			["Look alive, %s! No, seriously. Look alive."] = true,
			["Mimiron had some spare parts, %s. You probably won't notice them."] = true,
			["My res cast time on %s is the fastest."] = true,
			["Never fear, %s. This resurrection is only mostly experimental."] = true,
			["No loot for ghosts, %s. You know what to do."] = true,
			["No one puts %s in a graveyard."] = true,
			["Not today, death. %s still has cooldowns to waste."] = true,
			["Patch notes: fixed an issue where %s remained dead."] = true,
			["Please wait while %s is restored to factory settings."] = true,
			["Plot armour activated for %s."] = true,
			["Rebooting %s. Please do not disconnect from the realm."] = true,
			["Resurrecting %s: because walking from the graveyard is apparently too much cardio."] = true,
			["Rumours of %s's demise have been greatly exaggerated."] = true,
			["Somehow, %s returned."] = true,
			["Spirit Healer, take the day off. I've got %s."] = true,
			["Stand by, %s. The Bronze dragonflight is undoing your last mistake."] = true,
			["Standing in the fire does not give you a Haste buff, %s."] = true,
			["Stop partying at the funeral, people. I'm bringing %s back to life."] = true,
			["The afterlife called about %s. Even they said it was too soon."] = true,
			["The Argent Crusade has reviewed %s's case and approved immediate reinstatement."] = true,
			["The floor boss has been defeated. %s may now rejoin the group."] = true,
			["The Kyrian lost %s's paperwork, so I'm sending it back."] = true,
			["The Light checked its notes and decided %s deserves another attempt."] = true,
			["The raid leader requested %s in living condition."] = true,
			["The Red dragonflight called. They want %s warmed up and moving again."] = true,
			["The reports of %s's death are accurate, but temporary."] = true,
			["The Scourge rejected %s's internship application."] = true,
			["The Spirit Healer can keep the durability loss. I'll resurrect %s here."] = true,
			["The universe tried to delete %s. Fortunately, I keep backups."] = true,
			["There is no place like home, and no place for %s in the graveyard."] = true,
			["This is %s's wake-up call. Snooze is not available."] = true,
			["This resurrection of %s is brought to you by the letter 'R', the number '4', and SmartRes2."] = true,
			["This resurrection spell contains no goblin engineering. Probably, %s."] = true,
			["Time to make the corpses, %s. Wait, wrong instruction. Getting you up!"] = true,
			["Today's forecast for %s: partly alive with a chance of repair bills."] = true,
			["Turns out %s was load-bearing. Resurrecting now."] = true,
			["Uther left the Light on for %s."] = true,
			["Wake up, %s. We have a world to save and loot to vendor."] = true,
			["We can rebuild %s. Better. Stronger. Faster."] = true,
			["We interrupt %s's dirt nap for this important resurrection."] = true,
			["What is dead may never—actually, never mind. Get up, %s."] = true,
			["Who needs a soulstone when %s has me?"] = true,
			["You can't loot while dead, %s. Consider this motivation."] = true,
			["You have about 10 more seconds of sleep time, %s."] = true,
			["Your free trial of death has expired, %s."] = true,
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
