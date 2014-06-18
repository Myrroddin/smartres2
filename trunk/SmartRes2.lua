--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Myrroddin of Llane
-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- declare addon ------------------------------------------------------------
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0", "LibBars-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)

local version = GetAddOnMetadata("SmartRes2", "Version")
--@alpha@
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
local timeOutBars = {}
local notified = {}
local orientation
local icon
local raidUpdated
local in_combat
local unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK
local SortedResList = {}
local _, currentRealm = UnitFullName("player")
local creatorName = {
	["Myrroddin"] = true,
	["Jelia"] = true,
	["Badash"] = true,
	["Vanhoeffen"] = true,
}

-- addon defaults -----------------------------------------------------------
local defaults = {
	profile = {
		autoResKey = "",
		barHeight = 20,
		barWidth = 300,
		borderThickness = 10,
		chatOutput = "0-NONE",
		classColours = true,
		collisionBarsColour = { r = 1, g = 0, b = 0, a = 1 },
		--@debug@
		debugMode = true,
		--@end-debug@
		enableAddon = true,
		enableTimeOutBars = true,
		fontFlags = "NONE",
		fontScale = 12,
		fontType = "Friz Quadrata TT",
		hideAnchor = false,
		horizontalOrientation = "RIGHT",
		manualResKey = "",
		massResBarColour = { r = 0.9 , g = 0.8, b = 0.5, a = 1 },
		massResKey = "",
		maxBars = 10,
		notifyCollision = "0-OFF",
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
		timeOutBarsAnchor = true,
		timeOutBarsColour = { r = 1, g = 1, b = 1, a = 1 },
		timeOutBarsX = 50,
		timeOutBarsY = 500,
		visibleResBars = true,
		waitingBarsColour = { r = 0, g = 0, b = 1, a = 1 }
	}
}

-- utility methods ---------------------------------------------------------

