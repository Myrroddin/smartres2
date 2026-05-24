--[[--------------------------------------------------------------------
LibResInfo-2.0

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
- Spell and aura logic is ID-based; names are not used for logic.
----------------------------------------------------------------------]]

assert(LibStub, "LibResInfo-2.0 requires LibStub")
assert(LibStub("CallbackHandler-1.0", true), "LibResInfo-2.0 requires CallbackHandler-1.0")

---@class LibResInfo-2.0: table
local lib = LibStub:NewLibrary("LibResInfo-2.0", 1)
if not lib then return end

---@alias ResType "SINGLE"|"MASS"
---@alias SelfResOptionTable table<string, SelfResOptionInfo>
---@alias ResCasterTable table<string, ResType>

-- Callback names accepted by RegisterCallback and UnregisterCallback.
---@alias LibResInfoCallback
---| "ResCast_Started"
---| "ResCast_Finished"
---| "ResCast_Stopped"
---| "MassResCast_Started"
---| "MassResCast_Finished"
---| "MassResCast_Stopped"
---| "FastestRes_Changed"
---| "ResTargetGUID_Resolved"
---| "ResTargetGUID_IsAlive"
---| "UnitSelfRes_Available"
---| "UnitSelfRes_Consumed"

---@class CallbackHandlerRegistry
---@field RegisterCallback fun(self: table, eventName: LibResInfoCallback, method?: string|function)
---@field UnregisterCallback fun(self: table, eventName: LibResInfoCallback)
---@field UnregisterAllCallbacks fun(self: CallbackHandlerRegistry, target: table)

---@class NamePlateFrame
---@field unitToken string

---@class ResCastInfo
---@field castGUID? string
---@field casterGUID string
---@field castTime? number
---@field spellID integer
---@field targetGUID? string
---@field textureID? integer
---@field endTime? number

---@class ResTargetInfo
---@field targetGUID string
---@field fastestCasterGUID? string
---@field fastestResType? ResType

---@class SelfResurrectOption
---@field spellID? integer
---@field itemID? integer
---@field auraInstanceID? integer
---@field expirationTime? number

---@class SelfResOptionInfo
---@field unitGUID string
---@field spellID? integer
---@field itemID? integer
---@field auraInstanceID? integer
---@field expirationTime? number

---@type CallbackHandlerRegistry
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib,
	"RegisterCallback",
	"UnregisterCallback",
	"UnregisterAllResInfoCallbacks"
)
lib.embeds = lib.embeds or {}

function lib:UnregisterAllResInfoCallbacks()
	self.callbacks:UnregisterAllCallbacks(self)
end

-- -------------------------------------------------------------------
-- Event frame
-- -------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, ...)
	local handler = lib[event]
	if handler then
		handler(lib, event, ...)
	end
end)

frame:RegisterEvent("PLAYER_LOGIN")

-- -------------------------------------------------------------------
-- WoW API
-- -------------------------------------------------------------------

local UnitGUID = UnitGUID
local UnitCastingInfo = UnitCastingInfo
local UnitName = UnitName
local UnitTokenFromGUID = UnitTokenFromGUID
local UnitSpellTargetName = UnitSpellTargetName
local UnitHealth = UnitHealth
local UnitExists = UnitExists
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitAffectingCombat = UnitAffectingCombat

local GetTime = GetTime
local GetNumGroupMembers = GetNumGroupMembers
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local IsPlayerNeutral = IsPlayerNeutral
local UnitFactionGroup = UnitFactionGroup
local InCombatLockdown = InCombatLockdown

local GetNamePlates = C_NamePlate.GetNamePlates
local After = C_Timer.After
local GetUnitAuraBySpellID = C_UnitAuras.GetUnitAuraBySpellID
local GetSelfResurrectOptions = C_DeathInfo.GetSelfResurrectOptions

local wipe = table.wipe
local pairs = pairs
local next = next
local type = type

-- -------------------------------------------------------------------
-- Constants
-- -------------------------------------------------------------------

local UNKNOWN_TARGET_GUID = "UNKNOWN"
local RES_PENDING_TIMEOUT = 60

local PLAYER_GUID
local isMists = WOW_PROJECT_ID == WOW_PROJECT_MISTS_CLASSIC
local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

-- -------------------------------------------------------------------
-- Internal state
-- -------------------------------------------------------------------

-- Active single-target resurrection casts, keyed by caster GUID.
---@type table<string, ResCastInfo>
local resCasterInfo = {}

