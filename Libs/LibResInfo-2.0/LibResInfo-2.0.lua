--[[--------------------------------------------------------------------
LibResInfo-2.0
Revision: @project-revision@
Date: @project-date-iso@

CLEU-free resurrection tracking library.

Tracks:
- single-target resurrection casts
- mass resurrection casts
- completed resurrection targets becoming alive
- self-resurrection options
- external resurrection requests received by the player

Core rules:
- Caster identity must be a real GUID or the event is ignored.
- Target identity is GUID-first, but may be "UNKNOWN" when Blizzard does
  not expose enough data to resolve it.
- Spell and aura logic is ID-based. Names are used only to resolve unit
  identities when Blizzard does not provide a GUID directly.
----------------------------------------------------------------------]]

assert(LibStub, "LibResInfo-2.0 requires LibStub")
assert(LibStub("CallbackHandler-1.0", true), "LibResInfo-2.0 requires CallbackHandler-1.0")

---@class LibResInfo-2.0
---@field RegisterCallback fun(target: table, eventName: LibResInfoCallbackName, method: string, arg?: any)
---@field UnregisterCallback fun(target: table, eventName: LibResInfoCallbackName)
---@field UnregisterAllResInfoCallbacks fun(target: table)
local lib = LibStub:NewLibrary("LibResInfo-2.0", 7)
if not lib then return end

-- Callback names accepted by RegisterCallback and UnregisterCallback.
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib,
	"RegisterCallback",
	"UnregisterCallback",
	"UnregisterAllResInfoCallbacks"
)

lib.embeds = lib.embeds or {}

---@class LibResInfoSelfResurrectOption
---@field spellID? integer
---@field itemID? integer
---@field auraInstanceID? integer
---@field expirationTime? number

---@alias LibResInfoCallbackName
---| "ResCast_Started"
---| "ResCast_Stopped"
---| "ResCast_Finished"
---| "MassResCast_Started"
---| "MassResCast_Stopped"
---| "MassResCast_Finished"
---| "FastestRes_Changed"
---| "ResTargetGUID_Resolved"
---| "ResTargetGUID_HasResOffer"
---| "ResTargetGUID_IsAlive"
---| "ResTargetGUID_WaitingTimeExpired"
---| "UnitSelfRes_Available"
---| "UnitSelfRes_Consumed"

-- -------------------------------------------------------------------
-- Event frame
-- -------------------------------------------------------------------

local frame = CreateFrame("Frame")
local eventHandlers = {}

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = eventHandlers[event]
	if handler then
		handler(...)
	end
end)

frame:RegisterEvent("PLAYER_LOGIN")

-- -------------------------------------------------------------------
-- WoW API
-- -------------------------------------------------------------------

local After = C_Timer.After
local canaccessvalue = canaccessvalue or function() return true end
local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local GetCorpseRecoveryDelay = GetCorpseRecoveryDelay
local GetNamePlates = C_NamePlate.GetNamePlates
local GetNumGroupMembers = GetNumGroupMembers
local GetSelfResurrectOptions = C_DeathInfo.GetSelfResurrectOptions
local GetTime = GetTime
local GetUnitAuraBySpellID = C_UnitAuras.GetUnitAuraBySpellID
local InCombatLockdown = InCombatLockdown
local IsInGroup = IsInGroup
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local IsPlayerNeutral = IsPlayerNeutral
local LE_EXPANSION_CLASSIC = LE_EXPANSION_CLASSIC
local LE_EXPANSION_LEVEL_CURRENT = LE_EXPANSION_LEVEL_CURRENT
local next = next
local pairs = pairs
local type = type
local UnitAffectingCombat = UnitAffectingCombat
local UnitCastingInfo = UnitCastingInfo
local UnitExists = UnitExists
local UnitFactionGroup = UnitFactionGroup
local UnitGUID = UnitGUID
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitHealth = UnitHealth
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitName = UnitName
local UnitSpellTargetName = UnitSpellTargetName
local UnitTokenFromGUID = UnitTokenFromGUID
local wipe = table.wipe

-- -------------------------------------------------------------------
-- Constants
-- -------------------------------------------------------------------

local isStandard = (WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) and (LE_EXPANSION_LEVEL_CURRENT > LE_EXPANSION_CLASSIC)
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local PLAYER_GUID = UnitGUID("player")
local REVIVE_PET_SPELL_ID = 982
local RES_OFFER_CONFIRMATION_TIMEOUT = 2
local RES_WAITING_TIMEOUT = 60
local TERMINAL_CAST_RETENTION = 10
local UNKNOWN_TARGET_CLEANUP_TIMEOUT = 10
local UNKNOWN_TARGET_GUID = "UNKNOWN"

-- -------------------------------------------------------------------
-- Internal state
-- -------------------------------------------------------------------

-- Active single-target resurrection casts, keyed by caster GUID.
local resCasterInfo = {}

-- Active mass resurrection casts, keyed by caster GUID.
local massResCasterInfo = {}

-- Active single-target resurrection casts, keyed by target GUID, then caster GUID.
-- The UNKNOWN key is a temporary staging area for unresolved casts and is not
-- treated as a real target for fastest-caster calculations.
local resTargetInfo = {}

-- Expected or confirmed resurrection offers, keyed by target GUID and expiry.
local resOfferExpireTimes = {}

-- Mass resurrection affected targets, keyed by caster GUID, then target GUID.
local massResTargetGUIDs = {}

-- Self-resurrection options, keyed by unit GUID, then option key.
local selfResInfo = {}

-- Player resurrection attempt reported by UNIT_SPELLCAST_SENT while waiting
-- for UNIT_SPELLCAST_START or UNIT_SPELLCAST_SUCCEEDED to confirm its timing.
local playerSentCastInfo

-- Engineering activations which completed their cast but still need a local
-- resurrection-offer confirmation. Entries are short-lived and keyed by caster
-- GUID so the existing active cast tables remain available to callbacks.
local pendingEngineeringCasts = {}

-- Recently completed casts retained briefly so RESURRECT_REQUEST can correlate
-- its inviter with the caster and spell after the active cast was removed.
local recentFinishedResCasts = {}

-- Cast GUIDs which have already reached a success or failure outcome. Blizzard
-- may report more than one terminal event for the same physical cast; retaining
-- the GUID prevents a late duplicate from recreating state after cleanup.
local terminalCastGUIDs = {}

-- Cast-bar sequence IDs which have already reached a terminal outcome, keyed
-- first by caster GUID. This remains empty for casts without castBarID.
local terminalCastBarIDs = {}

-- -------------------------------------------------------------------
-- Spell tables
-- -------------------------------------------------------------------

local SINGLE_TARGET_RES_SPELLS = {
	-- Priest
	[2006]		= true,		-- Resurrection Rank 1
	[2010]		= true,		-- Resurrection Rank 2
	[10880]		= true,		-- Resurrection Rank 3
	[10881]		= true,		-- Resurrection Rank 4
	[20770]		= true,		-- Resurrection Rank 5
	[25435]		= true,		-- Resurrection Rank 6
	[48171]		= true,		-- Resurrection Rank 7

	-- Paladin
	[7328]		= true,		-- Redemption Rank 1
	[10322]		= true,		-- Redemption Rank 2
	[10324]		= true,		-- Redemption Rank 3
	[20772]		= true,		-- Redemption Rank 4
	[20773]		= true,		-- Redemption Rank 5
	[48949]		= true,		-- Redemption Rank 6
	[48950]		= true,		-- Redemption Rank 7
	[391054]	= true,		-- Intercession

	-- Shaman
	[2008]		= true,		-- Ancestral Spirit Rank 1
	[20609]		= true,		-- Ancestral Spirit Rank 2
	[20610]		= true,		-- Ancestral Spirit Rank 3
	[20776]		= true,		-- Ancestral Spirit Rank 4
	[20777]		= true,		-- Ancestral Spirit Rank 5
	[25590]		= true,		-- Ancestral Spirit Rank 6
	[49277]		= true,		-- Ancestral Spirit Rank 7

	-- Druid
	[20484]		= true,		-- Rebirth Rank 1
	[20739]		= true,		-- Rebirth Rank 2
	[20742]		= true,		-- Rebirth Rank 3
	[20747]		= true,		-- Rebirth Rank 4
	[20748]		= true,		-- Rebirth Rank 5
	[26994]		= true,		-- Rebirth Rank 6
	[48477]		= true,		-- Rebirth Rank 7
	[50769]		= true,		-- Revive

	-- Monk
	[115178]	= true,		-- Resuscitate

	-- Hunter
	[REVIVE_PET_SPELL_ID] = true,	-- Revive Pet

	-- Evoker
	[361227]	= true,		-- Return

	-- Death Knight
	[61999]		= true,		-- Raise Ally

	-- Engineering
	[8342]		= true,		-- Goblin Jumper Cables
	[22999]		= true,		-- Goblin Jumper Cables XL
	[54732]		= true,		-- Gnomish Army Knife
	[164729]	= true,		-- Ultimate Gnomish Army Knife
	[345130]	= true,		-- Disposable Spectrophasic Reanimator
	[384893]	= true,		-- Convincingly Realistic Jumper Cables
	[385403]	= true,		-- Arclight Vital Correctors
	[385404]	= true,		-- Arclight Vital Correctors item effect

	-- Combat resurrection
	[20707]		= true,		-- Soulstone Resurrection Rank 1
	[20762]		= true,		-- Soulstone Resurrection Rank 2
	[20763]		= true,		-- Soulstone Resurrection Rank 3
	[20764]		= true,		-- Soulstone Resurrection Rank 4
	[20765]		= true,		-- Soulstone Resurrection Rank 5
	[27239]		= true,		-- Soulstone Resurrection Rank 6
	[47883]		= true,		-- Soulstone Resurrection Rank 7
	[267922]	= true,		-- Eternal Guardian (hunter pet resurrection)

	-- Self-resurrection spells; availability is tracked separately.
	[20608]		= true,		-- Reincarnation
	[18976]		= true,		-- Self Resurrection
	[23683]		= true,		-- Twisting Nether
	[23700]		= true,		-- Twisting Nether
	[23701]		= true,		-- Twisting Nether
	[148623]	= true,		-- Cauterizing Core
	[280007]	= true,		-- Drust Soulcatcher

	-- World objects
	[187777]	= true,		-- Reawaken (Brazier of Awakening)
	[199119]	= true,		-- Failure Detection Aura (Failure Detection Pylon)
	[339643]	= true,		-- Gift of Life (Mi'kai's Deathscythe)
}

-- Engineering resurrection devices can complete their activation without
-- producing a resurrection offer. Their casts remain pending briefly after
-- UNIT_SPELLCAST_SUCCEEDED and finish only when the target confirms an offer.
local ENGINEERING_RES_SPELLS = {
	[8342]		= true,		-- Goblin Jumper Cables
	[22999]		= true,		-- Goblin Jumper Cables XL
	[54732]		= true,		-- Gnomish Army Knife
	[164729]	= true,		-- Ultimate Gnomish Army Knife
	[345130]	= true,		-- Disposable Spectrophasic Reanimator
	[384893]	= true,		-- Convincingly Realistic Jumper Cables
	[385403]	= true,		-- Arclight Vital Correctors
	[385404]	= true,		-- Arclight Vital Correctors item effect
}

