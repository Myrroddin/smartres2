-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Chat
--
-- Responsibilities:
-- - Initialize the Chat settings namespace and lifecycle.
-- - Announce the player's single-target and mass resurrection casts.
-- - Coordinate one collision-warning sender among eligible SmartRes2 clients.
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
local string_byte = string.byte
local string_find = string.find
local string_format = string.format
local string_match = string.match
local string_sub = string.sub
local table_wipe = table.wipe
local UnitClassBase = UnitClassBase
local UnitGUID = UnitGUID
local UNKNOWN = UNKNOWN
local After = C_Timer.After

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
---@class Chat: AceAddon, AceEvent-3.0, AceConsole-3.0, AceComm-3.0, LibResInfo-2.0
---@field db AceDBObject-3.0
local module = addon:NewModule("Chat", "AceComm-3.0")

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
			["A moment of silence for the fallen. Okay, that's enough. Everybody up!"] = true,
			["A raid that wipes together gets resurrected together."] = true,
			["According to the combat log, the entire group made a small tactical error."] = true,
			["Afterlife capacity reached. Returning the whole group to sender."] = true,
			["Alexstrasza sends her regards and several replacement health bars."] = true,
			["All aboard the resurrection express! Next stop: being alive."] = true,
			["All dead party members have been upgraded to mostly alive."] = true,
			["All your resurrections are belong to me!"] = true,
			["Ancestral spirits, please return this raid in working order."] = true,
			["Another wipe successfully converted into a learning opportunity."] = true,
			["Apparently the graveyard has a group-booking discount. Let's not use it."] = true,
			["Arise, champions! There are still mechanics left to misunderstand."] = true,
			["Azeroth called. It wants all of its heroes back."] = true,
			["Back by popular demand: everyone."] = true,
			["Behold, the rarest raid mechanic of all: recovery."] = true,
			["Blame the healer for this mass res. Oh, wait..."] = true,
			["Brace yourselves. Life is coming."] = true,
			["Bwonsamdi checked the guest list and sent everyone back."] = true,
			["By process of elimination, at least one of you must know what went wrong."] = true,
			["Casting mass resurrection is like doing a jigsaw puzzle without the picture. I hope everyone's parts are correct!"] = true,
			["Cleanup on aisle Azeroth. Resurrecting the raid."] = true,
			["Consider this a group refund from the afterlife."] = true,
			["Corpse run cancelled due to excessive customer complaints."] = true,
			["Death is merely a setback. A raid-wide, embarrassingly visible setback."] = true,
			["Deathwing broke the world; you lot merely broke the pull. This is fixable."] = true,
			["Defibrillating the entire raid. Stand clear."] = true,
			["Did someone order a large resurrection with extra health bars?"] = true,
			["Eonar reviewed our situation and prescribed more life."] = true,
			["Everybody stay calm. I am restoring the group."] = true,
			["Everyone gets another chance. Please use it responsibly."] = true,
			["Fine, I'll put the raid back where I found it."] = true,
			["From zero health to hero health in one convenient cast."] = true,
			["Good news, everyone! The wipe has been temporarily reversed."] = true,
			["Graveyard shift is over. Back to the encounter."] = true,
			["Great news: none of you have to explain that corpse run."] = true,
			["Group wipe recovery protocol initiated."] = true,
			["Heroes never die permanently when the healer remembers this button."] = true,
			["Hold onto your souls. Reassembly is about to begin."] = true,
			["I am casting mass resurrection."] = true,
			["I am pulling everyone back from the brink. Try not to sprint back there."] = true,
			["I came, I saw, I resurrected everybody."] = true,
			["I found the whole group in the lost and found. Resurrecting now."] = true,
			["I have one spell and ninety-nine problems. Most of them are corpses."] = true,
			["I reject this wipe and substitute a living raid."] = true,
			["If anyone asks, this pull was merely a rehearsal."] = true,
			["If this works, please pretend the wipe never happened."] = true,
			["If you are seeing this mass resurrection message, my cast time is the fastest."] = true,
			["In case of total party failure, break glass and cast mass resurrection."] = true,
			["It's dangerous to go alone. Take the rest of the resurrected raid."] = true,
			["Keep calm. Your regularly scheduled pulse will resume shortly."] = true,
			["Khadgar opened a portal back to life. Please exit in an orderly fashion."] = true,
			["Life, uh, finds a raid."] = true,
			["Make way! A large shipment of second chances is arriving."] = true,
			["Mass resurrection is just a raid reset with better customer service."] = true,
			["Mass resurrection: because apparently one corpse was not enough."] = true,
			["Nobody move. I am trying to remember which limbs belong to whom."] = true,
			["Not today, death. We still have consumables to waste."] = true,
			["Of all the random mass resurrection messages, I get this one!?"] = true,
			["On your feet, champions. The floor has had enough attention."] = true,
			["Patch notes: resolved an issue where the entire raid remained dead."] = true,
			["Please accept your complimentary return to the mortal plane."] = true,
			["Please keep all limbs inside the resurrection spell until casting is complete."] = true,
			["Raid repair in progress. Percussive maintenance may be required."] = true,
			["Rebooting the party. Please do not unplug the healer."] = true,
			["Reports of our total defeat have been greatly exaggerated."] = true,
			["Resurrection, but make it efficient."] = true,
			["Rise and shine! Mostly rise; the shine is optional."] = true,
			["Rise, champions. The repair bill is not done with you yet."] = true,
			["Somehow, the entire raid returned."] = true,
			["Spirit Healers hate this one simple spell."] = true,
			["Stand by while the Bronze dragonflight edits the last pull."] = true,
			["Terenas Menethil taught me mass resurrection. All of you benefit from his knowledge."] = true,
			["The afterlife called. It cannot accommodate parties of this size."] = true,
			["The afterlife denied your application. Welcome back."] = true,
			["The Bronze dragonflight assures me that the wipe never happened."] = true,
			["The encounter is not over until the last repair bill is paid."] = true,
			["The floor has enough friends. Everybody get up."] = true,
			["The floor has released its claim on you. For now."] = true,
			["The Kyrian misplaced an entire raid's paperwork. Lucky us."] = true,
			["The Light has reviewed your appeal and approved a group do-over."] = true,
			["The raid leader requested everyone alive, or at least convincingly upright."] = true,
			["The Red dragonflight recommends applying life directly to the affected raid."] = true,
			["The wipe was brought to you by gravity, fire, and poor decisions."] = true,
			["There are two kinds of raiders: the living and the about-to-be-resurrected."] = true,
			["This is a mass resurrection, not a mass absolution. Remember the mechanics."] = true,
			["This mass resurrection is brought to you by the Light."] = true,
			["This spell restores health, mana, and absolutely no dignity."] = true,
			["Today's raid forecast: scattered corpses followed by widespread resurrection."] = true,
			["Victory is still possible. Plausible might be asking too much."] = true,
			["Wake up, everyone. We have a world to save and loot to vendor."] = true,
			["We can rebuild this raid. Better, stronger, and slightly more cautious."] = true,
			["We have enough ghosts for one night. Returning everyone to active duty."] = true,
			["Welcome back to life. Please keep your hands inside the encounter."] = true,
			["What's better than a resurrection spell? A mass resurrection spell!"] = true,
			["When everyone is special, everyone gets a resurrection."] = true,
			["Who ordered the family-sized resurrection?"] = true,
			["Wipe detected. Deploying emergency raid recovery."] = true,
			["You are all cordially invited to stop being dead."] = true,
			["You get a res, and you, and you. Mass resurrection for everybody!"] = true,
			["Your regularly scheduled raid has been renewed for another pull."] = true,
		},
	},
}