function SmartRes2:Debug(str, ...)
	--@debug@
	if not self.db.profile.debugMode then return end
	if not str or strlen(str) == 0 then return end
	if select("#", ...) > 0 then
		if strfind(str, "%%[dfqsx%d]") or strfind(str, "%%%.%d") then
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
	if select("#", ...) > 0 then
		if strfind(str, "%%[dfqsx%d]") or strfind(str, "%%%.%d") then
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

	-- @phanx: auto expand the sub-panels
	do
		self.optionsFrame:HookScript("OnShow", function(self)
			if InCombatLockdown() then return end
			local target = self.parent or self.name
			local i = 1
			local button = _G["InterfaceOptionsFrameAddOnsButton"..i]
			while button do
				local element = button.element
				if element.name == target then
					if element.hasChildren and element.collapsed then
						_G["InterfaceOptionsFrameAddOnsButton"..i.."Toggle"]:Click()
					end
					return
				end
				i = i + 1
				button = _G["InterfaceOptionsFrameAddOnsButton"..i]
			end
		end)
		local function OnClose(self)
			if InCombatLockdown() then return end
			local target = self.parent or self.name
			local i = 1
			local button = _G["InterfaceOptionsFrameAddOnsButton"..i]
			while button do
				local element = button.element
				if element.name == target then
					if element.hasChildren and not element.collapsed then
						local selection = InterfaceOptionsFrameAddOns.selection
						if not selection or selection.parent ~= target then
							_G["InterfaceOptionsFrameAddOnsButton"..i.."Toggle"]:Click()
						end
					end
					return
				end
				i = i + 1
				button = _G["InterfaceOptionsFrameAddOnsButton"..i]
			end
		end
		hooksecurefunc(self.optionsFrame, "okay", OnClose)
		hooksecurefunc(self.optionsFrame, "cancel", OnClose)
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
			icon = self.playerSpell and select(3, GetSpellInfo(self.playerSpell)) or select(3, GetSpellInfo(2006)),
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
			end
		})
		self.launcher = launcher
	end

	-- create a secure button for ressing
	local resButton = CreateFrame("button", "SmartRes2Button", UIParent, "SecureActionButtonTemplate")
	resButton:SetAttribute("type", "spell")
	resButton:SetScript("PreClick", function() self:Resurrection() end)
	self.resButton = resButton

	-- create separate button for Mass Resurrection
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

	self.rez_bars = self.rez_bars or self:NewBarGroup("SmartRes2", self.db.profile.horizontalOrientation, 300, 15, "SmartRes2_ResBars")
	self.rez_bars:SetClampedToScreen(true)
	if self.db.profile.hideAnchor then
		self.rez_bars:HideAnchor()
		self.rez_bars:Lock()
	else
		self.rez_bars:ShowAnchor()
		self.rez_bars:Unlock()
	end
	self.rez_bars:SetMaxBars(self.db.profile.maxBars)
	self.rez_bars:SetHeight(self.db.profile.barHeight)
	self.rez_bars:SetWidth(self.db.profile.barWidth)
	self.rez_bars:SetScale(self.db.profile.scale)

	self.timeOut_bars = self.timeOut_bars or self:NewBarGroup("SmartRes2_TimeOutBars", self.db.profile.horizontalOrientation, 300, 15, "SmartRes2_TimeOutBars")
	self.timeOut_bars:SetClampedToScreen(true)
	if self.db.profile.timeOutBarsAnchor then
		self.timeOut_bars:ShowAnchor()
		self.timeOut_bars:Unlock()
	else
		self.timeOut_bars:HideAnchor()
		self.timeOut_bars:Lock()
	end
	self.timeOut_bars:SetMaxBars(self.db.profile.maxBars)
	self.timeOut_bars:SetHeight(self.db.profile.barHeight)
	self.timeOut_bars:SetWidth(self.db.profile.barWidth)
	self.timeOut_bars:SetScale(self.db.profile.scale)
	self:RestorePosition()

	Media.RegisterCallback(self, "OnValueChanged", "UpdateMedia")

	ResInfo.RegisterCallback(self, "LibResInfo_ResCastStarted")
	ResInfo.RegisterCallback(self, "LibResInfo_ResCastFinished", "DeleteBar")
	ResInfo.RegisterCallback(self, "LibResInfo_ResCastCancelled", "DeleteBar")

	ResInfo.RegisterCallback(self, "LibResInfo_MassResStarted", "LibResInfo_ResCastStarted")
	ResInfo.RegisterCallback(self, "LibResInfo_MassResFinished", "DeleteBar")
	ResInfo.RegisterCallback(self, "LibResInfo_MassResCancelled", "DeleteBar")

	ResInfo.RegisterCallback(self, "LibResInfo_ResPending", "ResTimeOutStarted")
	ResInfo.RegisterCallback(self, "LibResInfo_ResUsed", "ResTimeOutEnded")
	ResInfo.RegisterCallback(self, "LibResInfo_ResExpired", "ResTimeOutEnded")

	self.rez_bars.RegisterCallback(self, "AnchorMoved", "SavePosition")

	self.timeOut_bars.RegisterCallback(self, "AnchorMoved", "SavePosition")

	self:BindMassRes()
	self:BindKeys()
end

function SmartRes2:SavePosition()
	local f = self.rez_bars
	local t = self.timeOut_bars
	local s = f:GetEffectiveScale()
	local ts = t:GetEffectiveScale()
	self.db.profile.resBarsX = f:GetLeft() * s
	self.db.profile.resBarsY = f:GetTop() * s
	self.db.profile.timeOutBarsX = t:GetLeft() * ts
	self.db.profile.timeOutBarsY = t:GetTop() * ts
end

function SmartRes2:RestorePosition()
	local x = self.db.profile.resBarsX
	local y = self.db.profile.resBarsY
	local tx = self.db.profile.timeOutBarsX
	local ty = self.db.profile.timeOutBarsY
	if not x or not y or not tx or not ty then return end

	local f = self.rez_bars
	local t = self.timeOut_bars
	local s = f:GetEffectiveScale()
	local ts = t:GetEffectiveScale()
	f:ClearAllPoints()
	t:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
	t:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tx / ts, ty / ts)
end

