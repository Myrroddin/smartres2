--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Myrroddin of Llane

-- localise global variables for faster access ------------------------------
local _G = getfenv(0)
local math = _G.math
local string = _G.string
local table = _G.table
local tinsert = table.insert
local tonumber = _G.tonumber
local tremove = table.remove
local tsort = table.sort
local wipe = table.wipe
local pairs = _G.pairs
local ipairs = _G.ipairs

-- Upvalued Blizzard API ----------------------------------------------------
local GameTooltip = _G.GameTooltip
local GetAddOnMetadata = _G.GetAddOnMetadata
local GetItemIcon = _G.GetItemIcon
local GetNumRaidMembers = _G.GetNumRaidMembers
local GetNumPartyMembers = _G.GetNumPartyMembers
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local HIGHLIGHT_FONT_COLOR = _G.HIGHLIGHT_FONT_COLOR
local IsSpellInRange = _G.IsSpellInRange
local IsUsableSpell = _G.IsUsableSpell
local NORMAL_FONT_COLOR = _G.NORMAL_FONT_COLOR
local select = _G.select
local SendChatMessage = _G.SendChatMessage
local UIParent = _G.UIParent
local UnitCastingInfo = _G.UnitCastingInfo
local UnitClass = _G.UnitClass
local UnitInRaid = _G.UnitInRaid
local UnitInRange = _G.UnitInRange
local UnitIsAFK = _G.UnitIsAFK
local UnitIsDead = _G.UnitIsDead
local UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost
local UnitIsGhost = _G.UnitIsGhost
local UnitIsUnit = _G.UnitIsUnit
local UnitLevel = _G.UnitLevel
local UnitName = _G.UnitName

-- declare addon ------------------------------------------------------------
local LibStub = _G.LibStub

local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0", "LibBars-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)

-- get version from .toc - set to Development if no version
local version = GetAddOnMetadata("SmartRes2", "Version")
--[===[@alpha@
if version:match("@") then
	version = "Development"
else
	version = "Alpha "..version
end
--@end-alpha@]===]

-- add localisation to addon
SmartRes2.L = L
-- declare the database
local db
-- additional libraries -----------------------------------------------------
-- LibDataBroker used for LDB enabled addons like ChocolateBars
local DataBroker = LibStub:GetLibrary("LibDataBroker-1.1")
-- LibBars used for bars
local Bars = LibStub:GetLibrary("LibBars-1.0")
-- LibResComm used for communication
local ResComm, ResCommMinor = LibStub:GetLibrary("LibResComm-1.0")
-- LibSharedMedia used for more textures
local Media = LibStub:GetLibrary("LibSharedMedia-3.0")
-- register the res bar textures with LibSharedMedia-3.0
Media:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])

-- local variables ----------------------------------------------------------
local doingRessing = {}
local waitingForAccept = {}
local resBars = {}
local orientation
local icon
local LastRes

-- variable to use for multiple PLAYER_REGEN_DISABLED calls (see SmartRes2:PLAYER_REGEN_DISABLED below)
local in_combat = false

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
		fontFlags = "0-nothing",
		fontScale = 12,
		fontType = "Friz Quadrata TT",
		guessResses = true,
		hideAnchor = true,
		horizontalOrientation = "RIGHT",
		manualResKey = "",
		massResKey = "",
		maxBars = 10,
		notifyCollision = "0-off",
		notifySelf = true,
		randMsgs = false,
		customchatmsg = "",
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

-- standard methods ---------------------------------------------------------