local UNKNOWN_TARGET_GUID = "UNKNOWN"
local COLLISION_COMM_PREFIX = "SmartRes2C"
local COLLISION_COMM_VERSION = "1"
local COLLISION_ELECTION_DELAY = 0.4
local COLLISION_RECORD_TTL = 10

---@type table
local db
local activeSingleCasts = {}
local collisionNotified = {}
local collisionElections = {}
local randomSingleMessages = {}
local randomMassMessages = {}
local electionGeneration = 0

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
	self:RegisterComm(COLLISION_COMM_PREFIX, "OnCollisionCommReceived")
	self:RegisterCallback("ResCast_Started", "OnSingleResCastStarted")
	self:RegisterCallback("ResCast_Stopped", "OnSingleResCastStopped")
	self:RegisterCallback("ResCast_Finished", "OnSingleResCastFinished")
	self:RegisterCallback("MassResCast_Started", "OnMassResCastStarted")
	self:RegisterCallback("FastestRes_Changed", "OnFastestResChanged")
	self:RegisterCallback("ResTargetGUID_Resolved", "OnResTargetGUIDResolved")
end

function module:OnDisable()
	self:UnregisterComm(COLLISION_COMM_PREFIX)
	self:UnregisterAllResInfoCallbacks()

	electionGeneration = electionGeneration + 1
	table_wipe(activeSingleCasts)
	table_wipe(collisionNotified)
	table_wipe(collisionElections)
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
		return false
	end

	message = string_sub(message, 1, 255)

	if chatType == "WHISPER" then
		if allowWhisper then
			SendChatMessage(message, "WHISPER", nil, whisperTarget)
			return true
		end
	else
		SendChatMessage(message, chatType)
		return true
	end

	return false
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

