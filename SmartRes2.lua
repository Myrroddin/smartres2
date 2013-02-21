--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Myrroddin of Llane
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- declare addon ------------------------------------------------------------
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0", "LibBars-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)

--@alpha@
local version = GetAddOnMetadata("SmartRes2", "Version")
if version:match("@") then
	version = "Development"
else
	version = "Alpha "..version
end
--@end-alpha@

-- add localisation to addon
SmartRes2.L = L
-- declare the database
local db

-- additional libraries -----------------------------------------------------
local DataBroker = LibStub:GetLibrary("LibDataBroker-1.1")
local Bars = LibStub:GetLibrary("LibBars-1.0")
local ResInfo = LibStub:GetLibrary("LibResInfo-1.0")
local Media = LibStub:GetLibrary("LibSharedMedia-3.0")

Media:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])

-- local variables ----------------------------------------------------------
local resBars = {}
local orientation
local LastRes
local icon
local in_combat = false
local creatorName = {
	"Myrroddin",
	"Jelia",
	"Badash",
	"Vanhoeffen"
}

-- addon defaults -----------------------------------------------------------
local defaults = {
	profile = {
		autoResKey = "",
		barHeight = 16,
		barWidth = 128,
		borderThickness = 10,
		chatOutput = "0-none",
		classColours = true,
		collisionBarsColour = { r = 1, g = 0, b = 0, a = 1 },
		enableAddon = true,
		fontFlags = "nil",
		fontScale = 12,
		fontType = "Friz Quadrata TT",
		hideAnchor = true,
		horizontalOrientation = "RIGHT",
		manualResKey = "",
		massResBarColour = { r = 0.9 , g = 0.8, b = 0.5, a = 1 },
		massResKey = "",
		massResMessage = "",
		maxBars = 10,
		notifyCollision = "0-off",
		notifySelf = true,
		maxBars = 10,
		randMsgs = false,
		resBarsColour = { r = 0, g = 1, b = 0, a = 1 },
		resBarsIcon = true,
		resBarsAlpha = 1,
		resBarsBorder = "None",
		resBarsTexture = "Blizzard",
		resBarsX = 0,
		resBarsY = 600,
		reverseGrowth = false,
		scale = 1,
		showBattleRes = false,
		visibleResBars = true,
		waitingBarsColour = { r = 0, g = 0, b = 1, a = 1 }
	}
}

-- utility methods ---------------------------------------------------------

function SmartRes2:Debug(str, ...)
	--@debug@
	if not str or strlen(str) == 0 then return end
	if (...) then
		if strfind(str, "%%%.%d") or strfind(str, "%%[dfqsx%d]") then
			str = format(str, ...)
		else
			str = strjoin(" ", str, tostringall(...))
		end
	end
	DEFAULT_CHAT_FRAME:AddMessage(format("|cffff9933%s:|r %s", self.name, str))
	--@end-debug@
end

function SmartRes2:Print(str, ...)
	if not str or strlen(str) == 0 then return end
	if (...) then
		if strfind(str, "%%%.%d") or strfind(str, "%%[dfqsx%d]") then
			str = format(str, ...)
		else
			str = strjoin(" ", str, tostringall(...))
		end
	end
	DEFAULT_CHAT_FRAME:AddMessage(format("|cff33ff99%s:|r %s", self.name, str))
end

-- standard methods ---------------------------------------------------------