-- Active mass resurrection casts, keyed by caster GUID.
---@type table<string, ResCastInfo>
local massResCasterInfo = {}

-- Active single-target resurrection casts, keyed by target GUID, then caster GUID.
---@type table<string, ResTargetInfo>
local resTargetInfo = {}

-- Targets whose resurrection cast finished, but whose alive state has not yet been observed.
---@type table<string, true>
local ressedTargetGUIDs = {}

-- Self-resurrection options, keyed by unit GUID, then option key.
---@type table<string, table<string, SelfResOptionInfo>>
local selfResInfo = {}

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
	[982]		= true,		-- Revive Pet

	-- Evoker
	[361227]	= true,		-- Return

	-- Death Knight
	[61999]		= true,		-- Raise Ally

	-- Engineering
	[8342]		= true,		-- Goblin Jumper Cables
	[22999]		= true,		-- Goblin Jumper Cables XL
	[54732]		= true,		-- Gnomish Army Knife
	[164729]	= true,		-- Ultimate Gnomish Army Knife
	[385404]	= true,		-- Arclight Vital Correctors

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

local MASS_RES_SPELLS = {
	-- Paladin
	[212056]	= true,		-- Absolution

	-- Shaman
	[212048]	= true,		-- Ancestral Vision

	-- Priest
	[212036]	= true,		-- Mass Resurrection

	-- Monk
	[212051]	= true,		-- Reawaken

	-- Druid
	[212040]	= true,		-- Revitalize

	-- Evoker
	[361178]	= true,		-- Mass Return
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
	["RESURRECT_REQUEST"]			= true,
	["UNIT_AURA"]					= true,
	["UNIT_HEALTH"]					= true,
	["UNIT_SPELLCAST_FAILED"]		= true,
	["UNIT_SPELLCAST_FAILED_QUIET"]	= true,
	["UNIT_SPELLCAST_INTERRUPTED"]	= true,
	["UNIT_SPELLCAST_SENT"]			= true,
	["UNIT_SPELLCAST_START"]		= true,
	["UNIT_SPELLCAST_STOP"]			= true,
	["UNIT_SPELLCAST_SUCCEEDED"]	= true,
	["PLAYER_ALIVE"]				= true,
	["PLAYER_UNGHOST"]				= true,
}

-- -------------------------------------------------------------------
-- Shared helpers
-- -------------------------------------------------------------------

local function NormalizeCallbackTable(info)
	if info and not next(info) then
		return nil
	end

	return info
end

local function SetIfMissing(info, key, value)
	if info[key] == nil then
		info[key] = value
	end
end

local function SetIfPresent(info, key, value)
	if value ~= nil then
		info[key] = value
	end
end

local function GetCastTimes(startTimeMs, endTimeMs)
	local castTime = (startTimeMs and endTimeMs) and ((endTimeMs - startTimeMs) / 1000) or 0
	local endTime = endTimeMs and (endTimeMs / 1000) or GetTime()

	return castTime, endTime
end

local function HasTableEntries(info)
	if not info then return end

	for _, value in pairs(info) do
		if type(value) == "table" then
			return true
		end
	end
end

-- -------------------------------------------------------------------
-- Fastest-caster helpers
-- -------------------------------------------------------------------

-- Recalculate the fastest active resurrection for one target.
local function UpdateFastestCasterGUID(targetGUID)
	if not targetGUID or not resTargetInfo[targetGUID] then return end

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

	for casterGUID, casterInfo in pairs(massResCasterInfo) do
		if type(casterInfo) == "table" and casterInfo.endTime then
			if not fastestEndTime or casterInfo.endTime < fastestEndTime then
				fastestCasterGUID = casterGUID
				fastestResType = "MASS"
				fastestEndTime = casterInfo.endTime
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

local function GetFastestMassResCasterGUID()
	local fastestCasterGUID
	local fastestEndTime

	for casterGUID, casterInfo in pairs(massResCasterInfo) do
		if type(casterInfo) == "table" and casterInfo.endTime then
			if not fastestEndTime or casterInfo.endTime < fastestEndTime then
				fastestCasterGUID = casterGUID
				fastestEndTime = casterInfo.endTime
			end
		end
	end

	return fastestCasterGUID
end

local function IsUnitGUID(value)
	return type(value) == "string" and value:find("^%a+%-%d") ~= nil
end