-- process slash commands ---------------------------------------------------
function SmartRes2:SlashHandler(input)
	input = input:lower()
	if input == "test" then
		self:StartTestBars()
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
	self.timeOut_bars.UnregisterAllCallbacks(self)
	wipe(resBars)
	wipe(timeOutBars)
	wipe(notified)
	wipe(SortedResList)
	unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK = nil, nil, nil, nil, nil, nil
	raidUpdated = nil
	in_combat = nil
end

-- General callback functions -----------------------------------------------

function SmartRes2:FillRandChatDefaults()
	-- Fix old lower case/camel case values
	self.db.profile.chatOutput = strupper(self.db.profile.chatOutput)
	self.db.profile.fontFlags = strupper(self.db.profile.fontFlags)
	self.db.profile.notifyCollision = strupper(self.db.profile.notifyCollision)

	local t = self.db.profile.randChatTbl
	if t then
		-- Fix old style formatting tokens
		for i = 1, #t do
			local msg = t[i]
			msg = gsub(msg, "%%%%p%%%%", "%%p")
			msg = gsub(msg, "%%%%t%%%%", "%%t")
			t[i] = msg
		end
		return
	end
	self.db.profile.randChatTbl = {
		L["%p is bringing %t back to life!"],
		L["Filthy peon! %p has to resurrect %t!"],
		L["%p has to wake %t from eternal slumber."],
		L["%p is ending %t's dirt nap."],
		L["No fallen heroes! %p needs %t to march forward to victory!"],
		L["%p doesn't think %t is immortal, but after this res cast, it is close enough."],
		L["Sleeping on the job? %p is disappointed in %t."],
		L["%p knew %t couldn't stay out of the fire. *Sigh*"],
		L["Once again, %p pulls %t and their bacon out of the fire."],
		L["%p thinks %t should work on their Dodge skill."],
		L["%p refuses to accept blame for %t's death, but kindly undoes the damage."],
		L["%p grabs a stick. A-ha! %t was only temporarily dead."],
		L["%p is ressing %t"],
		L["%p knows %t is faking. It was only a flesh wound!"],
		L["Oh. My. God. %p has to breathe life back into %t AGAIN?!?"],
		L["%p knows that %t dying was just an excuse to see another silly random res message."],
		L["Think that was bad? %p proudly shows %t the scar tissue caused by Hogger."],
		L["Just to be silly, %p tickles %t until they get back up."],
		L["FOR THE HORDE! FOR THE ALLIANCE! %p thinks %t should be more concerned about yelling FOR THE LICH KING! and prevents that from happening."],
		L["And you thought the Scourge looked bad. In about 10 seconds, %p knows %t will want a comb, some soap, and a mirror."],
		L["Somewhere, the Lich King is laughing at %p, because he knows %t will just die again eventually. More meat for the grinder!!"],
		L["%p doesn't want the Lich King to get another soldier, so is bringing %t back to life."],
		L["%p wonders about these stupid res messages. %t should just be happy to be alive."],
		L["%p prays over the corpse of %t, and a miracle happens!"],
		L["In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %p is making sure %t's death isn't permanent."],
		L["%p performs a series of lewd acts on %t's still warm corpse. Ew."],
	}
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
	if type == "statusbar" then
		self.rez_bars:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
		self.timeOut_bars:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
	elseif type == "border" then
		self.rez_bars:SetBackdrop({
			edgeFile = Media:Fetch("border", self.db.profile.resBarsBorder),
			tile = false,
			tileSize = self.db.profile.scale + 1,
			edgeSize = self.db.profile.borderThickness,
			insets = { left = 0, right = 0, top = 0, bottom = 0 }
		})
		self.timeOut_bars:SetBackdrop({
			edgeFile = Media:Fetch("border", self.db.profile.resBarsBorder),
			tile = false,
			tileSize = self.db.profile.scale + 1,
			edgeSize = self.db.profile.borderThickness,
			insets = { left = 0, right = 0, top = 0, bottom = 0 }
		})
	elseif type == "font" then
		self.rez_bars:SetFont(Media:Fetch("font", self.db.profile.fontType), self.db.profile.fontScale, self.db.profile.fontFlags)
		self.timeOut_bars:SetFont(Media:Fetch("font", self.db.profile.fontType), self.db.profile.fontScale, self.db.profile.fontFlags)
	end
