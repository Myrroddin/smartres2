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

local C_ChatInfo = C_ChatInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsPlayerNeutral = IsPlayerNeutral
local LE_PARTY_CATEGORY_INSTANCE = LE_PARTY_CATEGORY_INSTANCE
local LibStub = LibStub
local math_random = math.random
local pairs = pairs
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

---@class SmartRes2: AceAddon, AceConsole-3.0
---@field db SmartRes2DB
---@field NotifySelf fun(self: SmartRes2, message: string)
---@field RegisterModuleOptions fun(self: SmartRes2, moduleName: string, moduleOptions: table)
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

---@class SmartRes2_ResCastInfo
---@field casterGUID string
---@field targetGUID string|nil
---@field castTime number|nil
---@field spellID integer
---@field textureID integer|nil
---@field endTime number|nil

---@class SmartRes2_ResTargetInfo
---@field targetGUID string
---@field fastestCasterGUID string|nil
---@field fastestResType "SINGLE"|"MASS"|nil

---@class SmartRes2_ChatProfileDB
---@field enabled boolean
---@field notifyCollision "GROUP"|"WHISPER"|"NONE"
---@field singleResOutput "GROUP"|"INSTANCE_CHAT"|"RAID"|"PARTY"|"WHISPER"|"NONE"
---@field massResOutput "GROUP"|"INSTANCE_CHAT"|"RAID"|"PARTY"|"NONE"
---@field overrideSingleResMessage string|nil
---@field overrideMassResMessage string|nil
---@field deletedSingleMessages table<string, string>
---@field deletedMassMessages table<string, string>
---@field randomSingleMessages table<string, boolean>
---@field randomMassMessages table<string, boolean>

---@class SmartRes2_ChatDB: AceDBObject-3.0
---@field profile SmartRes2_ChatProfileDB

---@class SmartRes2_Chat: AceAddon, AceConsole-3.0, AceEvent-3.0, LibResInfo-2.0
---@field db SmartRes2_ChatDB
---@field randomSingleMessages string[]
---@field randomMassMessages string[]
---@field GetOptions fun(self: SmartRes2_Chat): table
---@field RegisterCallback fun(self: SmartRes2_Chat, eventName: string, method?: string, arg?: any)
---@field UnregisterAllResInfoCallbacks fun(self: SmartRes2_Chat)
local module = addon:NewModule("Chat")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

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

---@type SmartRes2_ChatProfileDB|nil
local db

---@type string|nil
local PLAYER_GUID
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

---@type table<string, SmartRes2_ResCastInfo>
local activeSingleCasts = {}

---@type table<string, true>
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
	self.db = addon.db:RegisterNamespace(self:GetName(), defaults) --[[@as SmartRes2_ChatDB]]

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

---@param source table<string, boolean>
---@param destination string[]
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

---@param messages string[]
---@param fallback string
---@return string message
local function GetRandomMessage(messages, fallback)
	local count = #messages

	if count == 0 then
		return fallback
	end

	return messages[math_random(count)]
end

---@param targetName string
---@return string message
function module:GetSingleResMessage(targetName)
	local message = db and db.overrideSingleResMessage
		or GetRandomMessage(self.randomSingleMessages, L["I am resurrecting %s."])

	return string_format(message, targetName)
end

---@return string message
function module:GetMassResMessage()
	return db and db.overrideMassResMessage
		or GetRandomMessage(self.randomMassMessages, L["I am casting mass resurrection."])
end

-- --------------------------------------------------------------------
-- Name and chat routing helpers
-- --------------------------------------------------------------------

---@param unitGUID string|nil
---@param includeRealm boolean|nil
---@return string name
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

---@param targetGUID string|nil
---@return string name
local function GetTargetName(targetGUID)
	return GetNameFromGUID(targetGUID, false)
end

---@return string|nil chatType
local function GetGroupChatType()
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		return "INSTANCE_CHAT"
	elseif IsInRaid() then
		return "RAID"
	elseif IsInGroup() then
		return "PARTY"
	end
end

---@param channelKey string|nil
---@param allowWhisper boolean
---@return string|nil chatType
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

---@param message string
---@param channelKey string|nil
---@param fallbackWhisperGUID string|nil
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
			C_ChatInfo.SendChatMessage(message, "WHISPER", nil, whisperTarget)
		end
	else
		C_ChatInfo.SendChatMessage(message, chatType)
	end
end

-- --------------------------------------------------------------------
-- Collision notification helpers
-- --------------------------------------------------------------------

---@param casterGUID string
---@param targetGUID string
---@return string key
local function GetCollisionKey(casterGUID, targetGUID)
	return casterGUID .. ":" .. targetGUID
end

---@param casterGUID string
---@param targetGUID string
---@param targetInfo SmartRes2_ResTargetInfo|nil
---@return boolean isCollision
local function IsCollision(casterGUID, targetGUID, targetInfo)
	if not targetInfo or not targetInfo.fastestCasterGUID then
		return false
	end

	if targetGUID == "UNKNOWN" then
		return false
	end

	return targetInfo.fastestCasterGUID ~= casterGUID or targetInfo.fastestResType ~= "SINGLE"
end

---@param casterGUID string
---@param targetGUID string
---@param targetInfo SmartRes2_ResTargetInfo|nil
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

---@param targetGUID string
---@param targetInfo SmartRes2_ResTargetInfo
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

---@param callback string
---@param casterGUID string
---@param targetGUID string
---@param casterInfo SmartRes2_ResCastInfo
---@param targetInfo SmartRes2_ResTargetInfo
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

---@param callback string
---@param casterGUID string
---@param targetGUID string
---@param casterInfo SmartRes2_ResCastInfo|nil
---@param targetInfo SmartRes2_ResTargetInfo|nil
function module:OnSingleResCastStopped(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = nil

	if targetGUID then
		collisionNotified[GetCollisionKey(casterGUID, targetGUID)] = nil
	end
end

---@param callback string
---@param casterGUID string
---@param targetGUID string
---@param casterInfo SmartRes2_ResCastInfo
---@param targetInfo SmartRes2_ResTargetInfo
function module:OnSingleResCastFinished(callback, casterGUID, targetGUID, casterInfo, targetInfo)
	activeSingleCasts[casterGUID] = nil

	if targetGUID then
		collisionNotified[GetCollisionKey(casterGUID, targetGUID)] = nil
	end
end

---@param callback string
---@param casterGUID string
---@param casterInfo SmartRes2_ResCastInfo
function module:OnMassResCastStarted(callback, casterGUID, casterInfo)
	if not db then
		return
	end

	if casterGUID == PLAYER_GUID then
		self:SendConfiguredMessage(self:GetMassResMessage(), db.massResOutput)
		addon:NotifySelf(L["I am casting mass resurrection."])
	end
end

---@param callback string
---@param casterGUID string
---@param casterInfo SmartRes2_ResCastInfo|nil
function module:OnMassResCastStopped(callback, casterGUID, casterInfo)
end

---@param callback string
---@param casterGUID string
---@param casterInfo SmartRes2_ResCastInfo
function module:OnMassResCastFinished(callback, casterGUID, casterInfo)
end

---@param callback string
---@param targetGUID string
---@param targetInfo SmartRes2_ResTargetInfo
function module:OnFastestResChanged(callback, targetGUID, targetInfo)
	self:RefreshCollisionNotifications(targetGUID, targetInfo)
end