local function ResolvePublicUnitArg(unit)
	local unitType = type(unit)

	if unitType ~= "string" then
		error(("bad argument #1, expected a unitID, GUID, or unit name, got %s"):format(unitType), 3)
	end

	if unit == "" or unit == UNKNOWN_TARGET_GUID then
		error(("bad argument #1, expected a unitID, GUID, or unit name, got %q"):format(unit), 3)
	end

	local unitGUID = UnitGUID(unit)
	if unitGUID then
		return unitGUID
	end

	if IsUnitGUID(unit) then
		return unit
	end

	-- Unresolved names are valid input, but Blizzard may not expose their GUID.
	return nil
end

-- -------------------------------------------------------------------
-- Active resurrection state
-- -------------------------------------------------------------------

local function ApplySingleCastInfo(casterInfo, targetInfo, casterGUID, targetGUID, castInfo)
	SetIfMissing(casterInfo, "castGUID", castInfo.castGUID)
	SetIfMissing(casterInfo, "casterGUID", casterGUID)
	SetIfMissing(casterInfo, "castTime", castInfo.castTime)
	SetIfMissing(casterInfo, "spellID", castInfo.spellID)
	SetIfMissing(casterInfo, "targetGUID", targetGUID)
	SetIfMissing(casterInfo, "textureID", castInfo.textureID)
	SetIfMissing(casterInfo, "endTime", castInfo.endTime)

	SetIfMissing(targetInfo, "castGUID", castInfo.castGUID)
	SetIfMissing(targetInfo, "casterGUID", casterGUID)
	SetIfMissing(targetInfo, "castTime", castInfo.castTime)
	SetIfMissing(targetInfo, "spellID", castInfo.spellID)
	SetIfMissing(targetInfo, "targetGUID", targetGUID)
	SetIfMissing(targetInfo, "textureID", castInfo.textureID)
	SetIfMissing(targetInfo, "endTime", castInfo.endTime)
end

local function ApplyMassCastInfo(casterInfo, casterGUID, castInfo)
	SetIfMissing(casterInfo, "castGUID", castInfo.castGUID)
	SetIfMissing(casterInfo, "casterGUID", casterGUID)
	SetIfMissing(casterInfo, "castTime", castInfo.castTime)
	SetIfMissing(casterInfo, "spellID", castInfo.spellID)
	SetIfMissing(casterInfo, "textureID", castInfo.textureID)
	SetIfMissing(casterInfo, "endTime", castInfo.endTime)
end

local function GetCurrentCastInfo(unitID)
	local spellName, _, textureID, startTimeMs, endTimeMs, _, castGUID, _, spellID = UnitCastingInfo(unitID)
	if not spellName or not spellID then return end

	local castTime, endTime = GetCastTimes(startTimeMs, endTimeMs)

	return {
		castGUID = castGUID,
		castTime = castTime,
		endTime = endTime,
		spellID = spellID,
		textureID = textureID,
	}
end

local function PopulateSingleResInfo(unitID, casterGUID, castInfo)
	local existingCasterInfo = resCasterInfo[casterGUID]
	local existingTargetGUID = existingCasterInfo and existingCasterInfo.targetGUID

	local targetName = UnitSpellTargetName(unitID)
	local targetGUID = UnitGUID(targetName) or existingTargetGUID or UNKNOWN_TARGET_GUID

	resCasterInfo[casterGUID] = resCasterInfo[casterGUID] or {}
	resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
	resTargetInfo[targetGUID].targetGUID = resTargetInfo[targetGUID].targetGUID or targetGUID
	resTargetInfo[targetGUID][casterGUID] = resTargetInfo[targetGUID][casterGUID] or {}

	ApplySingleCastInfo(resCasterInfo[casterGUID], resTargetInfo[targetGUID][casterGUID], casterGUID, targetGUID, castInfo)

	return targetGUID, UpdateFastestCasterGUID(targetGUID)
end

local function PopulateMassResInfo(casterGUID, castInfo)
	massResCasterInfo[casterGUID] = massResCasterInfo[casterGUID] or {}

	ApplyMassCastInfo(massResCasterInfo[casterGUID], casterGUID, castInfo)

	return UpdateAllFastestCasterGUIDs()
end