local function GetElectionKey(casterGUID, targetGUID, fastestCasterGUID)
	return casterGUID .. "\031" .. targetGUID .. "\031" .. fastestCasterGUID
end

local function IsGroupMemberGUID(memberGUID)
	if not memberGUID then
		return false
	end

	if memberGUID == addon.PLAYER_GUID then
		return true
	end

	local numGroupMembers = GetNumGroupMembers()

	if IsInRaid() then
		for index = 1, numGroupMembers do
			if UnitGUID("raid" .. index) == memberGUID then
				return true
			end
		end
	else
		for index = 1, numGroupMembers - 1 do
			if UnitGUID("party" .. index) == memberGUID then
				return true
			end
		end
	end

	return false
end

local function GetGroupMemberGUIDByName(memberName)
	local exactMatchedGUID
	local shortMatchedGUID
	local shortMatchIsAmbiguous = false
	local memberShortName = string_match(memberName, "^[^-]+")
	local numGroupMembers = GetNumGroupMembers()

	local function CheckGUID(memberGUID)
		if not memberGUID then
			return
		end

		local fullName = addon:GetUnitNameFromGUID(memberGUID, true)

		if fullName == memberName then
			exactMatchedGUID = memberGUID
			return true
		end

		if addon:GetUnitNameFromGUID(memberGUID, false) == memberShortName then
			if shortMatchedGUID and shortMatchedGUID ~= memberGUID then
				shortMatchIsAmbiguous = true
			else
				shortMatchedGUID = memberGUID
			end
		end
	end

	if CheckGUID(addon.PLAYER_GUID) then
		return exactMatchedGUID
	end

	if IsInRaid() then
		for index = 1, numGroupMembers do
			if CheckGUID(UnitGUID("raid" .. index)) then
				return exactMatchedGUID
			end
		end
	else
		for index = 1, numGroupMembers - 1 do
			if CheckGUID(UnitGUID("party" .. index)) then
				return exactMatchedGUID
			end
		end
	end

	if not shortMatchIsAmbiguous then
		return shortMatchedGUID
	end
end

local function IsCollisionSenderEligible(targetGUID)
	-- The Chat module only receives coordination traffic while it and SmartRes2
	-- are enabled. Respect the remaining output setting here, and never elect the
	-- resurrection target to emit text addressed to a caster.
	return db.notifyCollision ~= "NONE" and addon.PLAYER_GUID ~= targetGUID
end

local function GetElectionScore(electionKey, candidateGUID)
	local value = 5381
	local source = electionKey .. candidateGUID

	for index = 1, #source do
		value = (value * 33 + string_byte(source, index)) % 2147483647
	end

	return value
end

local function GetElectedSender(election)
	local electedGUID
	local electedScore

	for candidateGUID in pairs(election.candidates) do
		local score = GetElectionScore(election.key, candidateGUID)

		if not electedScore
			or score < electedScore
			or (score == electedScore and candidateGUID < electedGUID)
		then
			electedGUID = candidateGUID
			electedScore = score
		end
	end

	return electedGUID
end

local function SendCollisionComm(opcode, casterGUID, targetGUID, fastestCasterGUID)
	local distribution = GetGroupChatType()

	if not distribution then
		return false
	end

	module:SendCommMessage(
		COLLISION_COMM_PREFIX,
		string_format("%s\t%s\t%s\t%s\t%s", opcode, COLLISION_COMM_VERSION, casterGUID, targetGUID, fastestCasterGUID),
		distribution,
		nil,
		"ALERT"
	)

	return true
end

local function ExpireCollisionElection(electionKey, election)
	if collisionElections[electionKey] ~= election then
		return
	end

	collisionElections[electionKey] = nil
	collisionNotified[GetCollisionKey(election.casterGUID, election.targetGUID)] = nil