function SmartRes2:OnInitialize()
	-- register saved variables with AceDB
	db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, "Default")
	db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
	db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	db.RegisterCallback(self, "OnProfileReset", "OnNewProfile")
	db.RegisterCallback(self, "OnNewProfile", "OnNewProfile")
	self.db = db
	self:FillRandChatDefaults()	
	self:SetEnabledState(self.db.profile.enableAddon)
	
	-- prepare spells
	local resSpells = { -- getting the spell names
		PRIEST = GetSpellInfo(2006), -- Resurrection
		SHAMAN = GetSpellInfo(2008), -- Ancestral Spirit
		DRUID = GetSpellInfo(50769), -- Revive
		PALADIN = GetSpellInfo(7328) -- Redemption
	}
	self.resSpellIcons = { -- need the icons too, for the res bars
		PRIEST = select(3, GetSpellInfo(2006)), 	-- Resurrection
		SHAMAN = select(3, GetSpellInfo(2008)), 	-- Ancestral Spirit
		DRUID = select(3, GetSpellInfo(50769)), 	-- Revive
		PALADIN = select(3, GetSpellInfo(7328)) 	-- Redemption
	}  
	self.playerClass = select(2, UnitClass("player"))
	self.playerSpell = resSpells[self.playerClass]
	self.massResSpell = GetSpellInfo(83968)
	self.massResSpellIcon = select(3, GetSpellInfo(83968))

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
	
	-- create DataBroker Launcher
	if DataBroker then
		local launcher = DataBroker:NewDataObject("SmartRes2", {
			type = "launcher",
			icon = self.resSpellIcons[self.playerClass] or self.resSpellIcons.PRIEST,
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
					_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
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
	local resButton = _G.CreateFrame("button", "SmartRes2Button", UIParent, "SecureActionButtonTemplate")
	resButton:SetAttribute("type", "spell")
	resButton:SetScript("PreClick", function() self:Resurrection() end)
	self.resButton = resButton
	
	-- create seperate button for Mass Resurrection
	local massResButton = _G.CreateFrame("button", "SR2MassResButton", UIPARENT, "SecureActionButtonTemplate")
	massResButton:SetAttribute("type", "spell")
	massResButton:SetScript("PreClick", function() self:MassResurrection() end)
	self.massResButton = massResButton

	-- create the Res Bars and set the user preferences
	self.rez_bars = self:NewBarGroup("SmartRes2", self.db.horizontalOrientation, 300, 15, "SmartRes2_ResBars")
	self.rez_bars:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.resBarsX, self.db.profile.resBarsY)
	self.rez_bars:SetUserPlaced(false)
	if self.db.profile.hideAnchor then
		self.rez_bars:HideAnchor()
		self.rez_bars:Lock()
	else
		self.rez_bars:ShowAnchor()
		self.rez_bars:Unlock()
		self.rez_bars:SetClampedToScreen(true)
	end
end

function SmartRes2:OnEnable()
	-- called when SmartRes2 is enabled
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("RAID_ROSTER_UPDATE")
	self:RegisterEvent("PARTY_MEMBERS_CHANGED")	
	Media.RegisterCallback(self, "OnValueChanged", "UpdateMedia")
	ResComm.RegisterCallback(self, "ResComm_ResStart")
	ResComm.RegisterCallback(self, "ResComm_ResEnd")
	ResComm.RegisterCallback(self, "ResComm_Ressed")
	ResComm.RegisterCallback(self, "ResComm_ResExpired")
	self.rez_bars.RegisterCallback(self, "FadeFinished")
	self.rez_bars.RegisterCallback(self, "AnchorMoved", "ResAnchorMoved")
	self:BindKeys()
	if self.db.profile.guessResses then
		self:StartGuessing()
	end
end

-- process slash commands ---------------------------------------------------
-- developer version. let's see if we can find out why the macro command isn't working
--@debug@
function SmartRes2:SlashHandler(input)
	input = input:lower()
	if input == "cast" then
		SmartRes2:Resurrection()
	else
		_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	end
end
--@end-debug@

-- public version
--[===[@non-debug@
-- process slash commands ---------------------------------------------------
function SmartRes2:SlashHandler(input)
	_G.InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
end
--@end-non-debug@]===]

-- disable SmartRes2 completely ----------------------------------------------
function SmartRes2:OnDisable()
	self:UnBindKeys()
	self:UnregisterAllEvents()
	Media.UnregisterAllCallbacks(self)
	ResComm.UnregisterAllCallbacks(self)
	self.rez_bars.UnregisterAllCallbacks(self)
	wipe(doingRessing)
	wipe(waitingForAccept)
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
	if flags == "0-NOTHING" then
		flags = nil
	elseif flags == "thickOut" then
		flags = "THICKOUTLINE"
	end
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

function SmartRes2:AddCustomMsg(msg)
	msg = string.gsub(msg, "me", "%%%%p%%%%")
	msg = string.gsub(msg, "you", "%%%%t%%%%")
	self.db.profile.customchatmsg = msg
end

function SmartRes2:StartGuessing()
	if in_combat and not self.db.profile.showBattleRes then return end
	self:RegisterEvent("UNIT_SPELLCAST_START")
	self:RegisterEvent("UNIT_SPELLCAST_STOP")
	self:RegisterEvent("UNIT_SPELLCAST_FAILED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
end

function SmartRes2:StopGuessing()
	self:UnregisterEvent("UNIT_SPELLCAST_START")
	self:UnregisterEvent("UNIT_SPELLCAST_STOP")
	self:UnregisterEvent("UNIT_SPELLCAST_FAILED")
	self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	self:UnregisterEvent("UNIT_SPELLCAST_INTERRUPTED")
end

-- ResComm library callback functions ---------------------------------------

function SmartRes2:CheckResTarget(target, newsender)
	for sender, info in pairs(doingRessing) do
		if info.target == target and sender ~= newsender then return sender end
	end
	return nil
end

-- ResComm events - called when res is started
function SmartRes2:ResComm_ResStart(event, sender, endTime, target)
	-- check if we have the person in our table yet, and if not, add them
	if doingRessing[sender] then return end
	
	doingRessing[sender] = {
		endTime = endTime,
		target = target
	}
	self:CreateResBar(sender)

	if waitingForAccept[target] then
		self:AddWaitingBars(sender, target)
	end

	local oldsender = self:CheckResTarget(target, sender) 
	if oldsender then	--target already being ressed
		self:AddCollisionBars(sender, target, oldsender)
	end
	
	-- make sure only the player is sending messages
	if not UnitIsUnit(sender, "player")	then return end

	local name, realm = UnitName(target)
	if name == "Myrroddin" or name == "Jelia" or name == "Badash" or name == "Vanhoeffen" and realm == "Llane" then
		self:Print("You are ressing the Creator!!")
	end
	local channel = self.db.profile.chatOutput:upper()

	if channel == "GROUP" then
		if UnitInRaid("player") then
			channel = "RAID"
		elseif GetNumPartyMembers() > 0 then
			channel = "PARTY"
		end
	end

	if channel ~= "0-NONE" then -- if it is "none" then don't send any chat messages
		local msg = L["%%p%% is ressing %%t%%"]

		if self.db.profile.randMsgs then
			msg = self.db.profile.randChatTbl[math.random(#self.db.profile.randChatTbl)]
		elseif self.db.profile.customchatmsg ~= "" then
			msg = self.db.profile.customchatmsg
		end
		msg = string.gsub(msg, "%%%%p%%%%", sender)
		msg = string.gsub(msg, "%%%%t%%%%", target)

		SendChatMessage(msg, channel, nil, (channel == "WHISPER") and target or nil)
	end
	if self.db.profile.notifySelf then
		self:Print((L["You are ressing %s"]):format(target))
	end
end

-- ResComm events - called when res ends or is cancelled
function SmartRes2:ResComm_ResEnd(event, sender, target, complete)
	-- did the cast fail or complete? mystery.
	if not doingRessing[sender] then return end
	
	-- add the target to our waiting list, and save who the last person to res him was
	if complete then
		waitingForAccept[target] = doingRessing[sender].endTime
	end
	doingRessing[sender] = nil
		
	if self.db.profile.visibleResBars then
		self:DeleteResBar(sender)
		local oldsender = self:CheckResTarget(target, sender) 
		if oldsender and not self:CheckResTarget(target, oldsender) then	--collision bar existed and only 1 exists
			self:DeleteCollisionBars(sender, target, oldsender)
		end
	end
end

-- ResComm events - called when cast is complete (res dialog shown)
function SmartRes2:ResComm_Ressed(event, target)
	-- target ressed, add to list
	waitingForAccept[target] = GetTime()
end

-- ResComm events - called when res box disappears or player declines res
function SmartRes2:ResComm_ResExpired(event, target)
	-- target declined, remove from list
	waitingForAccept[target] = nil
end

do
	local otherResSpells = {
		[(GetSpellInfo(2006))] = true, --Resurrection
		[(GetSpellInfo(2008))] = true, --Ancestral Spirit
		[(GetSpellInfo(7328))] = true, --Redemption
		[(GetSpellInfo(50769))] = true, --Revive
		[(GetSpellInfo(20484))] = true, --Rebirth
		[(GetSpellInfo(83968))] = true, -- Mass Resurrection
		[(GetSpellInfo(8342))] = true, --Defibrillate (Goblin Jumper Cables)
		[(GetSpellInfo(22999))] = true, -- Defibrillate (Goblin Jumper Cables XL)
		[(GetSpellInfo(54732))] = true -- Defibillate (Gnomish Army Knife)
	}

	function SmartRes2:UNIT_SPELLCAST_START(_, unit, spellName)
		if not otherResSpells[spellName] or UnitIsUnit(unit, "player") or doingRessing[UnitName(unit)] then return end
		
		local spell, _, _, _, _, endTime = UnitCastingInfo(unit)
		local sender = UnitName(unit)
		if otherResSpells[spellName] ~= self.massResSpell then
			local target = UnitName(unit .. "target")
			if spell and target and UnitIsDeadOrGhost(target) then
				self:ResComm_ResStart(nil, sender, (endTime / 1000), target)
			end
		else
			self:MassResurrection(sender)
		end
	end

	function SmartRes2:UNIT_SPELLCAST_SUCCEEDED(_, unit, spellName)
		if UnitIsUnit(unit, "player") or not doingRessing[UnitName(unit)] then return end
		
		local sender = UnitName(unit)
		self:ResComm_ResEnd(nil, sender, doingRessing[sender].target, true)
	end

	function SmartRes2:UNIT_SPELLCAST_STOP(_, unit)
		if UnitIsUnit(unit, "player") or not doingRessing[UnitName(unit)] then return end
		
		local sender = UnitName(unit)
		self:ResComm_ResEnd(nil, sender, doingRessing[sender].target)
	end
	SmartRes2.UNIT_SPELLCAST_FAILED = SmartRes2.UNIT_SPELLCAST_STOP
	SmartRes2.UNIT_SPELLCAST_INTERRUPTED = SmartRes2.UNIT_SPELLCAST_STOP	
end

-- Blizzard callback functions ----------------------------------------------

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
			ResComm.UnregisterAllCallbacks(self)
			self:StopGuessing()
		end
		-- clear the ressing tables
		wipe(doingRessing)
		wipe(waitingForAccept)
		wipe(resBars)
		LastRes = nil
	end
	in_combat = true
end

function SmartRes2:PLAYER_REGEN_ENABLED()
	self:BindKeys()
	self:BindMassRes()
	-- reenable callbacks during battle if we don't want to see battle resses
	if not self.db.profile.showBattleRes then
		ResComm.RegisterCallback(self, "ResComm_ResStart")
		ResComm.RegisterCallback(self, "ResComm_ResEnd")
		ResComm.RegisterCallback(self, "ResComm_Ressed")
		ResComm.RegisterCallback(self, "ResComm_ResExpired")
		self.rez_bars.RegisterCallback(self, "FadeFinished")
	end
	in_combat = false
	if self.db.profile.guessResses then
		self:StartGuessing()
	end
end

-- key binding functions ----------------------------------------------------
function SmartRes2:BindMassRes()
	-- guild level may be cached, therefore redundant check
	if _G.GetGuildLevel() <= 24 or not _G.GetGuildInfo("player") then return end
	_G.SetOverrideBindingClick(self.massResButton, false, self.db.profile.massResKey, "SR2MassResButton")
end

function SmartRes2:BindKeys()
	-- only binds keys if the player can cast an out of combat res spell
	if not self.playerSpell then return end
	_G.SetOverrideBindingClick(self.resButton, false, self.db.profile.autoResKey, "SmartRes2Button")
	_G.SetOverrideBindingSpell(self.resButton, false, self.db.profile.manualResKey, self.playerSpell)
end

function SmartRes2:UnBindKeys()
	_G.ClearOverrideBindings(self.resButton)
	_G.ClearOverrideBindings(self.massResButton)
end

-- anchor management functions ----------------------------------------------
function SmartRes2:ResAnchorMoved(_, _, x, y)
	self.db.profile.resBarsX, self.db.profile.resBarsY = x, y
end

-- smart resurrection determination functions -------------------------------
local raidUpdated
function SmartRes2:PARTY_MEMBERS_CHANGED()
	raidUpdated = true
end

function SmartRes2:RAID_ROSTER_UPDATE()
	raidUpdated = true
end

function SmartRes2:MassResurrection(sender)
	local massResButton = self.massResButton
	massResButton:SetAttribute("unit", nil)

	if GetNumPartyMembers() == 0 and not UnitInRaid("player") then
		self:Print(L["You are not in a group."])
		return
	else
		massResButton:SetAttribute("spell", self.massResSpell)
	end
	
	if not IsUsableSpell(self.massResSpell) and UnitIsUnit(sender, "player") then
		self:Print(L["You cannot cast Mass Resurrection right now."])
		return
	end
	
	local spellName, _, _, _, _, endTime = UnitCastingInfo(sender)
	if not UnitIsUnit(sender, "player") and spellName ~= self.massResSpell then
		return
	end
	
	local groupSize = GetNumRaidMembers()
	if groupSize == 0 then
		groupSize = GetNumPartyMembers()
	end
	
	for i = 1, groupSize do
		if UnitIsDeadOrGhost(i) then
			if UnitIsUnit(sender, "player") then
				massResButton:SetAttribute("unit", UnitName(i))
			end
			self:ResComm_ResStart(nil, sender, (endTime / 1000), UnitName(i))
		end
	end
end

local unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK
local SortedResList = {}
local CLASS_PRIORITIES = {
	-- There might be 10 classes, but SHAMANs and DRUIDs res at equal efficiency, so no preference
	-- non healers who use Mana should be followed after healers, as they are usually buffers
	-- or pet summoners (ie: Mana burners)
	-- res non Mana users last
	PRIEST = 1,
	PALADIN = 2, 
	SHAMAN = 3, 
	DRUID = 3, 
	MAGE = 4, 
	WARLOCK = 4,
	DEATHKNIGHT = 5,
	WARRIOR = 5,	
	HUNTER = 5,	
	ROGUE = 5
}

-- create resurrection tables
local function getClassOrder(unit)
	local _, c = UnitClass(unit)
	local lvl = UnitLevel(unit)
	return CLASS_PRIORITIES[c] or 9, lvl
end

local function verifyUnit(unit)
	-- unit is the next candidate. there is NO way to check LoS, so don't ask!
	if UnitIsAFK(unit) then unitAFK = true return nil end
	if UnitIsGhost(unit) then
		unitGhost = true
		unitDead = true
		return nil
	end
	if not UnitIsDead(unit) then return nil end
	unitDead = true
	if unit == LastRes then return nil end
	if ResComm:IsUnitBeingRessed(unit) then unitBeingRessed = true return nil end
	if waitingForAccept[unit] then unitWaiting = true return nil end
	if IsSpellInRange(SmartRes2.playerSpell, unit) ~= 1 then unitOutOfRange = true return nil end
	return true
end

--sort function only called when raid has actually changed (avoided looking up unit names/classes everytime we click the res button)
local function SortCurrentRaiders()
	local num = GetNumRaidMembers()
	local member = "raid"
	if num == 0 then
		num = GetNumPartyMembers()
		member = "party"
	end
	wipe(SortedResList)
	for i = 1, num do
		local id = member .. i
		local name = UnitName(id)
		local resprio, lvl = getClassOrder(name)
		tinsert(SortedResList, {name = name, resprio = resprio, level = lvl})
	end
	tsort(SortedResList, function(a,b) 
		if a.resprio == b.resprio then
			return a.level > b.level
		else 
			return a.resprio < b.resprio
		end
	end)
	raidUpdated = nil
end

local function getBestCandidate()
	unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK = nil, nil, nil, nil, nil, nil
	if raidUpdated then SortCurrentRaiders() end	--only resort if raid changed	
	for _, data in ipairs(SortedResList) do
		local unit = data.name
		local validUnit = verifyUnit(unit)
		if validUnit then
			return unit
		end
	end
	return nil
end

function SmartRes2:Resurrection()
	local resButton = self.resButton
	resButton:SetAttribute("unit", nil)

	if GetNumPartyMembers() == 0 and not UnitInRaid("player") then
		self:Print(L["You are not in a group."])
		return
	else
		resButton:SetAttribute("spell", self.playerSpell)
	end

	-- check if the player has enough Mana to cast a res spell. if not, no point in continuing. same if player is not a sender 
	local _, outOfMana = IsUsableSpell(self.playerSpell) 
	if outOfMana == 1 then 
	   self:Print(ERR_OUT_OF_MANA) 
	   return
	end

	local unit = getBestCandidate()
	if unit then
		resButton:SetAttribute("unit", unit)		
		LastRes = unit
	else
		if unitOutOfRange then
			self:Print(SPELL_FAILED_CUSTOM_ERROR_64_NONE)
		elseif unitBeingRessed or unitWaiting then
			self:Print(L["All dead units are being ressed."])
		elseif not unitDead then
			self:Print(L["Everybody is alive. Congratulations!"])
			wipe(waitingForAccept)
			wipe(doingRessing)
		elseif unitGhost then
			self:Print(L["All dead units have released."])
		elseif unitAFK then
			self:Print(L["Remaining units are away from keyboard."])
		end
	end
end

-- resbar functions ---------------------------------------------------------

local function ClassColouredName(name)
	if not name then return "|cffcccccc"..UNKNOWN.."|r" end
	local _, class = UnitClass(name)
	if not class then return "|cffcccccc"..name.."|r" end
	local c = _G.RAID_CLASS_COLORS[class]
	return ("|cff%02X%02X%02X%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
end

function SmartRes2:CreateResBar(sender)
	if not self.db.profile.visibleResBars then return end
	local text
	local _, senderClass = UnitClass(sender)
	local spell = UnitCastingInfo(sender)
	local engineerSpells = { -- Defibrillate has 3 translations, one per item
		GJC = GetSpellInfo(8342), -- Goblin Jumper Cables
		GJCXL = GetSpellInfo(22999), -- Goblin Jumper Cables XL
		GAK = GetSpellInfo(54732) -- Gnomish Army Knife
	}
	if senderClass == "DRUID" and in_combat then
		icon = select(3, GetSpellInfo(20484))
	elseif spell == engineerSpells.GJC then
		icon = GetItemIcon(7148)
	elseif spell == engineerSpells.GJCXL then
		icon = GetItemIcon(18587)
	elseif spell == engineerSpells.GAK then
		icon = GetItemIcon(40772)
	elseif spell == self.massResSpell then
		icon = self.massResSpellIcon
	else
		icon = self.resSpellIcons[senderClass] or self.resSpellIcons.PRIEST
	end
	local info = doingRessing[sender]
	local time = info.endTime - GetTime()
	local flags = self.db.profile.fontFlags:upper()
	if flags == "0-NOTHING" then
		flags = nil
	elseif flags == "thickOut" then
		flags = "THICKOUTLINE"
	end
	
	if self.db.profile.classColours then
		text = (L["%s is ressing %s"]):format(ClassColouredName(sender), ClassColouredName(info.target))
	else
		text = (L["%s is ressing %s"]):format(sender, info.target)
	end

	-- args are as follows: lib:NewTimerBar(name, text, time, maxTime, icon, flashTrigger)
	local bar = self.rez_bars:NewTimerBar(sender, text, time, nil, icon, 0)	
	local t = self.db.profile.resBarsColour
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
	resBars[sender] = bar
end

function SmartRes2:DeleteResBar(sender)
	local info = doingRessing[sender]
	if not info then return end
	resBars[sender]:Fade(0.1)
	resBars[sender] = nil
end

-- LibBars event - called when bar finished fading
function SmartRes2:FadeFinished(event, bar, name)
	self.rez_bars:ReleaseBar(bar)
end

function SmartRes2:AddCollisionBars(sender, target, collisionsender)
	if self.db.profile.visibleResBars then 
		local t = self.db.profile.collisionBarsColour
		resBars[sender]:SetBackgroundColor(t.r, t.g, t.b, t.a)
		if self.db.profile.flashCollision then
			local interval = self.db.profile.flashInterval
			local times = self.db.profile.flashTimes
			resBars[sender]:Flash(interval, times)
		end
	end
	local chatType = self:GetChatType()
	if chatType ~= "0-OFF" and not UnitIsUnit(sender, "player") then
		SendChatMessage((L["SmartRes2 would like you to know that %s is already being ressed by %s."]):format(target, collisionsender), chatType, nil, sender)
	end
end

function SmartRes2:AddWaitingBars(sender, target)
	if self.db.profile.visibleResBars then 
		local t = self.db.profile.waitingBarsColour		
		resBars[sender]:SetBackgroundColor(t.r, t.g, t.b, t.a)
		if self.db.profile.flashCollision then
			local interval = self.db.profile.flashInterval
			local times = self.db.profile.flashTimes
			resBars[sender]:Flash(interval, times)
		end
	end
end

function SmartRes2:DeleteCollisionBars(sender, target, collisionsender)
	local t = self.db.profile.resBarsColour
	resBars[collisionsender]:SetBackgroundColor(t.r, t.g, t.b, t.a)
end

function SmartRes2:GetChatType()
	local chatType = self.db.profile.notifyCollision:upper()
	if chatType == "GROUP" then
		if GetNumRaidMembers() > 0 then
			chatType = "RAID"
		elseif GetNumPartyMembers() > 0 then
			chatType = "PARTY"
		end
	end
	return chatType
end

function SmartRes2:StartTestBars()
	if not self.db.profile.enableAddon then return end
	-- we don't want the test bars to throw an error if notify collision is on
	local settings = self.db.profile.notifyCollision
	if settings ~= "0-off" then
		self.db.profile.notifyCollision = "0-off"
	end

	-- set up the test bars
	waitingForAccept["Someone"] = GetTime() - 6
	self:ResComm_ResStart(nil, "Nursenancy", GetTime() + 4, "Frankthetank")
	self:ResComm_ResStart(nil, "Dummy", GetTime() + 8, "Frankthetank")
	self:ResComm_ResStart(nil, "Gabriel", GetTime() + 6, "Someone")
		
	-- clean up
	doingRessing["Nursenancy"] = nil
	doingRessing["Dummy"] = nil
	doingRessing["Gabriel"] = nil
	waitingForAccept["Someone"] = nil
	
	-- set the collision back to user preferences
	self.db.profile.notifyCollision = settings
end