local function PopulateResInfoTables(unitID)
	local casterGUID = UnitGUID(unitID)
	if not casterGUID then return end

	local castInfo = GetCurrentCastInfo(unitID)
	if not castInfo then return end

	if SINGLE_TARGET_RES_SPELLS[castInfo.spellID] then
		local targetGUID, fastestTargetInfo = PopulateSingleResInfo(unitID, casterGUID, castInfo)
		return "SINGLE", casterGUID, targetGUID, fastestTargetInfo
	elseif MASS_RES_SPELLS[castInfo.spellID] then
		local fastestTargetInfo = PopulateMassResInfo(casterGUID, castInfo)
		return "MASS", casterGUID, nil, fastestTargetInfo
	end
end

-- Move an unresolved target entry to its resolved GUID.
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

local function RemoveMassResCast(casterGUID, updateFastest)
	if not casterGUID then return end

	local removedCasterInfo = massResCasterInfo[casterGUID]

	massResCasterInfo[casterGUID] = nil

	local changedTargetInfo
	if updateFastest then
		changedTargetInfo = UpdateAllFastestCasterGUIDs()
	end

	return NormalizeCallbackTable(removedCasterInfo), changedTargetInfo
end

local function RemoveTargetResInfo(targetGUID)
	if not targetGUID or not resTargetInfo[targetGUID] then return end

	for casterGUID, info in pairs(resTargetInfo[targetGUID]) do
		if type(info) == "table" then
			resCasterInfo[casterGUID] = nil
		end
	end

	resTargetInfo[targetGUID] = nil

	return true
end

local function RemoveExpiredUnknownTargetInfo()
	local targetInfo = resTargetInfo[UNKNOWN_TARGET_GUID]
	if not targetInfo then return end

	local now = GetTime()
	local removed

	for casterGUID, info in pairs(targetInfo) do
		if type(info) == "table" and info.endTime and (now - info.endTime) >= RES_PENDING_TIMEOUT then
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
-- Completed resurrection state
-- -------------------------------------------------------------------

local function MarkRessedTargetGUID(targetGUID)
	if targetGUID and targetGUID ~= UNKNOWN_TARGET_GUID then
		ressedTargetGUIDs[targetGUID] = true
	end
end

local function MarkMassResTargets()
	local playerGUID = UnitGUID("player")

	if playerGUID and UnitIsDeadOrGhost("player") then
		ressedTargetGUIDs[playerGUID] = true
	end

	local prefix = IsInRaid() and "raid" or "party"
	local members = GetNumGroupMembers()

	for i = 1, members do
		local unitID = prefix .. i

		if UnitExists(unitID) and UnitIsDeadOrGhost(unitID) then
			local targetGUID = UnitGUID(unitID)
			if targetGUID then
				ressedTargetGUIDs[targetGUID] = true
			end
		end
	end
end

-- -------------------------------------------------------------------
-- Self-resurrection state
-- -------------------------------------------------------------------

local function GetSelfResOptionKey(optionInfo)
	if optionInfo.spellID then
		return "spell:" .. optionInfo.spellID
	elseif optionInfo.itemID then
		return "item:" .. optionInfo.itemID
	elseif optionInfo.auraInstanceID then
		return "aura:" .. optionInfo.auraInstanceID
	end
end

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

local function UpdatePlayerSelfResOptions()
	if not GetSelfResurrectOptions then return end

	local unitGUID = PLAYER_GUID or UnitGUID("player")
	if not unitGUID then return end

	local seen = {}

	---@type SelfResurrectOption[]|nil
	local options = GetSelfResurrectOptions()

	if options then
		for _, option in pairs(options) do
			---@type SelfResOptionInfo
			local optionInfo = {
				unitGUID = unitGUID,
			}

			SetIfPresent(optionInfo, "spellID", option.spellID)
			SetIfPresent(optionInfo, "itemID", option.itemID)
			SetIfPresent(optionInfo, "auraInstanceID", option.auraInstanceID)
			SetIfPresent(optionInfo, "expirationTime", option.expirationTime)

			local optionKey = GetSelfResOptionKey(optionInfo)

			if optionKey then
				seen[optionKey] = true
				AddSelfResOption(unitGUID, optionInfo)
			end
		end
	end

	if selfResInfo[unitGUID] then
		for optionKey in pairs(selfResInfo[unitGUID]) do
			if not seen[optionKey] then
				RemoveSelfResOption(unitGUID, optionKey)
			end
		end
	end
end

local function UpdateUnitSelfResAuras(unitID)
	if not unitID then return end

	local unitGUID = UnitGUID(unitID)
	if not unitGUID then return end

	local seen = {}

	for spellID in pairs(SELF_RES_AURAS) do
		local aura = GetUnitAuraBySpellID(unitID, spellID)

		if aura then
			---@type SelfResOptionInfo
			local optionInfo = {
				unitGUID = unitGUID,
				spellID = spellID,
			}

			SetIfPresent(optionInfo, "auraInstanceID", aura.auraInstanceID)
			SetIfPresent(optionInfo, "expirationTime", aura.expirationTime)

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