end

local function FinishCollisionElection(electionKey, election)
	if collisionElections[electionKey] ~= election or election.sent then
		return
	end

	if GetElectedSender(election) ~= addon.PLAYER_GUID then
		return
	end

	local targetName = GetTargetName(election.targetGUID)
	local message = string_format(L["Your resurrection of %s will not finish first."], targetName)

	if SendConfiguredMessage(message, db.notifyCollision, election.casterGUID) then
		election.sent = true
		SendCollisionComm("S", election.casterGUID, election.targetGUID, election.fastestCasterGUID)
	end
end

local function GetOrCreateCollisionElection(casterGUID, targetGUID, fastestCasterGUID)
	local electionKey = GetElectionKey(casterGUID, targetGUID, fastestCasterGUID)
	local election = collisionElections[electionKey]

	if election then
		return election
	end

	election = {
		key = electionKey,
		casterGUID = casterGUID,
		targetGUID = targetGUID,
		fastestCasterGUID = fastestCasterGUID,
		candidates = {},
		sent = false,
		generation = electionGeneration,
	}
	collisionElections[electionKey] = election
	collisionNotified[GetCollisionKey(casterGUID, targetGUID)] = true

	After(COLLISION_ELECTION_DELAY, function()
		if election.generation == electionGeneration then
			FinishCollisionElection(electionKey, election)
		end
	end)

	After(COLLISION_RECORD_TTL, function()
		if election.generation == electionGeneration then
			ExpireCollisionElection(electionKey, election)
		end
	end)

	return election
end

local function JoinCollisionElection(election)
	if not IsCollisionSenderEligible(election.targetGUID) or election.candidates[addon.PLAYER_GUID] then
		return
	end

	election.candidates[addon.PLAYER_GUID] = true
	SendCollisionComm("C", election.casterGUID, election.targetGUID, election.fastestCasterGUID)
end

function module:OnCollisionCommReceived(prefix, message, distribution, sender)
	if prefix ~= COLLISION_COMM_PREFIX or type(message) ~= "string" then
		return
	end

	local opcode, protocolVersion, casterGUID, targetGUID, fastestCasterGUID = string_match(
		message,
		"^([CPS])\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$"
	)

	if protocolVersion ~= COLLISION_COMM_VERSION then
		return
	end

	local senderGUID = GetGroupMemberGUIDByName(sender)

	if not senderGUID
		or not IsGroupMemberGUID(casterGUID)
		or not IsGroupMemberGUID(targetGUID)
		or not IsGroupMemberGUID(fastestCasterGUID)
	then
		return
	end

	local electionKey = GetElectionKey(casterGUID, targetGUID, fastestCasterGUID)
	local election = collisionElections[electionKey]

	-- Proposals create elections. Candidate and completion packets only update an
	-- election that was proposed locally or received first, so a stray packet
	-- cannot manufacture collision state on its own.
	if not election then
		if opcode ~= "P" then
			return
		end

		election = GetOrCreateCollisionElection(casterGUID, targetGUID, fastestCasterGUID)
	end

	if opcode == "S" then
		election.candidates[senderGUID] = true
		election.sent = true
		return
	end

	if opcode == "C" then
		election.candidates[senderGUID] = true
	end

	if election.sent then
		SendCollisionComm("S", casterGUID, targetGUID, fastestCasterGUID)
		return
	end

	JoinCollisionElection(election)
end

local function ClearCollisionNotification(casterGUID, targetGUID)
	if not IsKnownTargetGUID(targetGUID) then
		return
	end

	local collisionKey = GetCollisionKey(casterGUID, targetGUID)
	collisionNotified[collisionKey] = nil

	for electionKey, election in pairs(collisionElections) do
		if election.casterGUID == casterGUID and election.targetGUID == targetGUID then
			collisionElections[electionKey] = nil
		end
	end
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
	if not IsCollision(casterGUID, targetGUID, targetInfo) then
		return
	end

	local collisionKey = GetCollisionKey(casterGUID, targetGUID)

	if collisionNotified[collisionKey] then
		return
	end

	local fastestCasterGUID = targetInfo.fastestCasterGUID
	local election = GetOrCreateCollisionElection(casterGUID, targetGUID, fastestCasterGUID)

	SendCollisionComm("P", casterGUID, targetGUID, fastestCasterGUID)
	JoinCollisionElection(election)
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