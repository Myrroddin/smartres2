﻿--- SmartRes2
-- @class file
-- @name SmartRes2.lua
-- @author Myrroddin of Llane

-- declare addon ------------------------------------------------------------

local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0", "LibBars-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)

-- get version from .toc - set to Development if no version
local version = GetAddOnMetadata("SmartRes2", "Version")

-- add localisation to addon
SmartRes2.L = L
-- declare the database
local db

-- localise global variables for faster access ------------------------------

local GetNumRaidMembers = GetNumRaidMembers
local GetNumPartyMembers = GetNumPartyMembers
local GetSpellInfo = GetSpellInfo
local UnitClass = UnitClass
local UnitInRaid = UnitInRaid
local UnitInRange = UnitInRange
local UnitIsDead = UnitIsDead
local UnitIsGhost = UnitIsGhost
local UnitLevel = UnitLevel
local pairs = pairs
local tinsert = table.insert
local tsort = table.sort
local sgsub = string.gsub
local wipe = wipe

-- debugging section --------------------------------------------------------

--[===[@debug@
_G.SmartRes2 = SmartRes2
--@end-debug@]===]

-- additional libraries -----------------------------------------------------

-- LibDataBroker used for LDB enabled addons like ChocolateBars
local DataBroker = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not DataBroker then
	LoadAddOn("LibDataBroker-1.1")
	local DataBroker = LibStub("LibDataBroker-1.1", true)
	if not DataBroker then
		error(format(L["%s requires the library '%s' to be available."], "SmartRes2", "LibDataBroker-1.1"))
	end
end
-- LibBars used for bars
local Bars = LibStub:GetLibrary("LibBars-1.0", true)
if not Bars then
	LoadAddOn("LibBars-1.0")
	local Bars = LibStub:GetLibrary("LibBars-1.0", true)
	if not Bars then
		error(format(L["%s requires the library '%s' to be available."], "SmartRes2", "LibBars-1.0"))
	end
end
-- LibResComm used for communication
local ResComm = LibStub:GetLibrary("LibResComm-1.0", true)
if not ResComm then
	LoadAddOn("LibResComm-1.0")
	local ResComm = LibStub:GetLibrary("LibResComm-1.0", true)
	if not ResComm then
		error(format(L["%s requires the library '%s' to be available."], "SmartRes2", "LibResComm-1.0"))
	end
end
-- LibSharedMedia used for more textures
local Media = LibStub:GetLibrary("LibSharedMedia-3.0", true)
-- register the res bar textures with LibSharedMedia-3.0
Media:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])

-- global variables ---------------------------------------------------------

-- local variables ----------------------------------------------------------
local doingRessing = {}
local waitingForAccept = {}
local resBars = {}
local orientation
local icon
local LastRes

--[===[@debug@
SmartRes2.doingRessing = doingRessing
SmartRes2.waitingForAccept = waitingForAccept
--@end-debug@]===]

-- variable for our addon preferences
local db
-- variable to use for multiple PLAYER_REGEN_DISABLED calls (see SmartRes2:PLAYER_REGEN_DISABLED below)
local in_combat = false
local Player = UnitName("player")

-- addon defaults -----------------------------------------------------------