-- -------------------------------------------------------------------
-- External resurrection request helpers
-- -------------------------------------------------------------------

local function UnitMatchesName(unitID, name)
	if not unitID or not name then return end

	local unitName, unitRealm = UnitName(unitID)
	if not unitName then return end

	if name == unitName then
		return true
	end

	if unitRealm and unitRealm ~= "" and name == unitName .. "-" .. unitRealm then
		return true
	end
end

local function FinishExternalResCast(casterGUID, targetGUID)
	local casterInfo = resCasterInfo[casterGUID]
	if not casterInfo then return end
	if casterInfo.targetGUID ~= targetGUID then return end

	local finishedCasterInfo = resCasterInfo[casterGUID]
	local finishedTargetInfo = resTargetInfo[targetGUID]

	MarkRessedTargetGUID(targetGUID)

	lib.callbacks:Fire("ResCast_Finished", casterGUID, targetGUID, NormalizeCallbackTable(finishedCasterInfo), NormalizeCallbackTable(finishedTargetInfo))

	RemoveSingleResCast(casterGUID, targetGUID, false, false)
end

-- -------------------------------------------------------------------
-- Event aliases and registration
-- -------------------------------------------------------------------

local function RegisterEvents()
	lib.UNIT_SPELLCAST_FAILED		= lib.UNIT_SPELLCAST_STOP
	lib.UNIT_SPELLCAST_FAILED_QUIET	= lib.UNIT_SPELLCAST_STOP
	lib.UNIT_SPELLCAST_INTERRUPTED	= lib.UNIT_SPELLCAST_STOP
	lib.PLAYER_ALIVE				= lib.UNIT_HEALTH
	lib.PLAYER_UNGHOST				= lib.UNIT_HEALTH

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
function lib:PLAYER_LOGIN()
	PLAYER_GUID = PLAYER_GUID or UnitGUID("player")

	wipe(resCasterInfo)
	wipe(massResCasterInfo)
	wipe(resTargetInfo)
	wipe(ressedTargetGUIDs)
	wipe(selfResInfo)

	RegisterEvents()

	if IsPlayerNeutral() and (isMists or isMainline) then
		frame:RegisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
	end

	UpdatePlayerSelfResOptions()
end

function lib:NEUTRAL_FACTION_SELECT_RESULT(_, success)
	if success then
		local factionGroup = UnitFactionGroup("player")

		if factionGroup == "Alliance" or factionGroup == "Horde" then
			PLAYER_GUID = UnitGUID("player")
			frame:UnregisterEvent("NEUTRAL_FACTION_SELECT_RESULT")
		end
	end
end

-- Player spell targeting is available before the cast starts.
function lib:UNIT_SPELLCAST_SENT(_, unitID, targetID, castGUID, spellID)
	local endTime = GetTime()

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local targetGUID = UnitGUID(targetID) or UNKNOWN_TARGET_GUID

		resCasterInfo[PLAYER_GUID] = resCasterInfo[PLAYER_GUID] or {}
		resCasterInfo[PLAYER_GUID].castGUID = castGUID
		resCasterInfo[PLAYER_GUID].casterGUID = PLAYER_GUID
		resCasterInfo[PLAYER_GUID].spellID = spellID
		resCasterInfo[PLAYER_GUID].targetGUID = targetGUID
		resCasterInfo[PLAYER_GUID].endTime = endTime

		resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
		resTargetInfo[targetGUID].targetGUID = targetGUID
		resTargetInfo[targetGUID][PLAYER_GUID] = resTargetInfo[targetGUID][PLAYER_GUID] or {}
		resTargetInfo[targetGUID][PLAYER_GUID].castGUID = castGUID
		resTargetInfo[targetGUID][PLAYER_GUID].casterGUID = PLAYER_GUID
		resTargetInfo[targetGUID][PLAYER_GUID].spellID = spellID
		resTargetInfo[targetGUID][PLAYER_GUID].targetGUID = targetGUID
		resTargetInfo[targetGUID][PLAYER_GUID].endTime = endTime
	elseif MASS_RES_SPELLS[spellID] then
		massResCasterInfo[PLAYER_GUID] = massResCasterInfo[PLAYER_GUID] or {}
		massResCasterInfo[PLAYER_GUID].castGUID = castGUID
		massResCasterInfo[PLAYER_GUID].casterGUID = PLAYER_GUID
		massResCasterInfo[PLAYER_GUID].spellID = spellID
		massResCasterInfo[PLAYER_GUID].endTime = endTime
	end

	local resType, casterGUID, targetGUID, fastestTargetInfo = PopulateResInfoTables(unitID)

	if resType == "SINGLE" then
		lib.callbacks:Fire("ResCast_Started", casterGUID, targetGUID, resCasterInfo[casterGUID], resTargetInfo[targetGUID])

		if fastestTargetInfo then
			lib.callbacks:Fire("FastestRes_Changed", fastestTargetInfo.targetGUID, fastestTargetInfo)
		end
	elseif resType == "MASS" then
		lib.callbacks:Fire("MassResCast_Started", casterGUID, massResCasterInfo[casterGUID])

		if fastestTargetInfo then
			for _, targetInfo in pairs(fastestTargetInfo) do
				lib.callbacks:Fire("FastestRes_Changed", targetInfo.targetGUID, targetInfo)
			end
		end
	end