local MASS_RES_SPELLS = {
	-- Priest
	[212036]	= true,		-- Mass Resurrection

	-- Druid
	[212040]	= true,		-- Revitalize

	-- Shaman
	[212048]	= true,		-- Ancestral Vision

	-- Monk
	[212051]	= true,		-- Reawaken

	-- Paladin
	[212056]	= true,		-- Absolution

	-- Evoker
	[361178]	= true,		-- Mass Return

	-- Guild Perk (Mists)
	[83968]		= true,		-- Mass Resurrection
}

local SELF_RES_AURAS = {
	[20707]		= true,		-- Soulstone Resurrection Rank 1
	[20762]		= true,		-- Soulstone Resurrection Rank 2
	[20763]		= true,		-- Soulstone Resurrection Rank 3
	[20764]		= true,		-- Soulstone Resurrection Rank 4
	[20765]		= true,		-- Soulstone Resurrection Rank 5
	[27239]		= true,		-- Soulstone Resurrection Rank 6
	[47883]		= true,		-- Soulstone Resurrection Rank 7
	[20608]		= true,		-- Reincarnation
	[23683]		= true,		-- Twisting Nether (core self-res spell)
	[23700]		= true,		-- Twisting Nether (Darkmoon Card proc effect)
	[23701]		= true,		-- Twisting Nether (Darkmoon Card passive aura)
	[148623]	= true,		-- Cauterizing Core
	[280007]	= true,		-- Drust Soulcatcher
}

local events = {
	["INCOMING_RESURRECT_CHANGED"]	= true,
	["PLAYER_ALIVE"]				= true,
	["PLAYER_UNGHOST"]				= true,
	["RESURRECT_REQUEST"]			= true,
	["UNIT_AURA"]					= true,
	["UNIT_HEALTH"]					= true,
	["UNIT_SPELLCAST_FAILED"]		= true,
	["UNIT_SPELLCAST_FAILED_QUIET"]	= true,
	["UNIT_SPELLCAST_INTERRUPTED"]	= true,
	["UNIT_SPELLCAST_SENT"]			= true,
	["UNIT_SPELLCAST_START"]		= true,
	["UNIT_SPELLCAST_SUCCEEDED"]	= true,
}

-- -------------------------------------------------------------------
-- Shared helpers
-- -------------------------------------------------------------------

-- WoW can mark API and event values as secret on any game version. Secret
-- values cannot be compared, indexed, concatenated, or used in arithmetic by
-- addon code. Clients without canaccessvalue retain their traditional
-- non-secret behavior through the fallback above.

local function IsUsableUnitIdentifier(unitID)
	return canaccessvalue(unitID)
	and type(unitID) == "string"
	and unitID ~= ""
	and unitID:lower() ~= "none"
end

local function GetAccessibleUnitGUID(unitID)
	if not IsUsableUnitIdentifier(unitID) then return end

	local unitGUID = UnitGUID(unitID)
	if not canaccessvalue(unitGUID) then return end

	return unitGUID
end

local function GetAccessibleSpellTargetName(unitID)
	if not canaccessvalue(unitID) then return end

	local targetName = UnitSpellTargetName(unitID)
	if not canaccessvalue(targetName) then return end

	return targetName
end

local function GetAccessibleUnitTokenFromGUID(unitGUID)
	if not canaccessvalue(unitGUID) or not unitGUID then return end

	local unitID = UnitTokenFromGUID(unitGUID)
	if not canaccessvalue(unitID) then return end

	return unitID
end

local function GetAccessibleUnitName(unitID)
	if not canaccessvalue(unitID) then return end

	local unitName, unitRealm = UnitName(unitID)
	if not canaccessvalue(unitName) or not canaccessvalue(unitRealm) then return end

	return unitName, unitRealm
end

local function IsAccessibleUnitDeadOrGhost(unitID)
	if not canaccessvalue(unitID) then return end

	local isDeadOrGhost = UnitIsDeadOrGhost(unitID)
	if not canaccessvalue(isDeadOrGhost) then return end

	return isDeadOrGhost
end

local function HasAccessibleIncomingResurrection(unitID)
	if not canaccessvalue(unitID) then return end

	local hasIncomingResurrection = UnitHasIncomingResurrection(unitID)
	if not canaccessvalue(hasIncomingResurrection) then return end

	return hasIncomingResurrection
end

local function GetAccessibleUnitHealth(unitID)
	if not canaccessvalue(unitID) then return end

	local health = UnitHealth(unitID)
	if not canaccessvalue(health) then return end

	return health
end

-- Normal spellcast lifecycle tracking belongs only to the player and current
-- group. Retail also emits these events for nameplates, whose cast payloads
-- can be secret and are unrelated to group resurrection state. Out-of-group
-- resurrection offers are handled separately by RESURRECT_REQUEST.
local function IsTrackedSpellcastUnit(unitID)
	if not canaccessvalue(unitID) then return false end
	if unitID == "player" then return true end

	return unitID:find("^party%d+$") ~= nil or unitID:find("^raid%d+$") ~= nil
end

-- Callback payload tables are built from mutable internal state.
-- Return nil for empty tables so consumers do not receive meaningless
-- placeholders after cleanup or defensive normalization.
local function NormalizeCallbackTable(info)
	if info and not next(info) then
		return nil
	end

	return info
end

-- Merge partial spellcast data without overwriting better information that
-- may have arrived from an earlier event.
local function SetIfMissing(info, key, value)
	if not canaccessvalue(value) then return end

	if info[key] == nil then
		info[key] = value
	end
end

-- Copy optional Blizzard fields only when they are present. This keeps
-- public info tables sparse and avoids false "field exists but is nil" noise.
local function SetIfPresent(info, key, value)
	if not canaccessvalue(value) then return end

	if value ~= nil then
		info[key] = value
	end
end

-- A non-nil castBarID is the strongest available match for casts which display
-- a cast bar. The field is optional, so retain cast-GUID matching as the
-- universal fallback.
local function CastMatches(casterInfo, castGUID, castBarID)
	if not canaccessvalue(castGUID) or not canaccessvalue(castBarID) then return false end

	if casterInfo.castBarID and castBarID then
		return casterInfo.castBarID == castBarID
	end

	return not casterInfo.castGUID or not castGUID or casterInfo.castGUID == castGUID
end

local function IsTerminalCast(casterGUID, castGUID, castBarID)
	if canaccessvalue(castGUID) and castGUID and terminalCastGUIDs[castGUID] then
		return true
	end

	if not canaccessvalue(casterGUID) or not canaccessvalue(castBarID) then return end

	return casterGUID and castBarID
	and terminalCastBarIDs[casterGUID]
	and terminalCastBarIDs[casterGUID][castBarID]
end

local function MarkTerminalCast(casterGUID, castGUID, castBarID)
	if canaccessvalue(castGUID) and castGUID then
		local marker = {}
		terminalCastGUIDs[castGUID] = marker

		After(TERMINAL_CAST_RETENTION, function()
			if terminalCastGUIDs[castGUID] == marker then
				terminalCastGUIDs[castGUID] = nil
			end
		end)
	end

	if not canaccessvalue(casterGUID) or not canaccessvalue(castBarID) then return end
	if not casterGUID or not castBarID then return end

	terminalCastBarIDs[casterGUID] = terminalCastBarIDs[casterGUID] or {}

	local casterCastBarIDs = terminalCastBarIDs[casterGUID]
	local marker = {}
	casterCastBarIDs[castBarID] = marker

	After(TERMINAL_CAST_RETENTION, function()
		if casterCastBarIDs[castBarID] ~= marker then return end

		casterCastBarIDs[castBarID] = nil

		if not next(casterCastBarIDs) and terminalCastBarIDs[casterGUID] == casterCastBarIDs then
			terminalCastBarIDs[casterGUID] = nil
		end
	end)
end

-- UnitCastingInfo returns cast times in milliseconds. LibResInfo exposes
-- seconds, with endTime comparable to GetTime().
local function GetCastTimes(startTimeMs, endTimeMs)
	local castTime = (startTimeMs and endTimeMs) and ((endTimeMs - startTimeMs) / 1000) or 0
	local endTime = endTimeMs and (endTimeMs / 1000) or GetTime()

	return castTime, endTime
end

-- ResTargetInfo tables also store metadata fields such as targetGUID and
-- fastestCasterGUID. Only nested caster tables count as active entries.
local function HasTableEntries(info)
	if not info then return end

	for _, value in pairs(info) do
		if type(value) == "table" then
			return true
		end
	end
end

-- A known target is a real GUID. UNKNOWN is useful for callback reporting and
-- temporary staging, but must not be treated as a valid unit identity.
local function IsKnownTargetGUID(targetGUID)
	return targetGUID and targetGUID ~= UNKNOWN_TARGET_GUID
end

-- Retain only the most recent completed resurrection cast per caster. The
-- target's RESURRECT_REQUEST can arrive after the caster's active state was
-- removed, so this short correlation window preserves caster and spell IDs
-- without keeping resolved cast state for the whole login session.
local function StoreRecentFinishedResCast(casterGUID, targetGUID, spellID)
	if not casterGUID then return end

	local recentInfo = {
		spellID = spellID,
		targetGUID = targetGUID,
	}

	recentFinishedResCasts[casterGUID] = recentInfo

	After(TERMINAL_CAST_RETENTION, function()
		if recentFinishedResCasts[casterGUID] == recentInfo then
			recentFinishedResCasts[casterGUID] = nil
		end
	end)
end

local function ClearRecentFinishedResCastsForTarget(targetGUID)
	if not targetGUID then return end

	for casterGUID, recentInfo in pairs(recentFinishedResCasts) do
		if recentInfo.targetGUID == targetGUID then
			recentFinishedResCasts[casterGUID] = nil
		end
	end
end

-- Self-res spells and effects are present while their unit is alive, but only
-- represent a resurrection cast when used by or on a dead unit. Require a
-- resolvable dead target before entering the normal resurrection lifecycle;
-- aura availability and consumption are tracked separately.
local function IsValidResurrectionTarget(spellID, targetGUID)
	if not SELF_RES_AURAS[spellID] then
		return true
	end

	if not IsKnownTargetGUID(targetGUID) then return false end

	local unitID = GetAccessibleUnitTokenFromGUID(targetGUID)

	return unitID and IsAccessibleUnitDeadOrGhost(unitID)
end

-- Compare a name-only API or event value against both name forms exposed by
-- a known unitID. Blizzard does not consistently document whether such values
-- include the realm suffix, so both name and name-realm must be accepted.
local function UnitMatchesName(unitID, name)
	if not canaccessvalue(unitID) or not canaccessvalue(name) then return end
	if not unitID or not name then return end

	local unitName, unitRealm = GetAccessibleUnitName(unitID)
	if not unitName then return end

	if name == unitName then
		return true
	end

	if unitRealm and unitRealm ~= "" and name == unitName .. "-" .. unitRealm then
		return true
	end
end