function SmartRes2:OnInitialize()
	-- register saved variables with AceDB
	db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, true)
	db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	db.RegisterCallback(self, "OnProfileReset", "OnNewProfile")
	db.RegisterCallback(self, "OnNewProfile", "OnNewProfile")
	self.db = db
	self:FillRandChatDefaults()
	self:SetEnabledState(self.db.profile.enableAddon)

	-- addon options table
	self.options = self:OptionsTable() -- see SmartRes2Options.lua
	-- add the 'Profiles' section
	self.options.args.profilesTab = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	self.options.args.profilesTab.order = 50

	-- Register your options with AceConfigRegistry
	LibStub("AceConfig-3.0"):RegisterOptionsTable("SmartRes2", self.options)

	-- Add your options to the Blizz options window using AceConfigDialog
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SmartRes2", "SmartRes2")

	-- support for LibAboutPanel
	if LibStub:GetLibrary("LibAboutPanel", true) then
		self.optionsFrame[L["About"]] = LibStub("LibAboutPanel").new("SmartRes2", "SmartRes2")
	end

	-- add console commands
	self:RegisterChatCommand("sr", "SlashHandler")
	self:RegisterChatCommand("smartres", "SlashHandler")

	-- get player's spell for button
	local resSpells = { -- getting the spell names
		PRIEST = GetSpellInfo(2006), -- Resurrection
		SHAMAN = GetSpellInfo(2008), -- Ancestral Spirit
		DRUID = GetSpellInfo(50769), -- Revive
		PALADIN = GetSpellInfo(7328), -- Redemption
		MONK = GetSpellInfo(115178) -- Resuscitate
	}
	local _, player_class = UnitClass("player")
	self.playerSpell = resSpells[player_class]

	-- create DataBroker Launcher
	if DataBroker then
		local launcher = DataBroker:NewDataObject("SmartRes2", {
			type = "launcher",
			icon = select(3, GetSpellInfo(self.playerSpell)) or select(3, GetSpellInfo(2006)),
			OnClick = function(clickedframe, button)
				if button == "LeftButton" then
					-- keep our options table in sync with the ldb object state
					self.db.profile.hideAnchor = not self.db.profile.hideAnchor
					if self.db.profile.hideAnchor then
						self.rez_bars:HideAnchor()
						self.rez_bars:Lock()
					else
						self.rez_bars:ShowAnchor()
						self.rez_bars:Unlock()
						self.rez_bars:SetClampedToScreen(true)
					end
					LibStub("AceConfigRegistry-3.0"):NotifyChange("SmartRes2")
				elseif button == "RightButton" then
					InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
				elseif button == "MiddleButton" then
					self:StartTestBars()
				end
			end,
			OnTooltipShow = function(self)
			GameTooltip:AddLine("SmartRes2".." "..version, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			GameTooltip:AddLine(L["Left click to lock/unlock the res bars. Right click for configuration."].."\n"..L["Middle click for Test Bars."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
			GameTooltip:Show()
		end})
		self.launcher = launcher
	end

	-- create a secure button for ressing
	local resButton = CreateFrame("button", "SmartRes2Button", UIParent, "SecureActionButtonTemplate")
	resButton:SetAttribute("type", "spell")
	resButton:SetScript("PreClick", function() self:Resurrection() end)
	self.resButton = resButton

	-- create seperate button for Mass Resurrection
	local massResButton = CreateFrame("button", "SR2MassResButton", UIPARENT, "SecureActionButtonTemplate")
	massResButton:SetAttribute("type", "spell")
	massResButton:SetScript("PreClick", function() self:MassResurrection() end)
	self.massResButton = massResButton
end

function SmartRes2:OnEnable()
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("GROUP_ROSTER_UPDATE")
	self:RegisterEvent("GUILD_PERK_UPDATE", "VerifyPerk")
	self:RegisterEvent("PLAYER_GUILD_UPDATE", "VerifyPerk")

	self.rez_bars = self.rez_bars or self:NewBarGroup("SmartRes2", self.db.horizontalOrientation, 300, 15, "SmartRes2_ResBars")
	self.rez_bars:SetClampedToScreen(true)
	if self.db.profile.hideAnchor then
		self.rez_bars:HideAnchor()
		self.rez_bars:Lock()
	else
		self.rez_bars:ShowAnchor()
		self.rez_bars:Unlock()
	end
	self.rez_bars:SetMaxBars(self.db.profile.maxBars)
	self:RestorePosition()

	Media.RegisterCallback(self, "OnValueChanged", "UpdateMedia")
	ResInfo.RegisterCallback(self, "LibResInfo_ResCastStarted")
	ResInfo.RegisterCallback(self, "LibResInfo_ResExpired")
	ResInfo.RegisterCallback(self, "LibResInfo_ResCastFinished", "DeleteBar")
	ResInfo.RegisterCallback(self, "LibResInfo_ResCastCancelled", "DeleteBar")
	self.rez_bars.RegisterCallback(self, "FadeFinished")
	self.rez_bars.RegisterCallback(self, "AnchorMoved", "SavePosition")

	self:BindMassRes()
	self:BindKeys()
end

function SmartRes2:SavePosition()
	local f = self.rez_bars
	local s = f:GetEffectiveScale()
	self.db.profile.resBarsX = f:GetLeft() * s
	self.db.profile.resBarsY = f:GetTop() * s
end

function SmartRes2:RestorePosition()
	local x = self.db.profile.resBarsX
	local y = self.db.profile.resBarsY
	if not x or not y then return end

	local f = self.rez_bars
	local s = f:GetEffectiveScale()
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
end

-- process slash commands ---------------------------------------------------
function SmartRes2:SlashHandler(input)
	input = input:lower()
	if input == "test" then
		self:StartTestBars()
	elseif input == "cast" then
		self:Resurrection()
	else
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	end
end

-- disable SmartRes2 completely ----------------------------------------------
function SmartRes2:OnDisable()
	self:UnBindKeys()
	self:UnregisterAllEvents()
	Media.UnregisterAllCallbacks(self)
	ResInfo.UnregisterAllCallbacks(self)
	self.rez_bars.UnregisterAllCallbacks(self)
	wipe(resBars)
	LastRes = nil
end

-- General callback functions -----------------------------------------------

function SmartRes2:FillRandChatDefaults()
	if self.db.profile.randChatTbl then return end

	self.db.profile.randChatTbl = {}
	local randomMessages = {
		[1] = L["%%p%% is bringing %%t%% back to life!"],
		[2] = L["Filthy peon! %%p%% has to resurrect %%t%%!"],
		[3] = L["%%p%% has to wake %%t%% from eternal slumber."],
		[4] = L["%%p%% is ending %%t%%'s dirt nap."],
		[5] = L["No fallen heroes! %%p%% needs %%t%% to march forward to victory!"],
		[6] = L["%%p%% doesn't think %%t%% is immortal, but after this res cast, it is close enough."],
		[7] = L["Sleeping on the job? %%p%% is disappointed in %%t%%."],
		[8] = L["%%p%% knew %%t%% couldn't stay out of the fire. *Sigh*"],
		[9] = L["Once again, %%p%% pulls %%t%% and their bacon out of the fire."],
		[10] = L["%%p%% thinks %%t%% should work on their Dodge skill."],
		[11] = L["%%p%% refuses to accept blame for %%t%%'s death, but kindly undoes the damage."],
		[12] = L["%%p%% grabs a stick. A-ha! %%t%% was only temporarily dead."],
		[13] = L["%%p%% is ressing %%t%%"],
		[14] = L["%%p%% knows %%t%% is faking. It was only a flesh wound!"],
		[15] = L["Oh. My. God. %%p%% has to breathe life back into %%t%% AGAIN?!?"],
		[16] = L["%%p%% knows that %%t%% dying was just an excuse to see another silly random res message."],
		[17] = L["Think that was bad? %%p%% proudly shows %%t%% the scar tissue caused by Hogger."],
		[18] = L["Just to be silly, %%p%% tickles %%t%% until they get back up."],
		[19] = L["FOR THE HORDE! FOR THE ALLIANCE! %%p%% thinks %%t%% should be more concerned about yelling FOR THE LICH KING! and prevents that from happening."],
		[20] = L["And you thought the Scourge looked bad. In about 10 seconds, %%p%% knows %%t%% will want a comb, some soap, and a mirror."],
		[21] = L["Somewhere, the Lich King is laughing at %%p%%, because he knows %%t%% will just die again eventually. More meat for the grinder!!"],
		[22] = L["%%p%% doesn't want the Lich King to get another soldier, so is bringing %%t%% back to life."],
		[23] = L["%%p%% wonders about these stupid res messages. %%t%% should just be happy to be alive."],
		[24] = L["%%p%% prays over the corpse of %%t%%, and a miracle happens!"],
		[25] = L["In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %%p%% is making sure %%t%%'s death isn't permanent."],
		[26] = L["%%p%% performs a series of lewd acts on %%t%%'s still warm corpse. Ew."]
	}
	for idx, message in ipairs(randomMessages) do
		tinsert(self.db.profile.randChatTbl, message)
	end
end

-- called when new profile is created
function SmartRes2:OnNewProfile()
	self:FillRandChatDefaults()
end

-- called when user changes profile
function SmartRes2:OnProfileChanged()
	db = self.db
	self:FillRandChatDefaults()
end

-- called when user changes the texture of the bars
function SmartRes2:UpdateMedia(callback, type, handle)
	local flags = self.db.profile.fontFlags:upper()
	if type == "statusbar" then
		self.rez_bars:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
	elseif type == "border" then
		self.rez_bars:SetBackdrop({
			edgeFile = Media:Fetch("border", self.db.profile.resBarsBorder),
			tile = false,
			tileSize = self.db.profile.scale + 1,
			edgeSize = self.db.profile.borderThickness,
			insets = { left = 0, right = 0, top = 0, bottom = 0 }
		})
	elseif type == "font" then
		self.rez_bars:SetFont(Media:Fetch("font", self.db.profile.fontType), self.db.profile.fontScale, flags)
	end
end

local function ChatType()
	local chatType
	if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		chatType = "INSTANCE_CHAT"
	elseif IsInRaid() then
		chatType = "RAID"
	elseif IsInGroup() then
		chatType = "PARTY"
	end
	return chatType
end

-- ResInfo library callback functions ---------------------------------------
-- Fires when a group member starts casting a resurrection spell on another group member.
function SmartRes2:LibResInfo_ResCastStarted(callback, targetID, targetGUID, casterID, casterGUID, endTime)
	self:Debug(callback, targetID, casterID)

	local _, hasTarget, _, isFirst = ResInfo:UnitIsCastingRes(casterID)
	local targetName, targetRealm = UnitName(targetID)
	local casterName = UnitName(casterID)
	local hasIncomingRes = ResInfo:UnitHasIncomingRes(targetID)

	if self.db.profile.visibleResBars then
		self:CreateResBar(casterID, endTime, targetID, isFirst, hasIncomingRes, not hasTarget)
	end

	-- notify collider caster
	if (self.db.profile.notifyCollision ~= "0-off") and (not isFirst) then
		channel = self.db.profile.notifyCollision:upper()
		if channel == "GROUP" or "RAID" or "PARTY" or "INSTANCE" then
			chat_type = ChatType()
		else
			chat_type = channel
		end

		if hasTarget then
			-- handle class spells
			msg = format(L["SmartRes2 would like you to know that %s is already being ressed by %s."], targetName, casterName)
		else
			-- handle Mass Resurrection
			msg = format(L["SmartRes2 would like you to know that %s is already resurrecting everybody."], casterName)
		end
		SendChatMessage(msg, chat_type, nil, (chat_type == "WHISPER") and casterName or nil)
	end

	self:Debug("casterID", casterID, "UnitIsUnit", UnitIsUnit(casterID, "player"))
	if not UnitIsUnit(casterID, "player") then
		return
	end

	-- self print whom you are resurrecting
	if targetRealm == "Llane" and creatorName[targetName] then
		self:Print("You are resurrecting the Creator!!")

	elseif self.db.profile.notifySelf then
		self:Print(L["You are ressing %s"], targetName)
	end

	-- send normal, random, or custom chat message
	local channel = self.db.profile.chatOutput:upper()
	local chat_type
	local msg
	if channel ~= "0-NONE" then -- if it is "none" then don't send any chat messages
		if channel == "GROUP" or "RAID" or "PARTY" or "INSTANCE" then
			chat_type = ChatType()
		else
			chat_type = channel
		end
		msg = L["%%p%% is ressing %%t%%"]

		if self.db.profile.randMsgs and targetID then
			msg = self.db.profile.randChatTbl[math.random(#self.db.profile.randChatTbl)]
			msg = gsub(msg, "%%%%p%%%%", casterName)
			msg = gsub(msg, "%%%%t%%%%", targetName)
		elseif (self.db.profile.massResMessage ~= "") and (not targetID) then
			msg = self.db.profile.massResMessage
		end

		SendChatMessage(msg, chat_type, nil, (chat_type == "WHISPER") and targetName or nil)
	end
end

function SmartRes2:LibResInfo_ResExpired(callback, targetID, targetGUID)
	if not self.db.profile.resExpired then return end
	self:Print(L["%s's resurrection timer expired, and can be resurrected again"], UnitName(targetID) or targetID)
end

-- a res cast has finished or cancelled
function SmartRes2:DeleteBar(callback, targetID, targetGUID, casterID, casterGUID, endTime)
	self:Debug("DeleteBar", callback, targetID, casterID)
	resBars[casterID]:Fade(0.1)
	resBars[casterID] = nil
end

-- Blizzard callback functions ----------------------------------------------
function SmartRes2:VerifyPerk(unit)
	if unit ~= "player" then return end
	self:BindMassRes()
end

-- Important Note: Since the release of patch 3.2, certain fights in the game fire the
-- "PLAYER_REGEN_DISABLED" event continuously during combat causing any subsequent events
-- we might trigger as a result to also fire continuously. It is recommended therefore to
-- use a checking variable that is set to 'on/1/etc' when entering combat and back to
-- 'off/0/etc' only when exiting combat and then use this as the final determinant on
-- whether or not to action a subsequent event.
function SmartRes2:PLAYER_REGEN_DISABLED()
	-- don't confuse the variable below with being in combat - we use it to see if we've run
	-- the code below on entry into combat already so that we only run it once
	if not in_combat then
		self:UnBindKeys()
		-- disable callbacks during battle if we don't want to see battle resses
		if not self.db.profile.showBattleRes then
			ResInfo.UnregisterAllCallbacks(self)
			self.rez_bars.UnregisterAllCallbacks(self)
		end
		-- clear the ressing tables
		LastRes = nil
	end
	in_combat = true
end

function SmartRes2:PLAYER_REGEN_ENABLED()
	self:BindKeys()
	self:BindMassRes()
	-- reenable callbacks during battle if we don't want to see battle resses
	if not self.db.profile.showBattleRes then
		ResInfo.RegisterCallback(self, "LibResInfo_ResCastStarted")
		ResInfo.RegisterCallback(self, "LibResInfo_ResExpired")
		ResInfo.RegisterCallback(self, "LibResInfo_ResCastFinished", "DeleteBar")
		ResInfo.RegisterCallback(self, "LibResInfo_ResCastCancelled", "DeleteBar")
		self.rez_bars.RegisterCallback(self, "FadeFinished")
		self.rez_bars.RegisterCallback(self, "AnchorMoved", "ResAnchorMoved")
	end
	in_combat = false
end

-- key binding functions ----------------------------------------------------
function SmartRes2:BindMassRes()
	if IsSpellKnown(83968) then
		self.knowsMassRes = true
	else
		self.knowsMassRes = nil
	end

	if self.db.profile.massResKey ~= "" and self.knowsMassRes then
		SetOverrideBindingClick(self.massResButton, false, self.db.profile.massResKey, "SR2MassResButton")
	elseif self.db.profile.massResKey == "" or not self.knowsMassRes then
		SetOverrideBinding(self.massResButton, false, self.db.profile.massResKey, nil)
	end
end

function SmartRes2:BindKeys()
	-- only binds keys if the player can cast an out of combat res spell
	if not self.playerSpell then return end

	if self.db.profile.autoResKey ~= "" then
		SetOverrideBindingClick(self.resButton, false, self.db.profile.autoResKey, "SmartRes2Button")
	else
		SetOverrideBinding(self.resButton, false, self.db.profile.autoResKey, nil)
	end

	if self.db.profile.manualResKey ~= "" then
		SetOverrideBindingSpell(self.resButton, false, self.db.profile.manualResKey, self.playerSpell)
	else
		SetOverrideBinding(self.resButton, false, self.db.profile.manualResKey, nil)
	end
end

function SmartRes2:UnBindKeys()
	ClearOverrideBindings(self.resButton)
	ClearOverrideBindings(self.massResButton)
end

-- smart resurrection determination functions -------------------------------
local raidUpdated
function SmartRes2:GROUP_ROSTER_UPDATE()
	raidUpdated = true
end

function SmartRes2:MassResurrection(caster)
	local massResButton = self.massResButton

	if not IsUsableSpell(83968) and UnitIsUnit(caster, "player") then
		self:Print(L["You cannot cast Mass Resurrection right now."])
		return
	end

	if not IsInGroup() then
		self:Print(L["You are not in a group."])
		return
	else
		massResButton:SetAttribute("spell", GetSpellInfo(83968))
	end
end

local unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK
local SortedResList = {}
local CLASS_PRIORITIES = {
	-- MoP changed all resurrection spells to 35% health and mana
	-- get all ressers up first, then mana burners and pet summoners
	-- get fighers up next, other dps last
	PRIEST = 1,
	PALADIN = 1,
	SHAMAN = 1,
	DRUID = 1,
	MONK = 1,
	MAGE = 2,
	WARLOCK = 2,
	DEATHKNIGHT = 3,
	WARRIOR = 3,
	HUNTER = 4,
	ROGUE = 4
}

-- create resurrection tables
local function getClassOrder(unit)
	local _, c = UnitClass(unit)
	local lvl = UnitLevel(unit)
	return CLASS_PRIORITIES[c] or 9, lvl
end

local function verifyUnit(unit)
	-- unit is the next candidate. there is NO way to check LoS, so don't ask!
	if UnitIsAFK(unit) then
		unitAFK = true
		return
	end
	if UnitIsGhost(unit) then
		unitGhost = true
		unitDead = true
		return
	end
	if not UnitIsDead(unit) then
		return
	end
	unitDead = true
	if unit == LastRes then
		return
	end
	local state = ResInfo:UnitHasIncomingRes(unit)
	if state == "CASTING" then
		unitBeingRessed = true
		return
	end
	if state == "PENDING" then
		unitWaiting = true
		return
	end
	if IsSpellInRange(SmartRes2.playerSpell, unit) ~= 1 then
		unitOutOfRange = true
		return
	end
	return true
end

--sort function only called when group has actually changed
local function SortCurrentRaiders()
	local num = GetNumGroupMembers()
	local unit, resPrio, lvl
	wipe(SortedResList)
	if IsInRaid() then
		for i = 1, num do
			unit = "raid"..i
			if not UnitIsUnit(unit, "player") then
				resPrio, lvl = getClassOrder(unit)
				tinsert(SortedResList, {unit = unit, resPrio = resPrio, level = lvl})
			end
		end
	elseif IsInGroup() then
		for i = 1, num-1 do
			unit = "party"..i
			resPrio, lvl = getClassOrder(unit)
			tinsert(SortedResList, {unit = unit, resPrio = resPrio, level = lvl})
		end
	end
	sort(SortedResList, function(a,b)
		if a.resPrio == b.resPrio then
			return a.level > b.level
		else
			return a.resPrio < b.resPrio
		end
	end)
	raidUpdated = nil
end

local function getBestCandidate()
	unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK = nil, nil, nil, nil, nil, nil
	if raidUpdated then
		SortCurrentRaiders() -- only resort if group changed
	end
	for _, data in ipairs(SortedResList) do
		local unit = data.unit
		local validUnit = verifyUnit(unit)
		if validUnit then
			return unit
		end
	end
	return
end

function SmartRes2:Resurrection()
	self:Debug("Resurrection")
	local resButton = self.resButton

	if not IsInGroup() then
		self:Debug(L["You are not in a group."])
		return
	end

	-- check if the player has enough Mana to cast a res spell. if not, no point in continuing. same if player is not a caster
	local _, outOfMana = IsUsableSpell(self.playerSpell)
	if outOfMana == 1 then
	   self:Print(ERR_OUT_OF_MANA)
	   return
	end

	local unit = getBestCandidate()
	if unit then
		-- resButton:SetAttribute("unit", nil)
		self:Debug("spell:", self.playerSpell)
		self:Debug("unit:", unit)
		resButton:SetAttribute("spell", self.playerSpell)
		resButton:SetAttribute("unit", unit)
		LastRes = unit
	elseif unitOutOfRange then
		self:Print(SPELL_FAILED_CUSTOM_ERROR_64_NONE)
	elseif unitBeingRessed or unitWaiting then
		self:Print(L["All dead units are being ressed."])
	elseif not unitDead then
		self:Print(L["Everybody is alive. Congratulations!"])
	elseif unitGhost then
		self:Print(L["All dead units have released."])
	elseif unitAFK then
		self:Print(L["Remaining units are away from keyboard."])
	end
end

-- resbar functions ---------------------------------------------------------
local function ClassColouredName(name)
	if not name then return "|cffcccccc".. UNKNOWN.. "|r" end
	local _, class = UnitClass(name)
	if not class then return "|cffcccccc"..name.."|r" end
	local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
	return format("|cff%02X%02X%02X%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

function SmartRes2:CreateResBar(casterID, endTime, targetID, isFirst, hasIncomingRes, isMassRes, spellID)
	local spellName, _, icon
	local casterName
	local targetName
	local end_time = endTime - GetTime()
	local text
	local t -- bar colours

	if spellID then -- exists only for test bars
		spellName, _, icon = GetSpellInfo(spellID)
		casterName = casterID
		targetName = targetID or NONE
	else -- LibResInfo_ResCastStarted
		spellName, _, _, icon = UnitCastingInfo(casterID)
		casterName = UnitName(casterID)
		targetName = UnitName(targetID) or NONE
	end

	if self.db.profile.classColours then
		if isMassRes then
			text = format("%s: %s", ClassColouredName(casterName), spellName)
		else
			text = format(L["%s is ressing %s"], ClassColouredName(casterName), ClassColouredName(targetName))
		end
	else
		if isMassRes then
			text = format("%s: %s", casterName, spellName)
		else
			text = format(L["%s is ressing %s"], casterName, targetName)
		end
	end

	if isFirst then -- check for first cast
		t = isMassRes and self.db.profile.massResBarColour or self.db.profile.resBarsColour
	else -- collision, could be class spell or Mass Res
		t = self.db.profile.collisionBarsColour
	end

	if hasIncomingRes == "PENDING" then
		t = self.db.profile.waitingBarsColour
	end

	local flags = self.db.profile.fontFlags:upper()

	-- args are as follows: lib:NewTimerBar(name, text, time, maxTime, icon, flashTrigger)
	local bar = self.rez_bars:NewTimerBar(casterName, text, end_time, nil, icon, 0)
	bar:SetBackgroundColor(t.r, t.g, t.b, t.a)
	bar:SetColorAt(0, 0, 0, 0, 1) -- set bars to be black behind the cast bars

	orientation = (self.db.profile.horizontalOrientation == "RIGHT") and Bars.RIGHT_TO_LEFT or Bars.LEFT_TO_RIGHT
	bar:SetOrientation(orientation)

	if self.db.profile.resBarsIcon then
		bar:ShowIcon()
	else
		bar:HideIcon()
	end

	bar:SetHeight(self.db.profile.barHeight)
	bar:SetWidth(self.db.profile.barWidth)

	bar:SetFont(Media:Fetch("font", self.db.profile.fontType), self.db.profile.fontScale, flags)
	bar:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
	bar:SetBackdrop({
		edgeFile = Media:Fetch("border", self.db.profile.resBarsBorder),
		tile = false,
		tileSize = self.db.profile.scale + 1,
		edgeSize = self.db.profile.borderThickness,
		insets = { left = 0, right = 0, top = 0, bottom = 0 }
	})
	resBars[casterID] = bar
end

-- LibBars event - called when bar finished fading
function SmartRes2:FadeFinished(event, bar, name)
	self.rez_bars:ReleaseBar(bar)
end

function SmartRes2:StartTestBars()
	if not self.db.profile.enableAddon then return end
	if self.db.profile.visibleResBars then
		self:CreateResBar("NawtyNurse", GetTime() + 4, "FrankTheTank", true, nil, nil, 2008)
		self:CreateResBar("BadCaster", GetTime() + 5, "FrankTheTank", nil, nil, nil, 115178)
		self:CreateResBar("MassResser", GetTime() + 6, nil, true, nil, true, 83968)
		self:CreateResBar("MassCollider", GetTime() + 7, nil, nil, nil, true, 83968)
		self:CreateResBar("Sonayahh", GetTime() + 8, "AlreadyRessed", nil, "PENDING", nil, 7328)
	end
	self:LibResInfo_ResExpired(nil, "LazyPlayer")
end

--@debug@
_G.SmartRes2 = SmartRes2
--@end-debug@