end

function lib:UNIT_SPELLCAST_START(_, unitID)
	local resType, casterGUID, targetGUID, fastestTargetInfo = PopulateResInfoTables(unitID)

	if resType == "SINGLE" then
		lib.callbacks:Fire("ResCast_Started", casterGUID, targetGUID, resCasterInfo[casterGUID], resTargetInfo[targetGUID])

		if fastestTargetInfo then
			lib.callbacks:Fire("FastestRes_Changed", fastestTargetInfo.targetGUID, fastestTargetInfo)
		end
	elseif resType == "MASS" then
		lib.callbacks:Fire("MassResCast_Started", casterGUID, massResCasterInfo[casterGUID])

		if fastestTargetInfo then
			for _, targetInfo in pairs(fastestTargetInfo) do
				lib.callbacks:Fire("FastestRes_Changed", targetInfo.targetGUID, targetInfo)
			end
		end
	end
end

-- Fill in an UNKNOWN target when Blizzard later exposes incoming-res data.
function lib:INCOMING_RESURRECT_CHANGED(_, targetID)
	local targetGUID = UnitGUID(targetID)
	if not targetGUID then return end

	local targetName, targetRealm = UnitName(targetID)

	for _, info in pairs(resCasterInfo) do
		if info.targetGUID == UNKNOWN_TARGET_GUID then
			local casterGUID = info.casterGUID
			local casterID = UnitTokenFromGUID(casterGUID)

			if casterID then
				local spellTargetName = UnitSpellTargetName(casterID)

				if spellTargetName and (spellTargetName == targetName or spellTargetName == (targetRealm and targetName .. "-" .. targetRealm)) then
					info.targetGUID = targetGUID
					ReplaceUnknownTargetGUID(targetGUID, casterGUID)

					lib.callbacks:Fire("ResTargetGUID_Resolved", casterGUID, targetGUID, resCasterInfo[casterGUID], resTargetInfo[targetGUID])
				end
			end
		end
	end
end

-- External resurrection requests only target the player.
function lib:RESURRECT_REQUEST(_, inviterName)
	if IsInInstance() then return end
	if InCombatLockdown() or UnitAffectingCombat("player") then return end

	for _, nameplate in pairs(GetNamePlates()) do
		local unitID = nameplate.unitToken

		if UnitMatchesName(unitID, inviterName) then
			local casterGUID = UnitGUID(unitID)
			if not casterGUID then return end

			local castInfo = GetCurrentCastInfo(unitID)
			if not castInfo or not SINGLE_TARGET_RES_SPELLS[castInfo.spellID] then return end

			local targetGUID = PLAYER_GUID

			resCasterInfo[casterGUID] = resCasterInfo[casterGUID] or {}
			resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
			resTargetInfo[targetGUID].targetGUID = targetGUID
			resTargetInfo[targetGUID][casterGUID] = resTargetInfo[targetGUID][casterGUID] or {}

			ApplySingleCastInfo(resCasterInfo[casterGUID], resTargetInfo[targetGUID][casterGUID], casterGUID, targetGUID, castInfo)

			local targetInfo = UpdateFastestCasterGUID(targetGUID)

			lib.callbacks:Fire("ResCast_Started", casterGUID, targetGUID, resCasterInfo[casterGUID], resTargetInfo[targetGUID])

			if targetInfo then
				lib.callbacks:Fire("FastestRes_Changed", targetInfo.targetGUID, targetInfo)
			end

			local delay = castInfo.endTime - GetTime()

			if delay <= 0 then
				FinishExternalResCast(casterGUID, targetGUID)
			else
				After(delay, function()
					FinishExternalResCast(casterGUID, targetGUID)
				end)
			end

			return
		end
	end