-- Resolve a name or name-realm string against addressable player and group
-- unitIDs, then return the matched unit's GUID. This supplements direct
-- UnitGUID(name) resolution when Blizzard exposes only a name string.
local function ResolveGroupUnitName(name)
	if not IsUsableUnitIdentifier(name) then return end

	if UnitMatchesName("player", name) then
		return PLAYER_GUID
	end
	if UnitExists("pet") and UnitMatchesName("pet", name) then
		return GetAccessibleUnitGUID("pet")
	end

	local prefix = (IsInRaid() and "raid") or (IsInGroup() and "party")
	if not prefix then return end

	local members = GetNumGroupMembers()

	for i = 1, members do
		local unitID = prefix .. i
		local petUnitID = prefix .. "pet" .. i

		if UnitExists(unitID) and UnitMatchesName(unitID, name) then
			return GetAccessibleUnitGUID(unitID)
		end
		if UnitExists(petUnitID) and UnitMatchesName(petUnitID, name) then
			return GetAccessibleUnitGUID(petUnitID)
		end
	end
end

-- Build a callback-safe target table for UNKNOWN casts.
--
-- UNKNOWN is a staging marker, not a real target identity. Multiple casters
-- can have UNKNOWN targets at the same time, but those casts may belong to
-- different actual targets. For callbacks, expose only the caster's own
-- unresolved target entry instead of the whole shared UNKNOWN staging table.
local function GetCallbackTargetInfo(targetGUID, casterGUID)
	local targetInfo = resTargetInfo[targetGUID]
	if not targetInfo then return end

	if targetGUID ~= UNKNOWN_TARGET_GUID then
		return NormalizeCallbackTable(targetInfo)
	end

	local casterInfo = casterGUID and targetInfo[casterGUID]
	if not casterInfo then return end

	return {
		targetGUID = UNKNOWN_TARGET_GUID,
		[casterGUID] = casterInfo,
	}
end

-- -------------------------------------------------------------------
-- Fastest-caster helpers
-- -------------------------------------------------------------------

-- Recalculate the fastest active resurrection for one known target.
--
-- UNKNOWN targets are deliberately excluded. UNKNOWN means "this caster has
-- an unresolved target"; it does not mean all UNKNOWN casts share one target.
-- Fastest-res calculations only make sense after the target resolves to a
-- real GUID.
local function UpdateFastestCasterGUID(targetGUID)
	if not IsKnownTargetGUID(targetGUID) or not resTargetInfo[targetGUID] then return end

	local fastestCasterGUID
	local fastestResType
	local fastestEndTime

	for casterGUID, casterInfo in pairs(resTargetInfo[targetGUID]) do
		if type(casterInfo) == "table" and casterInfo.endTime then
			if not fastestEndTime or casterInfo.endTime < fastestEndTime then
				fastestCasterGUID = casterGUID
				fastestResType = "SINGLE"
				fastestEndTime = casterInfo.endTime
			end
		end
	end

	for casterGUID, targets in pairs(massResTargetGUIDs) do
		if targets[targetGUID] then
			local casterInfo = massResCasterInfo[casterGUID]

			if casterInfo and casterInfo.endTime then
				if not fastestEndTime or casterInfo.endTime < fastestEndTime then
					fastestCasterGUID = casterGUID
					fastestResType = "MASS"
					fastestEndTime = casterInfo.endTime
				end
			end
		end
	end

	local targetInfo = resTargetInfo[targetGUID]
	local oldFastestCasterGUID = targetInfo.fastestCasterGUID
	local oldFastestResType = targetInfo.fastestResType
	local hadFastestCaster = oldFastestCasterGUID ~= nil

	targetInfo.fastestCasterGUID = fastestCasterGUID
	targetInfo.fastestResType = fastestResType

	if hadFastestCaster and ((oldFastestCasterGUID ~= fastestCasterGUID) or (oldFastestResType ~= fastestResType)) then
		return targetInfo
	end
end