end

local return_chat = {
	["GUILD"] = true,
	["SAY"] = true,
	["YELL"] = true,
	["WHISPER"] = true,
	["0-NONE"] = true,
	["0-OFF"] = true
}
local function ChatType(chatType)
	chatType = strupper(chatType)
	if return_chat[chatType] then
		return chatType
	elseif IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
		chatType = "INSTANCE_CHAT"
	elseif IsInRaid() then
		if chatType ~= "PARTY" then
			chatType = "RAID"
		end
	elseif IsInGroup() then
		chatType = "PARTY"
	end
	return chatType
end

-- ResInfo library callback functions ---------------------------------------
-- Fires when a group member starts casting a resurrection spell on another group member.
-- Or Mass Resurrection, since I have mapped it to this function.
function SmartRes2:LibResInfo_ResCastStarted(callback, targetID, targetGUID, casterID, casterGUID, endTime)
	local targetName, targetRealm
	-- map Mass Res callback
	local isMassRes = callback == "LibResInfo_MassResStarted"
	if isMassRes then
		targetID, targetGUID, casterID, casterGUID, endTime = nil, nil, targetID, targetGUID, casterID, casterGUID, endTime
	else
		targetName, targetRealm = UnitName(targetID)
	end
	self:Debug(callback, targetID, UnitName(targetID or ""), casterID, UnitName(casterID), "isMassRes", isMassRes)

	local _, hasTarget, _, isFirst = ResInfo:UnitIsCastingRes(casterID)
	local casterName, casterRealm = UnitName(casterID)
	local hasIncomingRes, _, origResser = ResInfo:UnitHasIncomingRes(targetID)
	if origResser then origResser = UnitName(origResser) end

	-- self:Debug("single?", not not hasTarget, "first?", isFirst)

	if self.db.profile.visibleResBars then
		self:CreateResBar(casterID, endTime, targetID, isFirst, hasIncomingRes, not hasTarget)
	end

	-- self:Debug("casterID", casterID, "UnitIsUnit", UnitIsUnit(casterID, "player"))
	if UnitIsUnit(casterID, "player") then
		-- self print whom you are resurrecting
		-- but only if hasTarget is true
		if hasTarget then
			-- self:Debug(targetRealm, targetName, creatorName[targetName])
			if targetRealm == "Llane" and creatorName[targetName] then
				self:Print(L["You are resurrecting the Creator!!"])
			elseif self.db.profile.notifySelf then
				--self:Debug("Notifying self")
				self:Print(L["You are ressing %s"], targetName)
			end
		end

		-- send normal, random, or custom chat message
		local chat_type = ChatType(self.db.profile.chatOutput)
		-- self:Debug("chatOutput", self.db.profile.chatOutput, "=>", chat_type)
		if chat_type ~= "0-NONE" then -- if it is "none" then don't send any chat messages
			if hasTarget then
				local msg
				if self.db.profile.customchatmsg then
					msg = self.db.profile.customchatmsg
					-- self:Debug("custom", msg)
				elseif self.db.profile.randMsgs then
					msg = self.db.profile.randChatTbl[random(#self.db.profile.randChatTbl)]
					-- self:Debug("random", msg)
				else
					msg = L["%p is ressing %t"]
					-- self:Debug("default", msg)
				end

	 			msg = gsub(msg, "%%p", casterName)
	 			msg = gsub(msg, "%%t", targetName)

	 			if chat_type == "WHISPER" then
					local whisperTarget = format("%s-%s", targetName, targetRealm or currentRealm)
					self:Debug("Whisper target", whisperTarget)
					SendChatMessage(msg, chat_type, nil, whisperTarget)
				else
					-- self:Debug("Sending res message to chat channel:", chat_type)
	 				SendChatMessage(msg, chat_type)
	 			end
			end
		end

	elseif not isFirst then
		-- notify collision caster
		local chat_type = ChatType(self.db.profile.notifyCollision)
		self:Debug("notifyCollision", self.db.profile.notifyCollision, "=>", chat_type)
		if chat_type ~= "0-OFF" then
			local msg
			if hasTarget then
				-- handle class spells
				if hasIncomingRes == "PENDING" or hasIncomingRes == "SELFRES" then
					msg = format(L["%s already has a res pending; they have not accepted yet"], targetName)
				else
	 				msg = format(L["%s is already being ressed by %s."], targetName, origResser)
				end
			else
				-- handle Mass Resurrection
				if notified[casterID] then return end -- don't spam!
				notified[casterID] = casterID
				msg = format(L["SmartRes2 would like you to know that %s is already resurrecting everybody."], origResser)
			end
			if chat_type == "WHISPER" then
				local whisperTarget = format("%s-%s", casterName, casterRealm or currentRealm)
				SendChatMessage(msg, chat_type, nil, whisperTarget)
			else
				SendChatMessage(msg, chat_type)
			end
		end

	end
end

-- unit has been ressed, not accepted res yet
function SmartRes2:ResTimeOutStarted(callback, targetID, targetGUID)
	--self:Debug("ResTimeOutStarted", callback, targetID, targetGUID)
	if self.db.profile.enableTimeOutBars then
		local status, endTime = ResInfo:UnitHasIncomingRes(targetID)
		if status == "PENDING" or status == "SELFRES" then
			-- self:Debug("Status", status, "endTime", endTime)
			self:CreateTimeOutBars(endTime, targetID)
		end
	end
end

-- unit's res has expired or unit has accepted res
function SmartRes2:ResTimeOutEnded(callback, targetID, targetGUID)
	-- self:Debug("ResTimeOutEnded", callback, targetID, targetGUID)
	if self.db.profile.resExpired and UnitIsDeadOrGhost(targetID) then
		self:Print(L["%s's resurrection timer expired, and can be resurrected again"], UnitName(targetID) or targetID)
	end
	if timeOutBars[targetID] then
		timeOutBars[targetID]:Fade(0.1)
		timeOutBars[targetID] = nil
	end
end

-- a res cast has finished or cancelled
function SmartRes2:DeleteBar(callback, targetID, targetGUID, casterID, casterGUID)
	-- map Mass Res callback
	local isMassRes = callback == "LibResInfo_MassResFinished" or "LibResInfo_MassResCancelled"
	if isMassRes then
		targetID, targetGUID, casterID, casterGUID = nil, nil, casterID, casterGUID
	end
	
	-- self:Debug("DeleteBar", callback, targetID, casterID)
	if resBars[casterID] then
		resBars[casterID]:Fade(0.1)
		resBars[casterID] = nil
	end
	if notified[casterID] then
		notified[casterID] = nil
	end
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
			self.timeOut_bars.UnregisterAllCallbacks(self)
		end
	end
	in_combat = true
	unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK = nil, nil, nil, nil, nil, nil
end

function SmartRes2:PLAYER_REGEN_ENABLED()
	self:BindKeys()
	self:BindMassRes()
	-- re-enable callbacks during battle if we don't want to see battle resses
	if not self.db.profile.showBattleRes then
		ResInfo.RegisterCallback(self, "LibResInfo_ResCastStarted")
		ResInfo.RegisterCallback(self, "LibResInfo_ResCastFinished", "DeleteBar")
		ResInfo.RegisterCallback(self, "LibResInfo_ResCastCancelled", "DeleteBar")
		ResInfo.RegisterCallback(self, "LibResInfo_MassResStarted", "LibResInfo_ResCastStarted")
		ResInfo.RegisterCallback(self, "LibResInfo_MassResFinished", "DeleteBar")
		ResInfo.RegisterCallback(self, "LibResInfo_MassResCancelled", "DeleteBar")
		ResInfo.RegisterCallback(self, "LibResInfo_ResPending", "ResTimeOutStarted")
		ResInfo.RegisterCallback(self, "LibResInfo_ResUsed", "ResTimeOutEnded")
		ResInfo.RegisterCallback(self, "LibResInfo_ResExpired", "ResTimeOutEnded")
		self.rez_bars.RegisterCallback(self, "AnchorMoved", "SavePosition")
		self.timeOut_bars.RegisterCallback(self, "AnchorMoved", "SavePosition")
	end
	in_combat = nil
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
function SmartRes2:GROUP_ROSTER_UPDATE()
	if IsInGroup() then
		raidUpdated = true
	else
		raidUpdated = nil
		for i = 1, #timeOutBars do
			timeOutBars[i]:Fade(0.1)
		end
		wipe(SortedResList)
		unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK = nil, nil, nil, nil, nil, nil
	end
end

local RECENTLY_MASS_RESURRECTED = GetSpellInfo(95223)
function SmartRes2:MassResurrection()
	local button = self.massResButton
	button:SetAttribute("spell", nil)

	if not IsInGroup() then
		return self:Print(L["You are not in a group."])
	end

	if not IsUsableSpell(83968) then
		return self:Print(L["You cannot cast Mass Resurrection right now."])
	end

	local n, u, found = GetNumGroupMembers()
	if IsInRaid() then
		u = "raid"
	else
		u, n = "party", n - 1
	end
	for i = 1, n do
		local unit = u..i
		if UnitIsDeadOrGhost(unit) and UnitIsConnected(unit) and not UnitDebuff(unit, RECENTLY_MASS_RESURRECTED) then
			found = true
			break
		end
	end
	if not found then
		return self:Print(L["There are no valid targets for Mass Resurrection."])
	end

	button:SetAttribute("spell", GetSpellInfo(83968))

	local chat_type = strupper(self.db.profile.chatOutput)
	if chat_type == "0-NONE" then return end
	if chat_type == "WHISPER" then
		chat_type = "GROUP"
	end
	chat_type = ChatType(chat_type)
	self:Debug("MR chat channel:", chat_type)
	local msg
	if self.db.profile.massResMessage then
		msg = self.db.profile.massResMessage
		self:Debug("MR custom", msg)
	else
		msg = L["I am casting Mass Resurrection."]
		self:Debug("MR default", msg)
	end
	SendChatMessage(msg, chat_type)
end

local CLASS_PRIORITIES = {
	-- MoP changed all resurrection spells to 35% health and mana
	-- get all ressers up first, then mana burners and pet summoners
	-- get fighters up next, other dps last
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
local function GetClassOrder(unit)
	local _, c = UnitClass(unit)
	local lvl = UnitLevel(unit)
	return CLASS_PRIORITIES[c] or 9, lvl
end

local function VerifyUnit(unit)
	local self = SmartRes2
	self:Debug("VerifyUnit", unit)
	-- unit is the next candidate. there is NO way to check LoS, so don't ask!
	if not UnitIsDead(unit) then
		-- self:Debug("UnitIsDead")
		return
	end
	unitDead = true
	if UnitIsAFK(unit) then
		-- self:Debug("UnitIsAFK")
		unitAFK = true
		return
	end
	if UnitIsGhost(unit) then
		-- self:Debug("UnitIsGhost")
		unitGhost = true
		return
	end
	if IsSpellInRange(self.playerSpell, unit) ~= 1 then
		-- self:Debug("IsSpellInRange NO!")
		unitOutOfRange = true
		return
	end
	local state = ResInfo:UnitHasIncomingRes(unit)
	self:Debug("LRI state", state)
	if state == "CASTING" then
		-- self:Debug("UnitHasIncomingRes", state)
		unitBeingRessed = true
		return
	end
	if (state == "PENDING" or state == "SELFRES") then
		-- self:Debug("UnitHasIncomingRes", state)
		unitWaiting = true
		return
	end
	--[[ if (state == "PENDING" or state == "SELFRES") and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then -- weird LibResInfo bug that allows recasting during LFR
		self:Debug("UnitHasIncomingRes", state)
		unitWaiting = true
		return
	end ]]--
	-- self:Debug("OK")
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
				resPrio, lvl = GetClassOrder(unit)
				tinsert(SortedResList, {unit = unit, resPrio = resPrio, level = lvl})
			end
		end
	elseif IsInGroup() then
		for i = 1, num-1 do
			unit = "party"..i
			resPrio, lvl = GetClassOrder(unit)
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

local function GetBestCandidate()
	local self = SmartRes2
	self:Debug("GetBestCandidate")
	unitOutOfRange, unitBeingRessed, unitDead, unitWaiting, unitGhost, unitAFK = nil, nil, nil, nil, nil, nil
	if raidUpdated then
		SortCurrentRaiders() -- only resort if group changed
	end
	for _, data in ipairs(SortedResList) do
		local unit = data.unit
		local validUnit = VerifyUnit(unit)
		if validUnit then
			self:Debug(unit, "is the best!")
			return unit
		end
	end
	for _, data in ipairs(SortedResList) do
		local unit = data.unit
		local validUnit = VerifyUnit(unit, true)
		if validUnit then
			self:Debug(unit, "is almost the best!")
			return unit
		end
	end
end

function SmartRes2:Resurrection()
	-- self:Debug("Resurrection")
	local resButton = self.resButton
	resButton:SetAttribute("spell", nil)
	resButton:SetAttribute("unit", nil)

	if not IsInGroup() then
		return self:Print(L["You are not in a group."])
	end

	-- check if the player has enough Mana to cast a res spell. if not, no point in continuing. same if player is not a caster
	local _, outOfMana = IsUsableSpell(self.playerSpell)
	if outOfMana == 1 then
		return self:Print(ERR_OUT_OF_MANA)
	end

	local unit = GetBestCandidate()
	if unit then
		-- self:Debug("spell:", self.playerSpell)
		self:Debug("unit:", unit)
		resButton:SetAttribute("spell", self.playerSpell)
		resButton:SetAttribute("unit", unit)
	elseif not unitDead then
		self:Print(L["Everybody is alive. Congratulations!"])
	elseif unitAFK then
		self:Print(L["Remaining units are away from keyboard."])
	elseif unitGhost then
		self:Print(L["All dead units have released."])
	elseif unitOutOfRange then
		self:Print(SPELL_FAILED_CUSTOM_ERROR_64_NONE)
	elseif unitBeingRessed or unitWaiting then
		self:Print(L["All dead units are being ressed."])
	end
end

-- resbar functions ---------------------------------------------------------
local function ClassColouredName(unit, name)
	if not unit then return "|cffcccccc".. UNKNOWN.. "|r" end
	if not name then UnitName(unit) end
	local _, class = UnitClass(unit)
	if not class then return "|cffcccccc"..name.."|r" end
	local c = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[class]
	return format("|cff%02x%02x%02x%s|r", c.r * 255, c.g * 255, c.b * 255, name)
end

function SmartRes2:CreateTimeOutBars(endTime, targetID)
	local targetName = UnitName(targetID)
	local end_time = endTime - GetTime()
	local text
	local t = self.db.profile.timeOutBarsColour

	if self.db.profile.classColours then
		text = ClassColouredName(targetID, targetName)
	else
		text = targetName
	end

	-- args are as follows: lib:NewTimerBar(name, text, time, maxTime, icon, flashTrigger)
	local bar = self.timeOut_bars:NewTimerBar(targetName, text, end_time, nil, [[Interface\Icons\Spell_Nature_TimeStop]], 0)
	bar.RegisterCallback(self.timeOut_bars, "FadeFinished", SmartRes2.TimeOutBarsFadeFinished)
	bar:SetBackgroundColor(t.r, t.g, t.b, t.a)
	bar:SetColorAt(0, 0, 0, 0, 1)

	orientation = (self.db.profile.horizontalOrientation == "RIGHT") and Bars.RIGHT_TO_LEFT or Bars.LEFT_TO_RIGHT
	bar:SetOrientation(orientation)

	bar:SetFont(Media:Fetch("font", self.db.profile.fontType), self.db.profile.fontScale, self.db.profile.fontFlags)
	bar:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
	bar:SetBackdrop({
		edgeFile = Media:Fetch("border", self.db.profile.resBarsBorder),
		tile = false,
		tileSize = self.db.profile.scale + 1,
		edgeSize = self.db.profile.borderThickness,
		insets = { left = 0, right = 0, top = 0, bottom = 0 }
	})
	timeOutBars[targetID] = bar
end

function SmartRes2:CreateResBar(casterID, endTime, targetID, isFirst, hasIncomingRes, isMassRes, spellID)
	-- self:Debug("CreateResBar #", strjoin(" # ", tostringall(casterID, endTime, targetID, isFirst, hasIncomingRes, isMassRes, spellID)))

	local spellName, _, icon
	local casterName
	local targetName
	local end_time = endTime - GetTime()
	local text
	local t -- bar colours

	if spellID then -- exists only for test bars
		spellName, _, icon = GetSpellInfo(spellID)
		casterName = casterID
		targetName = targetID
	else -- LibResInfo_ResCastStarted
		spellName, _, _, icon = UnitCastingInfo(casterID)
		casterName = UnitName(casterID)
		targetName = UnitName(targetID or "")
	end -- self:Debug("spellName", spellName, "casterName", casterName, "targetName", targetName)

	if resBars[casterName] then
		-- duplicate Mass Res bar
		return -- self:Debug("DUPLICATE MASS RES")
	end

	if self.db.profile.classColours then
		if isMassRes then
			text = format("%s: %s", ClassColouredName(casterID, casterName), spellName)
		else
			text = format(L["%s is ressing %s"], ClassColouredName(casterID, casterName), ClassColouredName(targeID, targetName))
		end
	else
		if isMassRes then
			text = format("%s: %s", casterName, spellName)
		else
			text = format(L["%s is ressing %s"], casterName, targetName)
		end
	end

	if hasIncomingRes == "PENDING" or hasIncomingRes == "SELFRES" then
		t = self.db.profile.waitingBarsColour
	elseif isFirst then
		-- check for first cast
		t = isMassRes and self.db.profile.massResBarColour or self.db.profile.resBarsColour
	else
		-- collision, could be class spell or Mass Res
		t = self.db.profile.collisionBarsColour
	end

	-- args are as follows: lib:NewTimerBar(name, text, time, maxTime, icon, flashTrigger)
	local bar, isNew = self.rez_bars:NewTimerBar(casterName, text, end_time, nil, icon, 0)
	bar:SetBackgroundColor(t.r, t.g, t.b, t.a)
	bar:SetColorAt(0, 0, 0, 0, 1) -- set bars to be black behind the cast bars
	bar.RegisterCallback(self.rez_bars, "FadeFinished", SmartRes2.ResBarsFadeFinished)

	orientation = (self.db.profile.horizontalOrientation == "RIGHT") and Bars.RIGHT_TO_LEFT or Bars.LEFT_TO_RIGHT
	bar:SetOrientation(orientation)

	if self.db.profile.resBarsIcon then
		bar:ShowIcon()
	else
		bar:HideIcon()
	end

	bar:SetHeight(self.db.profile.barHeight)
	bar:SetWidth(self.db.profile.barWidth)

	bar:SetFont(Media:Fetch("font", self.db.profile.fontType), self.db.profile.fontScale, self.db.profile.fontFlags)
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
function SmartRes2:ResBarsFadeFinished(event, bar, name)
	if not name then
		-- Hack to deal with LibBars callback setup
		self, event, bar, name = SmartRes2, self, event, bar
	end
	-- self:Debug("ResBarsFadeFinished", name)
	resBars[name] = nil
end
function SmartRes2:TimeOutBarsFadeFinished(event, bar, name)
	if not name then
		-- Hack to deal with LibBars callback setup
		self, event, bar, name = SmartRes2, self, event, bar
	end
	-- self:Debug("TimeOutBarsFadeFinished", name)
	resBars[name] = nil
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
	wipe(resBars)
end

--@debug@
_G.SmartRes2 = SmartRes2
--@end-debug@