end

-- A resurrection cast is interrupted, fails, or is otherwise stopped before completion.
function lib:UNIT_SPELLCAST_STOP(_, unitID, castGUID, spellID)
	local casterGUID = UnitGUID(unitID)
	if not casterGUID then return end

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local casterInfo = resCasterInfo[casterGUID]
		if not casterInfo then return end
		if casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		local targetGUID = casterInfo.targetGUID or UNKNOWN_TARGET_GUID
		local removedCasterInfo, targetInfo, changedTargetInfo = RemoveSingleResCast(casterGUID, targetGUID, true, false)

		lib.callbacks:Fire("ResCast_Stopped", casterGUID, targetGUID, removedCasterInfo, targetInfo)

		if changedTargetInfo then
			lib.callbacks:Fire("FastestRes_Changed", changedTargetInfo.targetGUID, changedTargetInfo)
		end
	elseif MASS_RES_SPELLS[spellID] then
		local casterInfo = massResCasterInfo[casterGUID]
		if not casterInfo then return end
		if casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		local removedCasterInfo, changedTargetInfo = RemoveMassResCast(casterGUID, true)

		lib.callbacks:Fire("MassResCast_Stopped", casterGUID, removedCasterInfo)

		if changedTargetInfo then
			for _, targetInfo in pairs(changedTargetInfo) do
				lib.callbacks:Fire("FastestRes_Changed", targetInfo.targetGUID, targetInfo)
			end
		end
	end
end

-- A resurrection cast successfully finishes, but the target may not be alive yet.
function lib:UNIT_SPELLCAST_SUCCEEDED(_, unitID, castGUID, spellID)
	local casterGUID = UnitGUID(unitID)
	if not casterGUID then return end

	if SINGLE_TARGET_RES_SPELLS[spellID] then
		local casterInfo = resCasterInfo[casterGUID]
		local wasTracked = casterInfo ~= nil

		if casterInfo and casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		local targetGUID = wasTracked and (casterInfo.targetGUID or UNKNOWN_TARGET_GUID) or (UnitGUID(UnitSpellTargetName(unitID)) or UNKNOWN_TARGET_GUID)

		if not wasTracked then
			local castInfo = {
				castGUID = castGUID,
				castTime = 0,
				endTime = GetTime(),
				spellID = spellID,
			}

			resCasterInfo[casterGUID] = resCasterInfo[casterGUID] or {}
			resTargetInfo[targetGUID] = resTargetInfo[targetGUID] or {}
			resTargetInfo[targetGUID].targetGUID = targetGUID
			resTargetInfo[targetGUID][casterGUID] = resTargetInfo[targetGUID][casterGUID] or {}

			ApplySingleCastInfo(resCasterInfo[casterGUID], resTargetInfo[targetGUID][casterGUID], casterGUID, targetGUID, castInfo)
			UpdateFastestCasterGUID(targetGUID)

			lib.callbacks:Fire("ResCast_Started", casterGUID, targetGUID, resCasterInfo[casterGUID], resTargetInfo[targetGUID])
		end

		local finishedCasterInfo = resCasterInfo[casterGUID]
		local finishedTargetInfo = resTargetInfo[targetGUID]

		MarkRessedTargetGUID(targetGUID)

		lib.callbacks:Fire("ResCast_Finished", casterGUID, targetGUID, NormalizeCallbackTable(finishedCasterInfo), NormalizeCallbackTable(finishedTargetInfo))

		RemoveSingleResCast(casterGUID, targetGUID, false, false)
	elseif MASS_RES_SPELLS[spellID] then
		local casterInfo = massResCasterInfo[casterGUID]
		if not casterInfo then return end
		if casterInfo.castGUID and castGUID and casterInfo.castGUID ~= castGUID then return end

		MarkMassResTargets()

		lib.callbacks:Fire("MassResCast_Finished", casterGUID, NormalizeCallbackTable(massResCasterInfo[casterGUID]))

		RemoveMassResCast(casterGUID, false)
	end
end