-- Recalculate fastest resurrection for every known target.
--
-- This is used after mass-res state changes, because one mass-res cast can
-- affect the fastest result for many dead group members at once.
local function UpdateAllFastestCasterGUIDs()
	local changedTargetInfo

	for targetGUID in pairs(resTargetInfo) do
		local targetInfo = UpdateFastestCasterGUID(targetGUID)

		if targetInfo then
			changedTargetInfo = changedTargetInfo or {}
			changedTargetInfo[#changedTargetInfo + 1] = targetInfo
		end
	end

	return changedTargetInfo
end

-- Fire one fastest-res callback after its triggering lifecycle callback has
-- already exposed the cast state to consumers.
local function FireFastestResChanged(targetInfo)
	if targetInfo then
		lib.callbacks:Fire("FastestRes_Changed", targetInfo.targetGUID, targetInfo)
	end
end

-- Fire fastest-res callbacks for mass-res changes, which can affect many
-- known targets at once.
local function FireFastestResChangedList(changedTargetInfo)
	if not changedTargetInfo then return end

	for _, targetInfo in pairs(changedTargetInfo) do
		FireFastestResChanged(targetInfo)
	end
end

-- Find the mass resurrection cast which will complete first.
--
-- Returns the caster GUID and remaining cast time in seconds.
-- Remaining time is clamped to zero to avoid negative values from
-- event timing or delayed queries.
local function GetFastestMassResInfo()
	local fastestCasterGUID
	local fastestRemainingTime
	local now = GetTime()

	for casterGUID, casterInfo in pairs(massResCasterInfo) do
		if type(casterInfo) == "table" and casterInfo.endTime then
			local remainingTime = casterInfo.endTime - now

			if remainingTime < 0 then
				remainingTime = 0
			end

			if not fastestRemainingTime or remainingTime < fastestRemainingTime then
				fastestCasterGUID = casterGUID
				fastestRemainingTime = remainingTime
			end
		end
	end

	return fastestCasterGUID, fastestRemainingTime
end

-- Determine whether a specific target GUID is currently affected by
-- any tracked mass resurrection cast.
local function IsTargetAffectedByMassRes(targetGUID)
	if not targetGUID then return end

	for _, targets in pairs(massResTargetGUIDs) do
		if targets[targetGUID] then
			return true
		end
	end
end

-- Find the fastest mass resurrection affecting a specific target.
local function GetFastestMassResForTarget(targetGUID)
	local fastestCasterGUID
	local fastestRemainingTime
	local now = GetTime()

	for casterGUID, targets in pairs(massResTargetGUIDs) do
		if targets[targetGUID] then
			local casterInfo = massResCasterInfo[casterGUID]

			if casterInfo and casterInfo.endTime then
				local remainingTime = casterInfo.endTime - now

				if remainingTime < 0 then
					remainingTime = 0
				end

				if not fastestRemainingTime or remainingTime < fastestRemainingTime then
					fastestCasterGUID = casterGUID
					fastestRemainingTime = remainingTime
				end
			end
		end
	end

	return fastestCasterGUID, fastestRemainingTime
end

-- Lightweight GUID-shape check for public APIs. This intentionally avoids
-- validating every possible GUID form; it only distinguishes GUID-like input
-- from unresolved unit names.
local function IsUnitGUID(value)
	return type(value) == "string" and value:find("^%a+%-%d+%-") ~= nil
end

-- Normalize public unit arguments to GUIDs.
--
-- Public APIs accept unitIDs, GUIDs, unit names, and name-realm strings. Names
-- are valid input even when Blizzard cannot currently resolve them; in that
-- case callers receive the API's normal "not found" result instead of an
-- argument error.
local function ResolvePublicUnitArg(unit)
	if not canaccessvalue(unit) then return end

	local unitType = type(unit)

	if unitType ~= "string" then
		error(("bad argument #1, expected a unitID, GUID, or unit name, got %s"):format(unitType), 3)
	end

	if unit == "" or unit == UNKNOWN_TARGET_GUID then
		error(("bad argument #1, expected a unitID, GUID, or unit name, got %q"):format(unit), 3)
	end

	local unitGUID = GetAccessibleUnitGUID(unit)
	if unitGUID then
		return unitGUID
	end

	if IsUnitGUID(unit) then
		return unit
	end

	unitGUID = ResolveGroupUnitName(unit)
	if unitGUID then
		return unitGUID
	end

	-- Unresolved names are valid input, but Blizzard may not expose their GUID.
	return nil
end

-- -------------------------------------------------------------------
-- Active resurrection state
-- -------------------------------------------------------------------

-- Copy fields shared by every tracked resurrection cast. SetIfMissing keeps
-- earlier, more precise event data when later events provide only partial data.
local function ApplyCastInfo(info, casterGUID, castInfo)
	SetIfMissing(info, "castBarID", castInfo.castBarID)
	SetIfMissing(info, "castGUID", castInfo.castGUID)
	SetIfMissing(info, "casterGUID", casterGUID)
	SetIfMissing(info, "castTime", castInfo.castTime)
	SetIfMissing(info, "spellID", castInfo.spellID)
	SetIfMissing(info, "textureID", castInfo.textureID)
	SetIfMissing(info, "endTime", castInfo.endTime)
end

-- Mirror a single-target cast onto both lookup directions:
-- casterGUID -> ResCastInfo and targetGUID -> casterGUID -> ResCastInfo.
local function ApplySingleCastInfo(casterInfo, targetInfo, casterGUID, targetGUID, castInfo)
	ApplyCastInfo(casterInfo, casterGUID, castInfo)
	SetIfMissing(casterInfo, "targetGUID", targetGUID)

	ApplyCastInfo(targetInfo, casterGUID, castInfo)
	SetIfMissing(targetInfo, "targetGUID", targetGUID)
end

-- Mass-res cast data is caster-only because Blizzard does not expose targets
-- through the cast itself. Affected target GUIDs are snapshotted separately.
local function ApplyMassCastInfo(casterInfo, casterGUID, castInfo)
	ApplyCastInfo(casterInfo, casterGUID, castInfo)
end

-- Initialize and update both lookup directions for one single-target cast.
--
-- The caller supplies the authoritative caster GUID, which may intentionally be
-- the cached PLAYER_GUID rather than a GUID derived from the event unitID.
local function StoreSingleCastInfo(casterGUID, targetGUID, castInfo)
	recentFinishedResCasts[casterGUID] = nil
	resCasterInfo[casterGUID] = resCasterInfo[casterGUID] or {}
	resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
	resTargetInfo[targetGUID].targetGUID = resTargetInfo[targetGUID].targetGUID or targetGUID
	resTargetInfo[targetGUID][casterGUID] = resTargetInfo[targetGUID][casterGUID] or {}

	local casterInfo = resCasterInfo[casterGUID]
	local targetCasterInfo = resTargetInfo[targetGUID][casterGUID]

	ApplySingleCastInfo(casterInfo, targetCasterInfo, casterGUID, targetGUID, castInfo)

	return casterInfo, targetCasterInfo
end

-- Read the currently visible cast from a unit token and normalize its timing.
-- This only succeeds while Blizzard still exposes the cast through
-- UnitCastingInfo, so callers treat nil as "nothing useful to track."
local function GetCurrentCastInfo(unitID)
	if not canaccessvalue(unitID) then return end

	local _, _, textureID, startTimeMs, endTimeMs, _, castGUID, _, spellID, castBarID = UnitCastingInfo(unitID)
	if not canaccessvalue(startTimeMs)
		or not canaccessvalue(endTimeMs)
		or not canaccessvalue(spellID)
		or not canaccessvalue(castBarID)
	then
		return
	end
	if not spellID then return end

	if not canaccessvalue(castGUID) then
		castGUID = nil
	end
	if not canaccessvalue(textureID) then
		textureID = nil
	end

	local castTime, endTime = GetCastTimes(startTimeMs, endTimeMs)

	return {
		castBarID = castBarID,
		castGUID = castGUID,
		castTime = castTime,
		endTime = endTime,
		spellID = spellID,
		textureID = textureID,
	}
end

-- Populate single-target cast state from whatever Blizzard currently exposes.
--
-- UNIT_SPELLCAST_SENT can know the player's target before UNIT_SPELLCAST_START
-- has full cast timing, while observed casts may expose only name or name-realm,
-- or no target at all. Resolve those names against addressable group units and
-- merge partial data without overwriting better data from earlier events.
local function GetCasterPetUnitID(unitID)
	if unitID == "player" then
		return "pet"
	end

	local prefix, index = unitID:match("^(party)(%d+)$")

	if not prefix then
		prefix, index = unitID:match("^(raid)(%d+)$")
	end

	return prefix and (prefix .. "pet" .. index) or nil
end

local function ResolveSpellTargetGUID(unitID, spellID)
	if spellID == REVIVE_PET_SPELL_ID then
		return GetAccessibleUnitGUID(GetCasterPetUnitID(unitID))
	end

	return ResolveGroupUnitName(GetAccessibleSpellTargetName(unitID))
end

local function SelectSingleTargetGUID(sentTargetGUID, sentTargetIsExact, existingTargetGUID, spellTargetGUID)
	if existingTargetGUID then
		return existingTargetGUID
	end

	-- SENT identifies the attempted spell target, while UnitSpellTargetName
	-- describes the cast currently exposed for the unit. When they disagree,
	-- trust SENT only if its cast GUID exactly matches this cast; otherwise the
	-- current spell-target result is the stronger identity.
	if sentTargetGUID and spellTargetGUID and sentTargetGUID ~= spellTargetGUID then
		return sentTargetIsExact and sentTargetGUID or spellTargetGUID
	end

	return sentTargetGUID or spellTargetGUID or UNKNOWN_TARGET_GUID
end

local function PopulateSingleResInfo(unitID, casterGUID, castInfo, sentTargetGUID, sentTargetIsExact)
	local existingCasterInfo = resCasterInfo[casterGUID]
	local existingTargetGUID = existingCasterInfo
	and IsKnownTargetGUID(existingCasterInfo.targetGUID)
	and existingCasterInfo.targetGUID

	local spellTargetGUID = ResolveSpellTargetGUID(unitID, castInfo.spellID)
	local targetGUID = SelectSingleTargetGUID(
		sentTargetGUID,
		sentTargetIsExact,
		existingTargetGUID,
		spellTargetGUID
	)
	if not IsValidResurrectionTarget(castInfo.spellID, targetGUID) then return end

	StoreSingleCastInfo(casterGUID, targetGUID, castInfo)

	return targetGUID, UpdateFastestCasterGUID(targetGUID)
end

-- Snapshot the dead units actually affected by a mass resurrection while the
-- cast is still active.
--
-- UnitHasIncomingResurrection becomes false after the cast completes, so this
-- cannot be delayed until UNIT_SPELLCAST_SUCCEEDED. The snapshot is keyed by
-- caster GUID and later consumed when that caster's mass res finishes.
local function SnapshotMassResTargets(casterGUID)
	if not casterGUID then return end

	massResTargetGUIDs[casterGUID] = {}

	if IsAccessibleUnitDeadOrGhost("player") and HasAccessibleIncomingResurrection("player") then
		massResTargetGUIDs[casterGUID][PLAYER_GUID] = true
	end

	local prefix = (IsInRaid() and "raid") or (IsInGroup() and "party")
	if not prefix then return end

	local members = GetNumGroupMembers()

	for i = 1, members do
		local unitID = prefix .. i

		if UnitExists(unitID) and IsAccessibleUnitDeadOrGhost(unitID) and HasAccessibleIncomingResurrection(unitID) then
			local targetGUID = GetAccessibleUnitGUID(unitID)

			if targetGUID then
				massResTargetGUIDs[casterGUID][targetGUID] = true
			end
		end
	end
end

-- Populate mass-res cast state.
--
-- Mass resurrection spells do not expose individual target GUIDs through the
-- cast data, so the cast is tracked by caster while its affected target GUIDs
-- are snapshotted separately.
local function PopulateMassResInfo(casterGUID, castInfo)
	recentFinishedResCasts[casterGUID] = nil
	massResCasterInfo[casterGUID] = massResCasterInfo[casterGUID] or {}

	ApplyMassCastInfo(massResCasterInfo[casterGUID], casterGUID, castInfo)
	SnapshotMassResTargets(casterGUID)

	return UpdateAllFastestCasterGUIDs()
end

-- Identify whether the current visible cast is a resurrection spell and
-- populate the matching state tables. Returns enough context for event
-- handlers to fire the correct callbacks without re-reading state.
local function PopulateResInfoTables(unitID, castGUID, spellID, castBarID, sentTargetGUID, sentTargetIsExact)
	local casterGUID = GetAccessibleUnitGUID(unitID)
	if not casterGUID then return end

	local castInfo = GetCurrentCastInfo(unitID)
	if not castInfo then return end
	if spellID and castInfo.spellID ~= spellID then return end

	castInfo.castGUID = castGUID or castInfo.castGUID
	castInfo.spellID = spellID or castInfo.spellID
	castInfo.castBarID = castBarID or castInfo.castBarID

	if SINGLE_TARGET_RES_SPELLS[castInfo.spellID] then
		local targetGUID, fastestTargetInfo = PopulateSingleResInfo(
			unitID,
			casterGUID,
			castInfo,
			sentTargetGUID,
			sentTargetIsExact
		)
		if not targetGUID then return end

		return "SINGLE", casterGUID, targetGUID, fastestTargetInfo
	elseif MASS_RES_SPELLS[castInfo.spellID] then
		local fastestTargetInfo = PopulateMassResInfo(casterGUID, castInfo)
		return "MASS", casterGUID, nil, fastestTargetInfo
	end
end

-- Build pending identity for the player's UNIT_SPELLCAST_SENT path.
--
-- UNIT_SPELLCAST_SENT is authoritative for the player target, cast GUID, and
-- spell ID, but it only reports an attempted cast. Non-instant timing is read
-- from UnitCastingInfo after UNIT_SPELLCAST_START; casts which reach SUCCEEDED
-- without START are handled as instant casts.
local function NormalizePlayerSentTarget(target, spellID)
	if spellID == REVIVE_PET_SPELL_ID then
		return "pet"
	end

	return IsUsableUnitIdentifier(target) and target or nil
end

local function GetPlayerSentCastInfo(target, castGUID, spellID)
	if SINGLE_TARGET_RES_SPELLS[spellID] then
		return {
			castGUID = castGUID,
			spellID = spellID,
			targetGUID = GetAccessibleUnitGUID(target)
			or ResolveGroupUnitName(target),
		}
	elseif MASS_RES_SPELLS[spellID] then
		return {
			castGUID = castGUID,
			spellID = spellID,
		}
	end
end

local function PlayerSentCastMatches(castInfo, castGUID, spellID)
	if not castInfo or castInfo.spellID ~= spellID then return end

	return not castInfo.castGUID or not castGUID or castInfo.castGUID == castGUID
end

local function PlayerSentCastMatchesExactly(castInfo, castGUID, spellID)
	return castInfo
	and castInfo.spellID == spellID
	and castInfo.castGUID
	and castGUID
	and castInfo.castGUID == castGUID
end

-- Move one caster's unresolved target entry to its resolved GUID.
--
-- The UNKNOWN staging table is keyed by caster GUID. When Blizzard later
-- exposes the target through INCOMING_RESURRECT_CHANGED, only that caster's
-- entry is moved into the real target GUID table.
local function ReplaceUnknownTargetGUID(targetGUID, casterGUID)
	if not targetGUID or not casterGUID then return end
	if not resTargetInfo[UNKNOWN_TARGET_GUID] then return end
	if not resTargetInfo[UNKNOWN_TARGET_GUID][casterGUID] then return end

	resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
	resTargetInfo[targetGUID].targetGUID = targetGUID

	resTargetInfo[targetGUID][casterGUID] = resTargetInfo[UNKNOWN_TARGET_GUID][casterGUID]
	resTargetInfo[targetGUID][casterGUID].targetGUID = targetGUID
	resTargetInfo[UNKNOWN_TARGET_GUID][casterGUID] = nil

	if resTargetInfo[UNKNOWN_TARGET_GUID].fastestCasterGUID == casterGUID then
		resTargetInfo[UNKNOWN_TARGET_GUID].fastestCasterGUID = nil
		resTargetInfo[UNKNOWN_TARGET_GUID].fastestResType = nil
	end

	UpdateFastestCasterGUID(UNKNOWN_TARGET_GUID)
	UpdateFastestCasterGUID(targetGUID)

	if not HasTableEntries(resTargetInfo[UNKNOWN_TARGET_GUID]) then
		resTargetInfo[UNKNOWN_TARGET_GUID] = nil
	end
end

-- Remove a single-target cast from caster and target state.
--
-- Callers decide whether fastest-caster state should be recalculated and
-- whether the entire target table should be removed. This keeps callback
-- timing explicit: terminal callbacks can fire before cleanup, while fastest
-- change callbacks can fire after cleanup.
local function RemoveSingleResCast(casterGUID, targetGUID, updateFastest, removeTargetInfo)
	if not casterGUID then return end

	targetGUID = targetGUID or UNKNOWN_TARGET_GUID

	local removedCasterInfo = resCasterInfo[casterGUID]

	resCasterInfo[casterGUID] = nil

	if resTargetInfo[targetGUID] then
		resTargetInfo[targetGUID][casterGUID] = nil
	end

	local targetInfo
	local changedTargetInfo

	if removeTargetInfo and targetGUID ~= UNKNOWN_TARGET_GUID then
		resTargetInfo[targetGUID] = nil
	elseif HasTableEntries(resTargetInfo[targetGUID]) then
		if updateFastest then
			changedTargetInfo = UpdateFastestCasterGUID(targetGUID)
		elseif resTargetInfo[targetGUID].fastestCasterGUID == casterGUID then
			resTargetInfo[targetGUID].fastestCasterGUID = nil
			resTargetInfo[targetGUID].fastestResType = nil
			UpdateFastestCasterGUID(targetGUID)
		end

		targetInfo = resTargetInfo[targetGUID]
	else
		resTargetInfo[targetGUID] = nil
	end

	return NormalizeCallbackTable(removedCasterInfo), NormalizeCallbackTable(targetInfo), changedTargetInfo
end

-- Remove a mass-res cast and optionally recalculate fastest state for every
-- known target. One mass-res cast can affect many targets at once.
local function RemoveMassResCast(casterGUID, updateFastest)
	if not casterGUID then return end

	local removedCasterInfo = massResCasterInfo[casterGUID]

	massResCasterInfo[casterGUID] = nil
	massResTargetGUIDs[casterGUID] = nil

	local changedTargetInfo
	if updateFastest then
		changedTargetInfo = UpdateAllFastestCasterGUIDs()
	end

	return NormalizeCallbackTable(removedCasterInfo), changedTargetInfo
end

-- Remove all single-target resurrection state attached to one target.
-- Called after a completed known target is observed alive.
local function RemoveTargetResInfo(targetGUID)
	if not targetGUID then return end

	local removed

	for casterGUID, casterInfo in pairs(resCasterInfo) do
		if casterInfo.targetGUID == targetGUID then
			pendingEngineeringCasts[casterGUID] = nil
			resCasterInfo[casterGUID] = nil
			removed = true
		end
	end

	if resTargetInfo[targetGUID] then
		resTargetInfo[targetGUID] = nil
		removed = true
	end

	return removed
end

-- Defensive stale-state cleanup for unresolved target entries.
--
-- Normal stopped/finished paths remove UNKNOWN entries immediately after their
-- terminal callbacks fire. This fallback exists for missed or unusual event
-- ordering where an unresolved cast never receives a terminal spellcast event.
-- The timeout is measured from the tracked endTime. Ten seconds covers unusual
-- event ordering after the longest known resurrection cast should have ended.
local function RemoveExpiredUnknownTargetInfo()
	local targetInfo = resTargetInfo[UNKNOWN_TARGET_GUID]
	if not targetInfo then return end

	local now = GetTime()
	local removed

	for casterGUID, info in pairs(targetInfo) do
		if type(info) == "table" and info.endTime and (now - info.endTime) >= UNKNOWN_TARGET_CLEANUP_TIMEOUT then
			resCasterInfo[casterGUID] = nil
			targetInfo[casterGUID] = nil
			removed = true
		end
	end

	if removed and not HasTableEntries(targetInfo) then
		resTargetInfo[UNKNOWN_TARGET_GUID] = nil
	end

	return removed
end

-- -------------------------------------------------------------------
-- Resurrection-offer state
-- -------------------------------------------------------------------

-- Player resurrection offers can be delayed by corpse recovery. Blizzard only
-- exposes that delay for the player, so other units use the normal timeout.
local function GetResWaitingDuration(targetGUID)
	local waitingDuration = RES_WAITING_TIMEOUT

	if targetGUID == PLAYER_GUID then
		waitingDuration = waitingDuration + (GetCorpseRecoveryDelay() or 0)
	end

	return waitingDuration
end

-- Clear all expected or confirmed offer state without firing an expiry
-- callback. Used when the target becomes alive before the offer expires.
local function ClearResOfferTargetGUID(targetGUID)
	if IsKnownTargetGUID(targetGUID) then
		resOfferExpireTimes[targetGUID] = nil
	end
end

local ResolveAliveTarget

-- Start or refresh expected-offer state for a known resurrection target. A
-- later offer for the same target resets the waiting timer.
--
-- The scheduled callback verifies that the stored expire time still matches,
-- so an older timer cannot clear or fire for a newer resurrection offer.
local function TrackResOfferTargetGUID(targetGUID)
	if not IsKnownTargetGUID(targetGUID) then return end

	local duration = GetResWaitingDuration(targetGUID)
	local expireTime = GetTime() + duration

	resOfferExpireTimes[targetGUID] = expireTime

	After(duration, function()
		if resOfferExpireTimes[targetGUID] ~= expireTime then return end

		local unitID = GetAccessibleUnitTokenFromGUID(targetGUID)
		local health = unitID and GetAccessibleUnitHealth(unitID)

		if health and health > 0 then
			ResolveAliveTarget(targetGUID)
			return
		end

		ClearResOfferTargetGUID(targetGUID)
		ClearRecentFinishedResCastsForTarget(targetGUID)
		lib.callbacks:Fire("ResTargetGUID_WaitingTimeExpired", targetGUID)
	end)
end

-- Confirm that the target's client received a resurrection offer. Expected
-- remote offers use the same waiting state, but only this path fires the
-- confirmation callback.
local function ConfirmResOffer(targetGUID, casterGUID, spellID)
	if not IsKnownTargetGUID(targetGUID) then return end

	TrackResOfferTargetGUID(targetGUID)
	lib.callbacks:Fire("ResTargetGUID_HasResOffer", targetGUID, casterGUID, spellID)
end

-- Mark the snapshotted mass-res targets as waiting after the mass resurrection
-- cast completes.
--
-- The affected-unit snapshot was captured while UnitHasIncomingResurrection
-- was still true. At finish time, only consume that saved data; do not rescan.
local function MarkMassResTargets(casterGUID)
	local targets = casterGUID and massResTargetGUIDs[casterGUID]
	if not targets then return end

	for targetGUID in pairs(targets) do
		TrackResOfferTargetGUID(targetGUID)
	end
end

-- Move one active single-target cast to an authoritative target GUID. Direct
-- offer events are stronger evidence than spell-target data, which can be
-- absent or stale on observers.
local function ReassignSingleResTargetGUID(casterGUID, targetGUID)
	local casterInfo = casterGUID and resCasterInfo[casterGUID]
	if not casterInfo or not IsKnownTargetGUID(targetGUID) then return end

	local previousTargetGUID = casterInfo.targetGUID or UNKNOWN_TARGET_GUID
	if previousTargetGUID == targetGUID then return end

	if resTargetInfo[previousTargetGUID] then
		resTargetInfo[previousTargetGUID][casterGUID] = nil

		if resTargetInfo[previousTargetGUID].fastestCasterGUID == casterGUID then
			resTargetInfo[previousTargetGUID].fastestCasterGUID = nil
			resTargetInfo[previousTargetGUID].fastestResType = nil
		end

		UpdateFastestCasterGUID(previousTargetGUID)

		if not HasTableEntries(resTargetInfo[previousTargetGUID]) then
			resTargetInfo[previousTargetGUID] = nil
		end
	end

	casterInfo.targetGUID = targetGUID
	resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
	resTargetInfo[targetGUID].targetGUID = targetGUID
	resTargetInfo[targetGUID][casterGUID] = {}
	ApplySingleCastInfo(casterInfo, resTargetInfo[targetGUID][casterGUID], casterGUID, targetGUID, casterInfo)
	UpdateFastestCasterGUID(targetGUID)

	lib.callbacks:Fire(
		"ResTargetGUID_Resolved",
		casterGUID,
		targetGUID,
		casterInfo,
		resTargetInfo[targetGUID]
	)
end

-- Finish one tracked single-target cast and retire its active state. Reliable
-- resurrection spells may create an expected offer at spellcast completion;
-- engineering devices pass false and wait for direct offer confirmation.
local function FinishSingleResCast(casterGUID, targetGUID, trackExpectedOffer)
	local casterInfo = casterGUID and resCasterInfo[casterGUID]
	if not casterInfo then return end

	targetGUID = targetGUID or casterInfo.targetGUID or UNKNOWN_TARGET_GUID

	if IsKnownTargetGUID(targetGUID) and casterInfo.targetGUID ~= targetGUID then
		ReassignSingleResTargetGUID(casterGUID, targetGUID)
	elseif IsKnownTargetGUID(casterInfo.targetGUID) then
		targetGUID = casterInfo.targetGUID
	end

	local finishedCasterInfo = resCasterInfo[casterGUID]
	local finishedTargetInfo = GetCallbackTargetInfo(targetGUID, casterGUID)

	pendingEngineeringCasts[casterGUID] = nil
	MarkTerminalCast(casterGUID, finishedCasterInfo.castGUID, finishedCasterInfo.castBarID)
	StoreRecentFinishedResCast(casterGUID, targetGUID, finishedCasterInfo.spellID)

	if trackExpectedOffer then
		TrackResOfferTargetGUID(targetGUID)
	end

	lib.callbacks:Fire(
		"ResCast_Finished",
		casterGUID,
		targetGUID,
		NormalizeCallbackTable(finishedCasterInfo),
		finishedTargetInfo
	)

	RemoveSingleResCast(casterGUID, targetGUID, false, false)

	return targetGUID
end

-- Stop one tracked single-target cast and retire its active state. This path is
-- shared by explicit spellcast failures and engineering activations which did
-- not produce a confirmed resurrection offer.
local function StopSingleResCast(casterGUID, targetGUID, castGUID, castBarID)
	local casterInfo = casterGUID and resCasterInfo[casterGUID]
	if not casterInfo then
		pendingEngineeringCasts[casterGUID] = nil
		return
	end

	targetGUID = targetGUID or casterInfo.targetGUID or UNKNOWN_TARGET_GUID

	local callbackCasterInfo = NormalizeCallbackTable(casterInfo)
	local callbackTargetInfo = GetCallbackTargetInfo(targetGUID, casterGUID)

	pendingEngineeringCasts[casterGUID] = nil
	MarkTerminalCast(casterGUID, castGUID or casterInfo.castGUID, castBarID or casterInfo.castBarID)
	lib.callbacks:Fire("ResCast_Stopped", casterGUID, targetGUID, callbackCasterInfo, callbackTargetInfo)

	local _, _, changedTargetInfo = RemoveSingleResCast(casterGUID, targetGUID, true, false)

	FireFastestResChanged(changedTargetInfo)
end

-- Engineering UNIT_SPELLCAST_SUCCEEDED means only that the device activation
-- completed. Give RESURRECT_REQUEST a short opportunity to prove that the
-- activation actually produced an offer; otherwise report the attempt through
-- the existing stopped lifecycle.
local function WaitForEngineeringResOffer(casterGUID)
	local marker = {}
	pendingEngineeringCasts[casterGUID] = marker

	After(RES_OFFER_CONFIRMATION_TIMEOUT, function()
		if pendingEngineeringCasts[casterGUID] ~= marker then return end

		StopSingleResCast(casterGUID)
	end)
end

-- Once a target is alive, any remaining single-target casts aimed at it can no
-- longer complete usefully. Stop them through the normal callback path before
-- their lookup keys are retired.
local function StopSingleResCastsForTarget(targetGUID)
	local casterGUIDs = {}

	for casterGUID, casterInfo in pairs(resCasterInfo) do
		if casterInfo.targetGUID == targetGUID then
			casterGUIDs[#casterGUIDs + 1] = casterGUID
		end
	end

	for index = 1, #casterGUIDs do
		StopSingleResCast(casterGUIDs[index], targetGUID)
	end
end

local function ClearTargetFromMassResSnapshots(targetGUID)
	for casterGUID, targets in pairs(massResTargetGUIDs) do
		targets[targetGUID] = nil

		if not next(targets) and not massResCasterInfo[casterGUID] then
			massResTargetGUIDs[casterGUID] = nil
		end
	end
end

-- Resolve one offer lifecycle when its target becomes alive. This is shared by
-- UNIT_HEALTH and the expiry timer's defensive health check so missed event
-- ordering cannot leave target, caster, or mass-snapshot keys behind.
ResolveAliveTarget = function(targetGUID)
	if not targetGUID or not resOfferExpireTimes[targetGUID] then return end

	StopSingleResCastsForTarget(targetGUID)
	ClearTargetFromMassResSnapshots(targetGUID)
	ClearResOfferTargetGUID(targetGUID)
	ClearRecentFinishedResCastsForTarget(targetGUID)
	RemoveTargetResInfo(targetGUID)

	lib.callbacks:Fire("ResTargetGUID_IsAlive", targetGUID)

	RemoveExpiredUnknownTargetInfo()
end

-- -------------------------------------------------------------------
-- Self-resurrection state
-- -------------------------------------------------------------------

-- Build a stable key for one self-res option. Different self-res sources can
-- coexist, so spell, item, and aura-backed options must not overwrite each
-- other accidentally.
local function GetSelfResOptionKey(optionInfo)
	if optionInfo.spellID then
		return "spell:" .. optionInfo.spellID
	elseif optionInfo.itemID then
		return "item:" .. optionInfo.itemID
	elseif optionInfo.auraInstanceID then
		return "aura:" .. optionInfo.auraInstanceID
	end
end

-- Add or refresh a self-res option. The Available callback only fires for new
-- option keys; refreshing an existing key keeps state current without spamming
-- consumers.
local function AddSelfResOption(unitGUID, optionInfo)
	if not unitGUID or not optionInfo then return end

	local optionKey = GetSelfResOptionKey(optionInfo)
	if not optionKey then return end

	selfResInfo[unitGUID] = selfResInfo[unitGUID] or {}

	if not selfResInfo[unitGUID][optionKey] then
		selfResInfo[unitGUID][optionKey] = optionInfo
		lib.callbacks:Fire("UnitSelfRes_Available", unitGUID, optionInfo)
	else
		selfResInfo[unitGUID][optionKey] = optionInfo
	end

	return optionKey
end

-- Remove one self-res option and report what remains. Consumers can use
-- remainingInfo to decide whether the unit still has another self-res path.
local function RemoveSelfResOption(unitGUID, optionKey)
	if not unitGUID or not optionKey then return end
	if not selfResInfo[unitGUID] then return end

	local consumedOptionInfo = selfResInfo[unitGUID][optionKey]
	if not consumedOptionInfo then return end

	selfResInfo[unitGUID][optionKey] = nil

	local remainingInfo = next(selfResInfo[unitGUID]) and selfResInfo[unitGUID] or nil

	if not remainingInfo then
		selfResInfo[unitGUID] = nil
	end

	lib.callbacks:Fire("UnitSelfRes_Consumed", unitGUID, consumedOptionInfo, remainingInfo)
end

-- C_DeathInfo exposes player self-res choices such as soulstone, reincarnation,
-- and item-based options. This is authoritative for the player, so reconcile
-- the full option list each time it may have changed.
local function UpdatePlayerSelfResOptions()
	if not GetSelfResurrectOptions then return end

	local seen = {}

	---@type LibResInfoSelfResurrectOption[]|nil
	local options = GetSelfResurrectOptions()

	if canaccessvalue(options) and options then
		for _, option in pairs(options) do
			if canaccessvalue(option) then
				local optionInfo = {
					unitGUID = PLAYER_GUID,
				}

				SetIfPresent(optionInfo, "spellID", option.spellID)
				SetIfPresent(optionInfo, "itemID", option.itemID)
				SetIfPresent(optionInfo, "auraInstanceID", option.auraInstanceID)
				SetIfPresent(optionInfo, "expirationTime", option.expirationTime)

				local optionKey = GetSelfResOptionKey(optionInfo)

				if optionKey then
					seen[optionKey] = true
					AddSelfResOption(PLAYER_GUID, optionInfo)
				end
			end
		end
	end

	if selfResInfo[PLAYER_GUID] then
		for optionKey in pairs(selfResInfo[PLAYER_GUID]) do
			if not seen[optionKey] then
				RemoveSelfResOption(PLAYER_GUID, optionKey)
			end
		end
	end
end

-- Non-player self-res detection is aura-based. Scan only known self-res aura
-- spellIDs and remove aura-backed options that disappeared from the unit.
local function UpdateUnitSelfResAuras(unitID)
	if not unitID then return end

	local unitGUID = GetAccessibleUnitGUID(unitID)
	if not unitGUID then return end

	local seen = {}

	for spellID in pairs(SELF_RES_AURAS) do
		local aura = GetUnitAuraBySpellID(unitID, spellID)

		if canaccessvalue(aura) and aura then
			local optionInfo = {
				unitGUID = unitGUID,
				spellID = spellID,
			}

			if canaccessvalue(aura.auraInstanceID) then
				SetIfPresent(optionInfo, "auraInstanceID", aura.auraInstanceID)
			end
			if canaccessvalue(aura.expirationTime) then
				SetIfPresent(optionInfo, "expirationTime", aura.expirationTime)
			end

			local optionKey = GetSelfResOptionKey(optionInfo)

			if optionKey then
				seen[optionKey] = true
				AddSelfResOption(unitGUID, optionInfo)
			end
		end
	end

	if selfResInfo[unitGUID] then
		for optionKey, optionInfo in pairs(selfResInfo[unitGUID]) do
			if optionInfo.auraInstanceID and not seen[optionKey] then
				RemoveSelfResOption(unitGUID, optionKey)
			end
		end
	end
end

-- Return true when incremental UNIT_AURA data may have changed a tracked
-- self-resurrection aura. Missing, full, or inaccessible updates deliberately
-- fall back to the complete spellID scan above.
local function AuraInstanceIDsMayAffectSelfRes(unitID, auraInstanceIDs, trackedOptions)
	if not canaccessvalue(auraInstanceIDs) then return true end
	if not auraInstanceIDs then return false end
	if not GetAuraDataByAuraInstanceID then return true end

	for _, auraInstanceID in pairs(auraInstanceIDs) do
		if not canaccessvalue(auraInstanceID) then return true end

		if trackedOptions then
			for _, optionInfo in pairs(trackedOptions) do
				if optionInfo.auraInstanceID == auraInstanceID then
					return true
				end
			end
		end

		local aura = GetAuraDataByAuraInstanceID(unitID, auraInstanceID)
		if not canaccessvalue(aura) then return true end

		if aura then
			local spellID = aura.spellId
			if not canaccessvalue(spellID) then return true end

			if spellID and SELF_RES_AURAS[spellID] then
				return true
			end
		end
	end

	return false
end

local function UnitAuraUpdateMayAffectSelfRes(unitID, updateInfo)
	if not canaccessvalue(updateInfo) or type(updateInfo) ~= "table" then return true end

	local isFullUpdate = updateInfo.isFullUpdate
	if not canaccessvalue(isFullUpdate) or isFullUpdate then return true end

	local addedAuras = updateInfo.addedAuras
	local updatedAuraInstanceIDs = updateInfo.updatedAuraInstanceIDs
	local removedAuraInstanceIDs = updateInfo.removedAuraInstanceIDs

	if not canaccessvalue(addedAuras)
		or not canaccessvalue(updatedAuraInstanceIDs)
		or not canaccessvalue(removedAuraInstanceIDs)
	then
		return true
	end

	-- A table without incremental fields may come from a client whose event
	-- payload differs from the current UnitAuraUpdateInfo contract.
	if addedAuras == nil and updatedAuraInstanceIDs == nil and removedAuraInstanceIDs == nil then
		return true
	end

	if addedAuras then
		for _, aura in pairs(addedAuras) do
			if not canaccessvalue(aura) then return true end

			local spellID = aura.spellId
			if not canaccessvalue(spellID) then return true end

			if spellID and SELF_RES_AURAS[spellID] then
				return true
			end
		end
	end

	local unitGUID = GetAccessibleUnitGUID(unitID)
	if not unitGUID then return true end

	local trackedOptions = selfResInfo[unitGUID]

	return AuraInstanceIDsMayAffectSelfRes(unitID, updatedAuraInstanceIDs, trackedOptions)
		or AuraInstanceIDsMayAffectSelfRes(unitID, removedAuraInstanceIDs, trackedOptions)
end

-- -------------------------------------------------------------------
-- External resurrection request helpers
-- -------------------------------------------------------------------

-- Resolve the caster named by RESURRECT_REQUEST. Group unit tokens are the
-- preferred source; a visible nameplate is retained for the external-caster
-- fallback which can synthesize an otherwise unobserved cast.
local function ResolveResurrectRequester(inviterName)
	if not IsUsableUnitIdentifier(inviterName) then return end

	local casterGUID = ResolveGroupUnitName(inviterName)
	if casterGUID then
		return casterGUID, GetAccessibleUnitTokenFromGUID(casterGUID)
	end

	for _, nameplate in pairs(GetNamePlates()) do
		local unitID = nameplate.unitToken

		if UnitMatchesName(unitID, inviterName) then
			return GetAccessibleUnitGUID(unitID), unitID
		end
	end
end

-- RESURRECT_REQUEST is not paired with the normal target lifecycle. Once the
-- observed caster's cast timer ends, synthesize the same finished callback path
-- used by normal single-target resurrection casts.
local function FinishExternalResCast(casterGUID, targetGUID)
	local casterInfo = resCasterInfo[casterGUID]
	if not casterInfo then return end
	if casterInfo.targetGUID ~= targetGUID then return end
	if IsTerminalCast(casterGUID, casterInfo.castGUID, casterInfo.castBarID) then return end

	FinishSingleResCast(casterGUID, targetGUID, true)
end

-- -------------------------------------------------------------------
-- Event aliases and registration
-- -------------------------------------------------------------------

-- Register runtime events after PLAYER_LOGIN so player GUID and client state
-- are initialized. PLAYER_LOGIN remains the bootstrap event, while
-- NEUTRAL_FACTION_SELECT_RESULT is registered separately only when needed.
local function RegisterEvents()
	for event, enabled in pairs(events) do
		if enabled then
			frame:RegisterEvent(event)
		end
	end
end

-- -------------------------------------------------------------------
-- Event handlers
-- -------------------------------------------------------------------

-- Initialize state and register runtime events.
local function PLAYER_LOGIN()
	PLAYER_GUID = PLAYER_GUID or UnitGUID("player")

	wipe(resCasterInfo)
	wipe(massResCasterInfo)
	wipe(massResTargetGUIDs)
	wipe(resTargetInfo)
	wipe(resOfferExpireTimes)
	wipe(pendingEngineeringCasts)
	wipe(recentFinishedResCasts)
	wipe(selfResInfo)
	wipe(terminalCastGUIDs)
	wipe(terminalCastBarIDs)
	playerSentCastInfo = nil

	RegisterEvents()

	if (isMists or isStandard) and IsPlayerNeutral() then
		frame:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
	end

	UpdatePlayerSelfResOptions()
end

-- Neutral Pandaren can change faction after login. Refresh PLAYER_GUID after
-- faction selection because later player-cast tracking depends on it.
local function NEUTRAL_FACTION_SELECT_RESULT(success)
	if success then
		local factionGroup = UnitFactionGroup("player")

		if factionGroup == "Alliance" or factionGroup == "Horde" then
			PLAYER_GUID = UnitGUID("player")
			frame:UnregisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
		end
	end
end

-- Player spell targeting is available before the cast starts.
--
-- Store only authoritative SENT identity here. UNIT_SPELLCAST_SENT reports an
-- attempted cast, so callbacks wait for START to provide non-instant timing or
-- for SUCCEEDED to confirm an instant cast.
local function UNIT_SPELLCAST_SENT(unitID, target, castGUID, spellID)
	if not canaccessvalue(unitID) then return end
	if unitID ~= "player" then return end
	if not canaccessvalue(spellID) then return end
	if not canaccessvalue(castGUID) then castGUID = nil end

	target = NormalizePlayerSentTarget(target, spellID)

	local sentCastInfo = GetPlayerSentCastInfo(target, castGUID, spellID)

	if sentCastInfo and IsTerminalCast(PLAYER_GUID, sentCastInfo.castGUID) then
		playerSentCastInfo = nil
		return
	end

	playerSentCastInfo = sentCastInfo
end

-- Non-instant resurrection casts enter active tracking here.
--
-- For the player, use the target captured by UNIT_SPELLCAST_SENT while reading
-- actual timing and texture data from UnitCastingInfo. For observed casters,
-- resolve the target from whatever Blizzard currently exposes.
local function UNIT_SPELLCAST_START(unitID, castGUID, spellID, castBarID)
	if not IsTrackedSpellcastUnit(unitID) then return end
	if not canaccessvalue(spellID) or not canaccessvalue(castBarID) then return end
	if not canaccessvalue(castGUID) then castGUID = nil end
	if not SINGLE_TARGET_RES_SPELLS[spellID] and not MASS_RES_SPELLS[spellID] then return end

	local casterGUID = GetAccessibleUnitGUID(unitID)
	if not casterGUID then return end
	if IsTerminalCast(casterGUID, castGUID, castBarID) then return end

	local activeCasterInfo = resCasterInfo[casterGUID] or massResCasterInfo[casterGUID]
	if activeCasterInfo then
		-- A repeated START for the active cast must not announce it twice. A
		-- different GUID is a late or out-of-order event and must not replace the
		-- newer active cast stored for this caster.
		return
	end

	local sentTargetGUID, sentTargetIsExact

	if unitID == "player" and PlayerSentCastMatches(playerSentCastInfo, castGUID, spellID) then
		sentTargetGUID = playerSentCastInfo.targetGUID
		sentTargetIsExact = PlayerSentCastMatchesExactly(playerSentCastInfo, castGUID, spellID)
	end

	local resType, _, targetGUID, fastestTargetInfo = PopulateResInfoTables(
		unitID,
		castGUID,
		spellID,
		castBarID,
		sentTargetGUID,
		sentTargetIsExact
	)
	if not resType then return end

	if unitID == "player" then
		playerSentCastInfo = nil
	end

	if resType == "SINGLE" and targetGUID then
		lib.callbacks:Fire("ResCast_Started", casterGUID, targetGUID, resCasterInfo[casterGUID], GetCallbackTargetInfo(targetGUID, casterGUID))

		FireFastestResChanged(fastestTargetInfo)
	elseif resType == "MASS" then
		lib.callbacks:Fire("MassResCast_Started", casterGUID, massResCasterInfo[casterGUID])

		FireFastestResChangedList(fastestTargetInfo)
	end
end

-- Fill in an UNKNOWN target when Blizzard later exposes incoming-res data.
-- Blizzard sometimes reveals incoming-res target information after a cast was
-- first observed as UNKNOWN. Match either name form against the event unitID,
-- then move only that caster's staged entry to the real target GUID and notify
-- consumers.
local function INCOMING_RESURRECT_CHANGED(targetID)
	if not canaccessvalue(targetID) then return end

	local targetGUID = GetAccessibleUnitGUID(targetID)
	if not targetGUID then return end

	for _, info in pairs(resCasterInfo) do
		if info.targetGUID == UNKNOWN_TARGET_GUID then
			local casterGUID = info.casterGUID
			local casterID = GetAccessibleUnitTokenFromGUID(casterGUID)

			if casterID then
				local spellTargetName = GetAccessibleSpellTargetName(casterID)

				if UnitMatchesName(targetID, spellTargetName) then
					info.targetGUID = targetGUID
					ReplaceUnknownTargetGUID(targetGUID, casterGUID)

					lib.callbacks:Fire("ResTargetGUID_Resolved", casterGUID, targetGUID, resCasterInfo[casterGUID], resTargetInfo[targetGUID])
				end
			end
		end
	end
end

-- External resurrection requests are special:
-- they target the player, provide the caster as name or name-realm, may come
-- from a visible nearby caster, and do not necessarily give the same event
-- sequence as group spellcast tracking.
local function RESURRECT_REQUEST(inviterName)
	if not canaccessvalue(inviterName) then
		inviterName = nil
	end

	local casterGUID, casterID = ResolveResurrectRequester(inviterName)
	local activeSingleInfo = casterGUID and resCasterInfo[casterGUID]
	local activeMassInfo = casterGUID and massResCasterInfo[casterGUID]
	local recentInfo = casterGUID and recentFinishedResCasts[casterGUID]
	local currentCastInfo = casterID and GetCurrentCastInfo(casterID)
	local spellID = (activeSingleInfo and activeSingleInfo.spellID)
		or (activeMassInfo and activeMassInfo.spellID)
		or (recentInfo and recentInfo.spellID)
		or (currentCastInfo and currentCastInfo.spellID)

	-- A request received by the player is direct proof that the player has a
	-- resurrection offer. If its caster still has an active single-target cast,
	-- this event also authoritatively resolves and finishes that cast.
	if activeSingleInfo then
		FinishSingleResCast(casterGUID, PLAYER_GUID, false)
	end

	ConfirmResOffer(PLAYER_GUID, casterGUID, spellID)

	-- Tracked and recently completed casts already supplied all available cast
	-- lifecycle callbacks. Mass resurrection remains caster-wide and must not be
	-- declared finished merely because one target received an offer.
	if activeSingleInfo or activeMassInfo or recentInfo then return end

	-- Outside group tracking, retain the historical nameplate fallback for a
	-- visible nearby caster. This path is deliberately limited to safe contexts
	-- because it relies on live cast-bar inspection rather than group events.
	if IsInInstance() then return end
	if InCombatLockdown() or UnitAffectingCombat("player") then return end
	if not casterGUID or not currentCastInfo then return end
	if not SINGLE_TARGET_RES_SPELLS[currentCastInfo.spellID] then return end
	if IsTerminalCast(casterGUID, currentCastInfo.castGUID, currentCastInfo.castBarID) then return end

	local casterInfo = StoreSingleCastInfo(casterGUID, PLAYER_GUID, currentCastInfo)
	local targetInfo = UpdateFastestCasterGUID(PLAYER_GUID)

	lib.callbacks:Fire(
		"ResCast_Started",
		casterGUID,
		PLAYER_GUID,
		casterInfo,
		GetCallbackTargetInfo(PLAYER_GUID, casterGUID)
	)
	FireFastestResChanged(targetInfo)

	local delay = currentCastInfo.endTime - GetTime()

	if delay <= 0 then
		FinishExternalResCast(casterGUID, PLAYER_GUID)
	else
		After(delay, function()
			FinishExternalResCast(casterGUID, PLAYER_GUID)
		end)
	end
end

-- A resurrection cast is interrupted or fails before completion.
--
-- Terminal callbacks fire before cleanup so consumers can still inspect the
-- cast that just ended. Cleanup happens immediately afterward; any resulting
-- fastest-caster changes are then reported separately.
-- UNIT_SPELLCAST_STOP is deliberately not registered: it reports that the cast
-- bar ended, not whether the spell succeeded or failed.
local function UNIT_SPELLCAST_FAILED(unitID, castGUID, spellID, castBarID)
	if not IsTrackedSpellcastUnit(unitID) then return end
	if not canaccessvalue(spellID) or not canaccessvalue(castBarID) then return end
	if not canaccessvalue(castGUID) then castGUID = nil end
	if not SINGLE_TARGET_RES_SPELLS[spellID] and not MASS_RES_SPELLS[spellID] then return end

	local casterGUID = GetAccessibleUnitGUID(unitID)
	if not casterGUID then return end
	if IsTerminalCast(casterGUID, castGUID, castBarID) then return end

	if unitID == "player" and PlayerSentCastMatches(playerSentCastInfo, castGUID, spellID) then
		playerSentCastInfo = nil
	end

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local casterInfo = resCasterInfo[casterGUID]
		if not casterInfo then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end
		if not CastMatches(casterInfo, castGUID, castBarID) then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end

		StopSingleResCast(casterGUID, casterInfo.targetGUID, castGUID, castBarID)
	elseif MASS_RES_SPELLS[spellID] then
		local casterInfo = massResCasterInfo[casterGUID]
		if not casterInfo then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end
		if not CastMatches(casterInfo, castGUID, castBarID) then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end

		MarkTerminalCast(casterGUID, castGUID or casterInfo.castGUID, castBarID or casterInfo.castBarID)
		lib.callbacks:Fire("MassResCast_Stopped", casterGUID, NormalizeCallbackTable(casterInfo))

		local _, changedTargetInfo = RemoveMassResCast(casterGUID, true)

		FireFastestResChangedList(changedTargetInfo)
	end
end

-- INTERRUPTED inserts interruptedBy before the optional castBarID on clients
-- using the current payload. Normalize it to the shared failure handler;
-- clients with older payloads simply omit the trailing values.
local function UNIT_SPELLCAST_INTERRUPTED(unitID, castGUID, spellID, _, castBarID)
	UNIT_SPELLCAST_FAILED(unitID, castGUID, spellID, castBarID)
end

-- A resurrection spellcast reaches Blizzard's successful cast outcome.
--
-- Reliable spells enter the expected-offer state immediately. Engineering
-- devices can complete this event and still fail their resurrection roll, so
-- they remain active briefly and finish only after direct offer confirmation.
-- An untracked single-target success first attempts to resolve its name or
-- name-realm value against addressable group units.
local function UNIT_SPELLCAST_SUCCEEDED(unitID, castGUID, spellID, castBarID)
	if not IsTrackedSpellcastUnit(unitID) then return end
	if not canaccessvalue(spellID) or not canaccessvalue(castBarID) then return end
	if not canaccessvalue(castGUID) then castGUID = nil end
	if not SINGLE_TARGET_RES_SPELLS[spellID] and not MASS_RES_SPELLS[spellID] then return end

	local casterGUID = GetAccessibleUnitGUID(unitID)
	if not casterGUID then return end
	if IsTerminalCast(casterGUID, castGUID, castBarID) then return end

	local sentCastInfo, sentTargetIsExact

	if unitID == "player" and PlayerSentCastMatches(playerSentCastInfo, castGUID, spellID) then
		sentCastInfo = playerSentCastInfo
		sentTargetIsExact = PlayerSentCastMatchesExactly(playerSentCastInfo, castGUID, spellID)
		playerSentCastInfo = nil
	end

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local casterInfo = resCasterInfo[casterGUID]
		local wasTracked = casterInfo ~= nil

		if casterInfo and not CastMatches(casterInfo, castGUID, castBarID) then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end

		local sentTargetGUID = sentCastInfo and sentCastInfo.targetGUID
		local trackedTargetGUID = casterInfo
		and IsKnownTargetGUID(casterInfo.targetGUID)
		and casterInfo.targetGUID
		local spellTargetGUID = ResolveSpellTargetGUID(unitID, spellID)
		local targetGUID = SelectSingleTargetGUID(
			sentTargetGUID,
			sentTargetIsExact,
			trackedTargetGUID,
			spellTargetGUID
		)

		if not wasTracked and not IsValidResurrectionTarget(spellID, targetGUID) then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end

		if wasTracked and casterInfo.targetGUID == UNKNOWN_TARGET_GUID and IsKnownTargetGUID(targetGUID) then
			casterInfo.targetGUID = targetGUID
			ReplaceUnknownTargetGUID(targetGUID, casterGUID)

			lib.callbacks:Fire("ResTargetGUID_Resolved", casterGUID, targetGUID, casterInfo, resTargetInfo[targetGUID])
		end

		if not wasTracked then
			local castInfo = {
				castBarID = castBarID,
				castGUID = castGUID,
				castTime = 0,
				endTime = GetTime(),
				spellID = spellID,
			}

			local storedCasterInfo = StoreSingleCastInfo(casterGUID, targetGUID, castInfo)
			UpdateFastestCasterGUID(targetGUID)

			lib.callbacks:Fire("ResCast_Started", casterGUID, targetGUID, storedCasterInfo, GetCallbackTargetInfo(targetGUID, casterGUID))
		end

		if ENGINEERING_RES_SPELLS[spellID] then
			local activeCasterInfo = resCasterInfo[casterGUID]

			MarkTerminalCast(
				casterGUID,
				castGUID or (activeCasterInfo and activeCasterInfo.castGUID),
				castBarID or (activeCasterInfo and activeCasterInfo.castBarID)
			)
			WaitForEngineeringResOffer(casterGUID)
		else
			FinishSingleResCast(casterGUID, targetGUID, true)
		end
	elseif MASS_RES_SPELLS[spellID] then
		local casterInfo = massResCasterInfo[casterGUID]
		if not casterInfo then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end
		if not CastMatches(casterInfo, castGUID, castBarID) then
			MarkTerminalCast(casterGUID, castGUID, castBarID)
			return
		end

		MarkTerminalCast(casterGUID, castGUID or casterInfo.castGUID, castBarID or casterInfo.castBarID)
		MarkMassResTargets(casterGUID)
		StoreRecentFinishedResCast(casterGUID, nil, casterInfo.spellID)

		lib.callbacks:Fire("MassResCast_Finished", casterGUID, NormalizeCallbackTable(massResCasterInfo[casterGUID]))

		RemoveMassResCast(casterGUID, false)
	end
end

-- A target with an expected or confirmed resurrection offer is now alive.
-- Retire every target-owned lookup key and stop any competing casts before the
-- final alive callback is fired.
local function UNIT_HEALTH(unitID)
	unitID = unitID or "player"

	local targetGUID = GetAccessibleUnitGUID(unitID)
	if not targetGUID then return end
	if not resOfferExpireTimes[targetGUID] then return end

	local health = GetAccessibleUnitHealth(unitID)
	if not health or health <= 0 then return end

	ResolveAliveTarget(targetGUID)
end

local function PLAYER_ALIVE_OR_UNGHOST()
	-- PLAYER_ALIVE and PLAYER_UNGHOST do not carry a unit token. Recheck the
	-- player explicitly instead of passing their unrelated payload to UnitGUID.
	UNIT_HEALTH("player")
end

-- A unit gains or loses a self-resurrection aura, or the player's self-res options change.
-- Self-res availability can change through player resurrection options or
-- through aura changes on other visible units.
local function UNIT_AURA(unitID, updateInfo)
	if unitID == "player" then
		UpdatePlayerSelfResOptions()
	elseif UnitAuraUpdateMayAffectSelfRes(unitID, updateInfo) then
		UpdateUnitSelfResAuras(unitID)
	end
end

eventHandlers.INCOMING_RESURRECT_CHANGED = INCOMING_RESURRECT_CHANGED
eventHandlers.NEUTRAL_FACTION_SELECT_RESULT = NEUTRAL_FACTION_SELECT_RESULT
eventHandlers.PLAYER_ALIVE = PLAYER_ALIVE_OR_UNGHOST
eventHandlers.PLAYER_LOGIN = PLAYER_LOGIN
eventHandlers.PLAYER_UNGHOST = PLAYER_ALIVE_OR_UNGHOST
eventHandlers.RESURRECT_REQUEST = RESURRECT_REQUEST
eventHandlers.UNIT_AURA = UNIT_AURA
eventHandlers.UNIT_HEALTH = UNIT_HEALTH
eventHandlers.UNIT_SPELLCAST_FAILED = UNIT_SPELLCAST_FAILED
eventHandlers.UNIT_SPELLCAST_FAILED_QUIET = UNIT_SPELLCAST_FAILED
eventHandlers.UNIT_SPELLCAST_INTERRUPTED = UNIT_SPELLCAST_INTERRUPTED
eventHandlers.UNIT_SPELLCAST_SENT = UNIT_SPELLCAST_SENT
eventHandlers.UNIT_SPELLCAST_START = UNIT_SPELLCAST_START
eventHandlers.UNIT_SPELLCAST_SUCCEEDED = UNIT_SPELLCAST_SUCCEEDED

-- -------------------------------------------------------------------
-- Public APIs
-- -------------------------------------------------------------------

---@param unit string
---@return boolean isBeingResurrected
---@return string|nil fastestGUID
---@return number|nil fastestRemainingTime
---@return "SINGLE"|"MASS"|nil fastestResType
function lib:IsUnitBeingResurrected(unit)
	local targetGUID = ResolvePublicUnitArg(unit)
	if not targetGUID then
		return false, nil, nil, nil
	end

	local targetInfo = resTargetInfo[targetGUID]
	local fastestGUID = targetInfo and targetInfo.fastestCasterGUID
	local fastestResType = targetInfo and targetInfo.fastestResType

	if not fastestGUID or not fastestResType then
		local unitID = GetAccessibleUnitTokenFromGUID(targetGUID)

		if unitID and IsAccessibleUnitDeadOrGhost(unitID) then
			local fastestMassResGUID, fastestRemainingTime = GetFastestMassResForTarget(targetGUID)

			if fastestMassResGUID then
				return true, fastestMassResGUID, fastestRemainingTime, "MASS"
			end
		end

		return false, nil, nil, nil
	end

	local casterInfo = fastestResType == "MASS" and massResCasterInfo[fastestGUID] or resCasterInfo[fastestGUID]
	local fastestRemainingTime = casterInfo and casterInfo.endTime and (casterInfo.endTime - GetTime()) or 0

	if fastestRemainingTime < 0 then
		fastestRemainingTime = 0
	end

	return true, fastestGUID, fastestRemainingTime, fastestResType
end

---@return boolean isMassResBeingCast
---@return string|nil fastestMassResGUID
---@return number|nil fastestRemainingTime
function lib:IsMassResBeingCast()
	local fastestMassResGUID, fastestRemainingTime = GetFastestMassResInfo()

	if fastestMassResGUID then
		return true, fastestMassResGUID, fastestRemainingTime
	end

	return false, nil, nil
end

---@param unit string
---@return boolean hasResWaiting
---@return number|nil remainingTime
function lib:UnitHasResWaiting(unit)
	local targetGUID = ResolvePublicUnitArg(unit)
	if not targetGUID then
		return false, nil
	end

	local expireTime = resOfferExpireTimes[targetGUID]
	if not expireTime then
		return false, nil
	end

	local remainingTime = expireTime - GetTime()

	if remainingTime <= 0 then
		return false, nil
	end

	return true, remainingTime
end

---@param unit string
---@return boolean canSelfResurrect
---@return table|nil selfResInfo
function lib:UnitCanSelfResurrect(unit)
	local unitGUID = ResolvePublicUnitArg(unit)
	if not unitGUID then
		return false, nil
	end

	local options = selfResInfo[unitGUID]
	if not options then
		return false, nil
	end

	local firstOption
	local multipleOptions

	for _, optionInfo in pairs(options) do
		if firstOption then
			multipleOptions = true
			break
		end

		firstOption = optionInfo
	end

	if not firstOption then
		return false, nil
	end

	if multipleOptions then
		return true, options
	end

	return true, firstOption
end

---@param unit string
---@return number|false endTime
---@return string|nil targetGUID
---@return "SINGLE"|"MASS"|nil resType
function lib:GetResurrectionCastInfo(unit)
	local casterGUID = ResolvePublicUnitArg(unit)
	if not casterGUID then
		return false, nil, nil
	end

	local casterInfo = resCasterInfo[casterGUID]
	if casterInfo then
		return casterInfo.endTime, casterInfo.targetGUID, "SINGLE"
	end

	local massInfo = massResCasterInfo[casterGUID]
	if massInfo then
		return massInfo.endTime, nil, "MASS"
	end

	return false, nil, nil
end

---@param unit string
---@return table|nil casterInfo
function lib:GetCasterInfo(unit)
	local casterGUID = ResolvePublicUnitArg(unit)
	if not casterGUID then
		return nil
	end

	return resCasterInfo[casterGUID] or massResCasterInfo[casterGUID]
end

---@param unit string
---@return table|nil targetInfo
function lib:GetTargetInfo(unit)
	local targetGUID = ResolvePublicUnitArg(unit)
	if not targetGUID then
		return nil
	end

	return resTargetInfo[targetGUID]
end

---@param unit string
---@return table<string, "SINGLE"|"MASS">|nil casters
function lib:GetAllCastersForUnit(unit)
	local targetGUID = ResolvePublicUnitArg(unit)
	if not targetGUID then
		return nil
	end

	local casters
	local targetInfo = resTargetInfo[targetGUID]

	if targetInfo then
		for casterGUID, info in pairs(targetInfo) do
			if type(info) == "table" then
				casters = casters or {}
				casters[casterGUID] = "SINGLE"
			end
		end
	end

	local unitID = GetAccessibleUnitTokenFromGUID(targetGUID)

	if unitID and IsAccessibleUnitDeadOrGhost(unitID) then
		for casterGUID, targets in pairs(massResTargetGUIDs) do
			if targets[targetGUID] then
				casters = casters or {}
				casters[casterGUID] = "MASS"
			end
		end
	end

	return casters
end

-- -------------------------------------------------------------------
-- Embed mixins into target addon objects
-- -------------------------------------------------------------------

local mixins = {
	"GetAllCastersForUnit",
	"GetCasterInfo",
	"GetResurrectionCastInfo",
	"GetTargetInfo",
	"IsMassResBeingCast",
	"IsUnitBeingResurrected",
	"RegisterCallback",
	"UnitCanSelfResurrect",
	"UnitHasResWaiting",
	"UnregisterAllResInfoCallbacks",
	"UnregisterCallback",
}

function lib:Embed(target)
	for _, methodName in pairs(mixins) do
		target[methodName] = self[methodName]
	end

	self.embeds[target] = true
	return target
end

for target in pairs(lib.embeds) do
	lib:Embed(target)
end