local defaults = {
	profile = {
		autoResKey = "",
		chatOutput = "0-none",
		classColours = true,
		collisionBarsColour = { r = 1, g = 0, b = 0, a = 1 },
		disableAddon = false,
		hideAnchor = false,
		horizontalOrientation = "RIGHT",
		manualResKey = "",
		notifyCollision = "0-off",
		notifySelf = true,
		randMsgs = false,
		resBarsColour = { r = 0, g = 1, b = 0, a = 1 },
		resBarsIcon = true,
		-- resBarsBorder = "None",
		resBarsTexture = "Blizzard",
		resBarX = 470,
		resBarY = 375,
		reverseGrowth = false,
		scale = 1,
		showBattleRes = false,		
		visibleResBars = true,
		randChatTbl = { -- this is here for eventual support for users to add or remove their own random messages
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
	}
}

-- standard methods ---------------------------------------------------------

function SmartRes2:OnInitialize()
	-- register saved variables with AceDB
	db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, "Default")
	defaults = nil -- done with the table, so get rid of it
	self.db = db

	-- addon options table
	local options = {
		name = "SmartRes2",
		handler = SmartRes2,
		type = "group",
		childGroups = "tab",
		args = {
			barsOptionsTab = {
				name = L["Res Bars"],
				desc = L["Options for the res bars"],
				type = "group",
				order = 1,
				args = {
					barsOptionsHeader = {
						order = 1,
						type = "header",
						name = L["Res Bars"]
					},
					hideAnchor = {
						order = 2,
						type = "toggle",
						name = L["Hide Anchor"],
						desc = L["Toggles the anchor for the res bars so you can move them"],
						get = function() return self.db.profile.hideAnchor end,
						set = function(info, value)
							self.db.profile.hideAnchor = value
							if value then
								self.res_bars:HideAnchor()
							else
								self.res_bars:ShowAnchor()
							end
						end
					},
					disableAddon = {
						order = 3,
						type = "toggle",
						name = L["Disable SmartRes2"],
						desc = L["Completely disable Smartres2"],
						get = function() return self.db.profile.disableAddon end,
						set = function(info, value)
							self.db.profile.disableAddon = value
							if value then
								self:DisableSmartRes2()
							else
								self:EnableSmartRes2()
							end
						end
					},
					scale = {
						order = 4,
						type = "range",
						name = L["Scale"],
						desc = L["Set the scale for the res bars"],
						get = function() return self.db.profile.scale end,
						set = function(info, value)
							self.db.profile.scale = value
							self.res_bars:SetScale(value)
						end,
						min = 0.5,
						max = 2,
						step = 0.05
					},
					resBarsTexture = {
						order = 5,
						type = "select",
						dialogControl = "LSM30_Statusbar",
						name = L["Texture"],
						desc = L["Select the texture for the res bars"],
						values = AceGUIWidgetLSMlists.statusbar,
						get = function() return self.db.profile.resBarsTexture end,
						set = function(info, value)	self.db.profile.resBarsTexture = value end
					},					
					--[[ resBarsBorder = {
						order = 6,
						type = "select",
						dialogControl = "LSM30_Border",
						name = L["Border"],
						desc = L["Select the border for the res bars"],
						values = AceGUIWidgetLSMlists.border,
						get = function()
							return self.db.profile.resBarsBorder
						end,
						set = function(info, value)
							self.db.profile.resBarsBorder = value
						end
					},]] --
					horizontalOrientation = {
						order = 7,
						type = "select",
						name = L["Horizontal Direction"],
						desc = L["Change the horizontal direction of the res bars"],
						values = {
							["LEFT"] = L["Right to Left"],
							["RIGHT"] = L["Left to Right"], 
						},
						get = function() return self.db.profile.horizontalOrientation end,
						set = function(info, value) self.db.profile.horizontalOrientation = value end
					},
					reverseGrowth = {
						order = 8,
						type = "toggle",
						name = L["Grow Upwards"],
						desc = L["Make the res bars grow up instead of down"],
						get = function() return self.db.profile.reverseGrowth end,
						set = function(info, value)
							self.db.profile.reverseGrowth = value
							self.res_bars:ReverseGrowth(value)
						end
					},
					resBarsIcon = {
						order = 9,
						type = "toggle",
						name = L["Show Icon"],
						desc = L["Show or hide the icon for res spells"],
						get = function() return self.db.profile.resBarsIcon end,
						set = function(info, value)	self.db.profile.resBarsIcon = value end
					},
					classColours = {
						order = 10,
						type = "toggle",
						name = L["Class Colours"],
						desc = L["Use class colours for the target on the res bars"],
						get = function() return self.db.profile.classColours end,
						set = function(info, value)	self.db.profile.classColours = value end
					},
					showBattleRes = {
						order = 11,
						type = "toggle",
						name = L["Show Battle Resses"],
						desc = L["Show bars for Rebirth"],
						get = function() return self.db.profile.showBattleRes end,
						set = function(info, value)	self.db.profile.showBattleRes = value end
					},
					resBarsColour = {
						order = 12,
						type = "color",
						name = L["Bar Colour"],
						desc = L["Pick the colour for non-collision (not a duplicate) res bar"],
						hasAlpha = true,
						get = function()
							local t = self.db.profile.resBarsColour
							return t.r, t.g, t.b, t.a
						end,
						set = function(info, r, g, b, a)
							local t = self.db.profile.resBarsColour
							t.r, t.g, t.b, t.a = r, g, b, a
						end
					},
					collisionBarsColour = {
						order = 13,
						type = "color",
						name = L["Duplicate Bar Colour"],
						desc = L["Pick the colour for collision (duplicate) res bars"],
						hasAlpha = true,
						get = function()
							local t = self.db.profile.collisionBarsColour
							return t.r, t.g, t.b, t.a
						end,
						set = function(info, r, g, b, a)
							local t = self.db.profile.collisionBarsColour
							t.r, t.g, t.b, t.a = r, g, b, a
						end
					},
					resBarsTestBars = {
						order = 14,
						type = "execute",
						name = L["Test Bars"],
						desc = L["Show the test bars"],
						func = function() self:StartTestBars() end
					},
					visibleResBars = { 
						order = 15,
						type = "toggle",
						name = L["Show Bars"],
						desc = L["Show or hide the res bars. Everything else will still work"],
						get = function() return self.db.profile.visibleResBars end,
						set = function(info, value) self.db.profile.visibleResBars = value end
					}
				}
			},
			resChatTextTab = {
				name = L["Chat Output"],
				desc = L["Chat output options"],
				type = "group",
				order = 2,
				args = {
					resChatHeader = {
						order = 1,
						type = "header",
						name = L["Chat Output"]
					},
					randMsgs = {
						order = 2,
						type = "toggle",
						name = L["Random Res Messages"],
						desc = L["Turn random res messages on or keep the same message. Default is off"],
						get = function() return self.db.profile.randMsgs end,
						set = function(info, value)	self.db.profile.randMsgs = value end
					},
					chatOutput = {
						order = 3,
						type = "select",
						name = L["Chat Output Type"],
						desc = L["Where to print the res message. Raid, Party, Say, Yell, Guild, smart Group, or None"],
						values = {
							["0-none"] = L["None"],
							group = L["Group"],
							guild = L["Guild"],
							party = L["Party"],
							raid = L["Raid"],
							say = L["Say"],
							yell = L["Yell"],
						},
						get = function() return self.db.profile.chatOutput end,
						set = function(info, value)	self.db.profile.chatOutput = value end
					},
					notifySelf = {
						order = 4,
						type = "toggle",
						name = L["Self Notification"],
						desc = L["Prints a message to yourself whom you are ressing"],
						get = function() return self.db.profile.notifySelf end,
						set = function(info, value)	self.db.profile.notifySelf = value end
					},
					notifyCollision = {
						order = 5,
						type = "select",
						name = L["Duplicate Res Targets"],
						desc = L["Notify a resser they created a collision. Could get very spammy"],
						values = {
							["0-off"] = L["Off"],
							group = L["Group"],
							guild = L["Guild"],
							party = L["Party"],
							raid = L["Raid"],
							say = L["Say"],
							whisper = L["Whisper"],
							yell = L["Yell"],
						},
						get = function() return self.db.profile.notifyCollision end,
						set = function(info, value)	self.db.profile.notifyCollision = value	end
					},
					customMessage = {
						order = 6,
						type = "input",
						name = L["Custom Message"],
						desc = L["Your message.  Use 'me' for yourself and 'you' for target"],
						get = function() return self.db.profile.customchatmsg end,
						set = function(info, value) self:AddCustomMsg(value) end,
					}
				}
			},
			keyBindingsTab = {
				name = L["Key Bindings"],
				desc = L["Set the keybindings"],
				type = "group",
				order = 3,
				args = {
					autoResKey = {
						order = 1,
						type = "keybinding",
						name = L["Auto Res Key"],
						desc = L["For ressing targets who have not released their ghosts"],
						get = function() return self.db.profile.autoResKey end,
						set = function(info, value)	self.db.profile.autoResKey = value	end
					},
					manualResKey = {
						order = 2,
						type = "keybinding",
						name = L["Manual Target Key"],
						desc = L["Gives you the pointer to click on corpses"],
						get = function() return self.db.profile.manualResKey end,
						set  = function(info, value) self.db.profile.manualResKey = value end
					},
					castCommand = {
						order = 3,
						type = "description",
						name = L["The command \"cast\" will fire the smart Resurrection function. Usage: /sr cast or /smartres cast. Not necessary if you use the auto res key"]
					}
				}
			},
			creditsTab = {
				name = L["SmartRes2 Credits"],
				desc = L["About the author and SmartRes2"],
				type = "group",
				order = 6,
				args = {
					creditsHeader1 = {
						order = 1,
						type = "header",
						name = L["Credits"]
					},
					creditsDesc1 = {
						order = 2,
						type = "description",
						name = "* "..L["Massive kudos to Maia, Kyahx, and Poull for the original SmartRes. SmartRes2 was largely possible because of DathRarhek's LibResComm-1.0 so a big thanks to him."]
					},
					creditsDesc2 = {
						order = 3,
						type = "description",
						name = "* "..L["I would personally like to thank Jerry on the wowace forums for coding the new, smarter, resurrection function."]
					},
					creditsDesc3 = {
						order = 4,
						type = "description",
						name = "* "..L["Many bugfixes and development help from Onaforeignshore"]
					},
					creditsDesc5 = {
						order = 5,
						type = "description",
						name = "* "..L["German translation by Farook, Black_Mystics, Xevilgrin, and Dessa"],
					},
					creditsDesc6 = {
						order = 6,
						type = "description",
						name = "* "..L["French translation by Ckeurk and Xilbar"],
					},
					creditsDesc7 = {
						order = 7,
						type = "description",
						name = "* "..L["Latin American Spanish and Spanish translation by Silmano"],
					},
					creditsDesc8 = {
						order = 8,
						type = "description",
						name = "* "..L["Russian translation by Xenobios"],
					},
					creditsDesc9 = {
						order = 9,
						type = "description",
						name = "* "..L["Traditional Chinese translation by Whocare"],
					},
					creditsDesc10 = {
						order = 10,
						type = "description",
						name = "* "..L["Additional translations by Mattbnr"]
					}
				}
			}
		}
	}
	-- add the 'Profiles' section
	options.args.profilesTab = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profilesTab.order = 5

	-- Register your options with AceConfigRegistry
	LibStub("AceConfig-3.0"):RegisterOptionsTable("SmartRes2", options)

	-- Add your options to the Blizz options window using AceConfigDialog
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SmartRes2", "SmartRes2")	

	-- support for LibAboutPanel
	if LibStub:GetLibrary("LibAboutPanel", true) then
		self.optionsFrame[L["About"]] = LibStub("LibAboutPanel").new("SmartRes2", "SmartRes2")
	end

	-- add console commands
	self:RegisterChatCommand("sr", "SlashHandler")
	self:RegisterChatCommand("smartres", "SlashHandler")	

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
	self.playerClass = select(2, UnitClass("player"))  -- what class is the user?
	self.playerSpell = resSpells[self.playerClass] -- only has data if the player can cast a res spell

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
					self.res_bars:HideAnchor()
				else
					self.res_bars:ShowAnchor()
				end
				LibStub("AceConfigRegistry-3.0"):NotifyChange("SmartRes2")
			elseif button == "RightButton" then
				InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
			end
		end,
		OnTooltipShow = function(self)
			GameTooltip:AddLine("SmartRes2".." "..version, HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
			GameTooltip:AddLine(L["Left click to lock/unlock the res bars. Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
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

	-- create the Res Bars and set the user preferences
	if self.db.profile.visibleResBars then
		self.res_bars = self:NewBarGroup("SmartRes2", self.db.horizontalOrientation, 300, 15, "SmartRes2_ResBars")
		self.res_bars:SetPoint("CENTER", UIParent, "CENTER", self.db.profile.resBarsX, self.db.profile.resBarsY)
		self.res_bars:SetScale(self.db.profile.scale)
		self.res_bars:ReverseGrowth(self.db.profile.reverseGrowth)
		self.res_bars:SetUserPlaced(true)
		-- self.res_bars:SetBackdrop(Media:Fetch("border", self.db.profile.ResBarsBorder))
		-- set the icon to the user preference
		if self.db.profile.resBarsIcon then
			self.res_bars:ShowIcon()
		else
			self.res_bars:HideIcon()
		end
		-- set the anchor to the user preference
		if self.db.profile.hideAnchor then
			self.res_bars:HideAnchor()
		else
			self.res_bars:ShowAnchor()
		end
	end

end

function SmartRes2:OnEnable()
	-- called when SmartRes2 is enabled	
	self:EnableSmartRes2()
end

function SmartRes2:OnDisable()
	-- called when SmartRes2 is disabled
	self:DisableSmartRes2()
end

-- process slash commands ---------------------------------------------------
function SmartRes2:SlashHandler(input)
	input = input:lower()
	if input == "cast" then
		self:Resurrection()
	else
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	end
end

-- enable and disable SmartRes2 ---------------------------------------------

-- enable SmartRes2 ----------------------------------------------------------
function SmartRes2:EnableSmartRes2()
-- register events so we can turn things off in combat, and back on when out of combat
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("RAID_ROSTER_UPDATE")
	-- register Profile callbacks
	db.RegisterCallback(self, "OnProfileChanged")
	db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
	-- register Media change callbacks
	Media.RegisterCallback(self, "OnValueChanged", "UpdateMedia")	
	-- register LibResComm event callbacks
	ResComm.RegisterCallback(self, "ResComm_ResStart")
	ResComm.RegisterCallback(self, "ResComm_ResEnd")
	ResComm.RegisterCallback(self, "ResComm_Ressed")
	ResComm.RegisterCallback(self, "ResComm_ResExpired")	
	-- register bars callbacks
	self.res_bars.RegisterCallback(self, "FadeFinished")
	self.res_bars.RegisterCallback(self, "AnchorMoved", "ResAnchorMoved")
	-- call keybindings function
	self:BindKeys()
end

-- disable SmartRes2 completely ----------------------------------------------
function SmartRes2:DisableSmartRes2()
	self:UnBindKeys()
	SmartRes2.UnregisterAllEvents(self)
	ResComm.UnregisterAllCallbacks(self)
	self.res_bars.UnregisterAllCallbacks(self)
	Media.UnregisterAllCallbacks(self)
	wipe(doingRessing)
	wipe(waitingForAccept)
	wipe(resBars)
end

-- General callback functions -----------------------------------------------

-- called when user changes profile
function SmartRes2:OnProfileChanged()
	db = self.db
end

-- called when user changes the texture of the bars
function SmartRes2:UpdateMedia(callback, type, handle)
	if type == "statusbar" then
		self.res_bars:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
	end
	--[[if type == "border" then
		self.res_bars:SetBackdrop(Media:Fetch("border", self.db.profile.resBarsBorder))
	end]]--
end

function SmartRes2:AddCustomMsg(msg)
	msg = sgsub(msg, "me", "%%%%p%%%%")
	msg = sgsub(msg, "you", "%%%%t%%%%")
	self.db.profile.customchatmsg = msg
end

-- ResComm library callback functions ---------------------------------------

-- ResComm events - called when res is started
function SmartRes2:ResComm_ResStart(event, sender, endTime, targetName)
	-- check if we have the person in our table yet, and if not, add them
	if not doingRessing[sender] then
		doingRessing[sender] = {
			endTime = endTime,
			target = targetName
		}
	end
	self:CreateResBar(sender)
	local isSame = UnitIsUnit(sender, "player")
	if isSame == 1 then -- make sure only the player is sending messages
		local channel = self.db.profile.chatOutput:upper()
		if channel == "GROUP" then
			if UnitInRaid("player") then
				channel = "RAID"
			elseif GetNumPartyMembers() > 0 then
				channel = "PARTY"
			else
				channel = "NONE"
			end
		end
		if channel ~= "0-NONE" then -- if it is "none" then don't send any chat messages
			local msg = L["%%p%% is ressing %%t%%"]
			if self.db.profile.randMsgs then
				msg = self.db.profile.randChatTbl[math.random(#self.db.profile.randChatTbl)]
			elseif self.db.profile.customchatmsg ~= "" then
				msg = self.db.profile.customchatmsg
			end
			msg = sgsub(msg, "%%%%p%%%%", sender)
			msg = sgsub(msg, "%%%%t%%%%", targetName)
			SendChatMessage(msg, channel, nil, nil)
		end
		if self.db.profile.notifySelf then
			self:Print((L["You are ressing %s"]):format(targetName))
		end
	end
end

-- ResComm events - called when res ends
function SmartRes2:ResComm_ResEnd(event, sender, target)
	-- did the cast fail or complete?
	if not doingRessing[sender] then return end
	self:DeleteResBar(sender)
	-- add the target to our waiting list, and save who the last person to res him was
	waitingForAccept[target] = { target = target, sender = sender, endTime = doingRessing[sender].endTime }
	doingRessing[sender] = nil
end

-- ResComm events - called when player accepts res
function SmartRes2:ResComm_Ressed(event, target)
	-- target accepted, remove from list
	waitingForAccept[target] = nil
end

-- ResComm events - called when res box disappears or player declines res
function SmartRes2:ResComm_ResExpired(event, target)
	-- target declined, remove from list
	waitingForAccept[target] = nil
end

-- ResComm events - called when bar finished fading
function SmartRes2:FadeFinished(event, bar, name)
	self.res_bars:ReleaseBar(bar)
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
	-- reenable callbacks during battle if we don't want to see battle resses
	if not self.db.profile.showBattleRes then
		ResComm.RegisterCallback(self, "ResComm_ResStart")
		ResComm.RegisterCallback(self, "ResComm_ResEnd")
		ResComm.RegisterCallback(self, "ResComm_Ressed")
		ResComm.RegisterCallback(self, "ResComm_ResExpired")
		self.res_bars.RegisterCallback(self, "FadeFinished")
	end
	in_combat = false
end

-- key binding functions ----------------------------------------------------

function SmartRes2:BindKeys()
	-- only binds keys if the player can cast an out of combat res spell
	if not self.playerSpell then return end
	SetOverrideBindingClick(self.resButton, false, self.db.profile.autoResKey, "SmartRes2Button")
	SetOverrideBindingSpell(self.resButton, false, self.db.profile.manualResKey, self.playerSpell)
end

function SmartRes2:UnBindKeys()
	ClearOverrideBindings(self.resButton)
end

-- anchor management functions ----------------------------------------------

function SmartRes2:ResAnchorMoved(_, _, x, y)
	self.db.profile.resBarsX, self.db.profile.resBarsY = x, y
end

-- smart ressurection determination functions -------------------------------
local raidUpdated

function SmartRes2:RAID_ROSTER_UPDATE()
	raidUpdated = true
end

local unitOutOfRange, unitBeingRessed, unitDead, unitWaiting
local SortedResList = {}
local CLASS_PRIORITIES = {
	-- There might be 10 classes, but SHAMANs and DRUIDs res at equal efficiency, so no preference
	-- non healers who use Mana should be followed after healers, as they are usually buffers
	-- or pet summoners (ie: Mana burners)
	-- res non Mana users last (HUNTERs will get moved once Catalclysm hits)
	PRIEST = 1, 
	PALADIN = 2, 
	SHAMAN = 3, 
	DRUID = 3, 
	MAGE = 4, 
	WARLOCK = 4, 
	HUNTER = 4,
	DEATHKNIGHT = 5,
	ROGUE = 5,
	WARRIOR = 5
}

-- create resurrection tables
local function getClassOrder(unit)
	local _, c = UnitClass(unit)
	local lvl = UnitLevel(unit)
	return CLASS_PRIORITIES[c], lvl
end

local function verifyUnit(unit)
	-- unit is the next candidate. there is NO way to check LoS, so don't ask!
	if not UnitIsDead(unit) then return nil end
	unitDead = true
	if unit == LastRes then return nil end
	if ResComm:IsUnitBeingRessed(unit) then unitBeingRessed = true return nil end
	if waitingForAccept[unit] then unitWaiting = true return nil end
	if UnitIsGhost(unit) then return nil end
	if IsSpellInRange(self.playerSpell, unit) == 0 then unitOutOfRange = true return nil end
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
	unitOutOfRange, unitBeingRessed, unitDead, unitWaiting = nil, nil, nil, nil
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
	local isUsable, outOfMana = IsUsableSpell(self.playerSpell) 
	if outOfMana then 
	   self:Print(L["You don't have enough Mana to cast a res spell."]) 
	   return 
	elseif not isUsable then 
		self:Print(L["You cannot cast res spells."]) -- in the final code, you should never see this message
		return 
	end

	local unit = getBestCandidate()
	if unit then
		-- do something useful like setting the target of your button
		resButton:SetAttribute("unit", unit)
		waitingForAccept[unit] = { target = unit, sender = Player, endTime = GetTime() + 1000 }
		LastRes = unit
	else
		if unitOutOfRange then
			self:Print(L["There are no bodies in range to res."])
		elseif unitBeingRessed or unitWaiting then
			self:Print(L["All dead units are being ressed."])
		elseif not unitDead then
			self:Print(L["Everybody is alive. Congratulations!"])
			wipe(waitingForAccept)
		end
	end
end

-- resbar functions ---------------------------------------------------------

local function ClassColouredName(name)
	if not name then return "|cffcccccc"..L["Unknown"].."|r" end
	local _, class = UnitClass(name)
	if not class then return "|cffcccccc"..name.."|r" end
	local c = RAID_CLASS_COLORS[class]
	return ("|cff%02X%02X%02X%s|r"):format(c.r * 255, c.g * 255, c.b * 255, name)
end

function SmartRes2:CreateResBar(sender)
	local text
	local senderClass = select(2, UnitClass(sender))
	if senderClass == "DRUID" and in_combat then
		icon = select(3, GetSpellInfo(20484))
	else		
		icon = icon == self.resSpellIcons[select(2, UnitClass(sender))] or self.resSpellIcons.PRIEST
	end
	local name = sender
	local info = doingRessing[sender]
	local time = info.endTime - GetTime()
	local maxTime = sender.endTime

	if self.db.profile.classColours then
		text = (L["%s is ressing %s"]):format(ClassColouredName(sender), ClassColouredName(info.target))
	else
		text = (L["%s is ressing %s"]):format(sender, info.target)
	end

	-- args are as follows: lib:NewTimerBar(name, text, time, maxTime, icon, flashTrigger)
	if self.db.profile.visibleResBars then
		local bar = self.res_bars:NewTimerBar(name, text, time, maxTime, icon, 0)
		local t = self.db.profile.resBarsColour
		bar:SetBackgroundColor(t.r, t.g, t.b, t.a)
		bar:SetColorAt(0, 0, 0, 0, 1) -- sets bars to be black behind the cast bars
		bar:SetTexture(Media:Fetch("statusbar", self.db.profile.resBarsTexture))
		if self.db.profile.resBarsIcon then
			bar:ShowIcon()
		else
			bar:HideIcon()
		end	
		if self.db.profile.horizontalOrientation == "RIGHT" then
			orientation = Bars.RIGHT_TO_LEFT
			bar:SetOrientation(orientation)
		else
			orientation = Bars.LEFT_TO_RIGHT
			bar:SetOrientation(orientation)
		end

		resBars[sender] = resBars[sender] or {}
		resBars[sender][info.target] = resBars[sender][info.target] or {}
		resBars[sender][info.target].bar = bar
		resBars[sender][info.target].endTime = info.endTime
		self:UpdateResColours()
	end
end

function SmartRes2:DeleteResBar(sender)
	local info = doingRessing[sender]
	if not info then return end
	resBars[sender][info.target].bar:Fade(0.1) -- 1/10 second fade
end

function SmartRes2:UpdateResColours()
	local currentRes = {}
	local t = self.db.profile.collisionBarsColour
	local chatType = self.db.profile.notifyCollision:upper()
	-- collision res chat notification stuff
	if chatType == "GROUP" then
		if GetNumRaidMembers() > 0 then
			chatType = "RAID"
		elseif GetNumPartyMembers() > 0 then
			chatType = "PARTY"
		end
	end

	-- add waitingForAccept entries to the table
	for sender, v in pairs(waitingForAccept) do
		currentRes[v.target] = currentRes[v.target] or {}
		currentRes[v.target].endTime = v.endTime
	end

	-- iterate through the healers
	for sender, v in pairs(resBars) do
		-- iterate through their targets
		for target, info in pairs(v) do
			-- check if the target exists
			if currentRes[target] then
				-- if the one we're testing ends before the one in the table
				if info.endTime < currentRes[target].endTime then
					-- if the bar exists
					if resBars[currentRes[target].sender] and resBars[currentRes[target].sender][target].bar then
						-- change the colour of the one in the table
						resBars[currentRes[target].sender][target].bar:SetBackgroundColor(t.r, t.g, t.b, t.a)
						-- send chat message if set
						if chatType == "WHISPER" then
							SendChatMessage((L["SmartRes2 would like you to know that %s is already being ressed by %s."]):format(target, sender), chatType, nil, currentRes[target].sender)
						elseif chatType ~= "0-OFF" then
							SendChatMessage((L["SmartRes2 would like you to know that %s is already being ressed by %s."]):format(target, sender), chatType)
						end
					end
				else -- info.endTime > currentRes[target].endTime
					-- if the bar exists
					if resBars[sender][target].bar then
						-- change the colour of our bar
						resBars[sender][target].bar:SetBackgroundColor(t.r, t.g, t.b, t.a)
						-- send chat message if set
						if chatType == "WHISPER" then
							SendChatMessage((L["SmartRes2 would like you to know that %s is already being ressed by %s."]):format(target, sender), chatType, nil, currentRes[sender].target)
						elseif chatType ~= "0-OFF" then
							SendChatMessage((L["SmartRes2 would like you to know that %s is already being ressed by %s."]):format(target, sender), chatType)
						end
					end
				end
			else -- otherwise add the target
				currentRes[target] = info
				currentRes[target].sender = sender
			end
		end
	end
	wipe(currentRes)
end

function SmartRes2:StartTestBars()
	-- we don't want the test bars to throw an error if notify collision is on
	local settings = self.db.profile.notifyCollision
	if settings ~= "0-off" then
		self.db.profile.notifyCollision = "0-off"
	end

	-- set up the test bars
	waitingForAccept["Someone"] = { target = "Someone", sender = "Dummy", endTime = GetTime() - 6 }
	doingRessing["Nursenancy"] = { target = "Frankthetank", endTime = GetTime() + 6 }
	self:CreateResBar("Nursenancy")
	doingRessing["Dummy"] = { target = "Frankthetank", endTime = GetTime() + 2 }
	self:CreateResBar("Dummy")
	doingRessing["Gabriel"] = { target = "Someone", endTime = GetTime() + 4 }
	self:CreateResBar("Gabriel")
	self:UpdateResColours()

	-- clean up
	doingRessing["Nursenancy"] = nil
	doingRessing["Dummy"] = nil
	doingRessing["Gabriel"] = nil
	waitingForAccept["Someone"] = nil
	
	-- set the collision back to user preferences
	self.db.profile.notifyCollision = settings
end