-- A completed resurrection target is now alive.
function lib:UNIT_HEALTH(_, unitID)
	unitID = unitID or "player"

	local targetGUID = UnitGUID(unitID)
	if not targetGUID then return end
	if not ressedTargetGUIDs[targetGUID] then return end
	if not UnitHealth(unitID) or UnitHealth(unitID) <= 0 then return end

	ressedTargetGUIDs[targetGUID] = nil
	RemoveTargetResInfo(targetGUID)

	lib.callbacks:Fire("ResTargetGUID_IsAlive", targetGUID)

	RemoveExpiredUnknownTargetInfo()
end

-- A unit gains or loses a self-resurrection aura, or the player's self-res options change.
function lib:UNIT_AURA(_, unitID)
	if unitID == "player" then
		UpdatePlayerSelfResOptions()
	else
		UpdateUnitSelfResAuras(unitID)
	end
end

-- -------------------------------------------------------------------
-- Public APIs
-- -------------------------------------------------------------------

---@param unit string unitID, GUID, unit name, or name-realm
---@return string|false casterGUID Returns false if no active resurrection exists.
---@return ResType|nil resType
function lib:GetFastestCasterForUnit(unit)
	local targetGUID = ResolvePublicUnitArg(unit)
	if not targetGUID then
		return false, nil
	end

	local targetInfo = resTargetInfo[targetGUID]

	if targetInfo and targetInfo.fastestCasterGUID and targetInfo.fastestResType then
		return targetInfo.fastestCasterGUID, targetInfo.fastestResType
	end

	local unitID = UnitTokenFromGUID(targetGUID)

	if unitID and UnitIsDeadOrGhost(unitID) then
		local casterGUID = GetFastestMassResCasterGUID()

		if casterGUID then
			return casterGUID, "MASS"
		end
	end

	return false, nil
end

---@param unit string unitID, GUID, unit name, or name-realm
---@return boolean isBeingResurrected
function lib:IsUnitBeingResurrected(unit)
	local casterGUID = self:GetFastestCasterForUnit(unit)

	return casterGUID ~= false
end

---@param unit string unitID, GUID, unit name, or name-realm
---@return boolean canSelfRes
---@return SelfResOptionInfo|SelfResOptionTable|nil optionInfo
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

---@param unit string unitID, GUID, unit name, or name-realm
---@return number|false endTime Absolute cast end time, comparable to GetTime()
---@return string|nil targetGUID
---@return ResType|nil resType
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

---@param unit string unitID, GUID, unit name, or name-realm
---@return ResCastInfo|nil casterInfo
function lib:GetCasterInfo(unit)
	local casterGUID = ResolvePublicUnitArg(unit)
	if not casterGUID then
		return nil
	end

	return resCasterInfo[casterGUID] or massResCasterInfo[casterGUID]
end

---@param unit string unitID, GUID, unit name, or name-realm
---@return ResTargetInfo|nil targetInfo
function lib:GetTargetInfo(unit)
	local targetGUID = ResolvePublicUnitArg(unit)
	if not targetGUID then
		return nil
	end

	return resTargetInfo[targetGUID]
end

---@param unit string unitID, GUID, unit name, or name-realm
---@return ResCasterTable|nil casters
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

	local unitID = UnitTokenFromGUID(targetGUID)

	if unitID and UnitIsDeadOrGhost(unitID) then
		for casterGUID in pairs(massResCasterInfo) do
			casters = casters or {}
			casters[casterGUID] = "MASS"
		end
	end

	return casters
end

-- -------------------------------------------------------------------
-- Embed mixins into target addon objects
-- -------------------------------------------------------------------

---@alias LibResInfoMixin
---| "RegisterCallback"
---| "UnregisterCallback"
---| "UnregisterAllResInfoCallbacks"
---| "GetFastestCasterForUnit"
---| "IsUnitBeingResurrected"
---| "UnitCanSelfResurrect"
---| "GetResurrectionCastInfo"
---| "GetCasterInfo"
---| "GetTargetInfo"
---| "GetAllCastersForUnit"

---@type LibResInfoMixin[]
local mixins = {
	"RegisterCallback",
	"UnregisterCallback",
	"UnregisterAllResInfoCallbacks",
	"GetFastestCasterForUnit",
	"IsUnitBeingResurrected",
	"UnitCanSelfResurrect",
	"GetResurrectionCastInfo",
	"GetCasterInfo",
	"GetTargetInfo",
	"GetAllCastersForUnit",
}

---@param target table
---@return table
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