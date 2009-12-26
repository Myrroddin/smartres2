-- SmartRes2
-- Author:  Myrroddin of Llane

-- load libraries & other stuff
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0", "LibBars-1.0")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)

local ResComm = LibStub:GetLibrary("LibResComm-1.0")
local Media = LibStub:GetLibrary("LibSharedMedia-3.0")

--[===[@debug@
_G.SmartRes2 = SmartRes2
--@end-debug@]===]

local db

-- register the res bar textures with LibSharedMedia-3.0
Media:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])
-- Media:Register("border", "Wood border", "Interface\\AchievementFrame\\UI-Achievement-WoodBorder.blp")

local hexcolors = {
	PRIEST = "FFFFFF",
	SHAMAN = "2459FF",
	PALADIN = "F58CBA",
	DRUID = "FF7D0A",
	DEATHKNIGHT = "C41F3B",
	HUNTER = "ABD473",
	MAGE = "69CCF0",
	ROGUE = "FFF569",
	WARLOCK = "9482C9",
	WARRIOR = "C79C6E",
}

-- really often used globals
local tinsert = table.insert
local tsort = table.sort
local pairs = pairs
local unpack = unpack
local in_combat = false

function SmartRes2:OnInitialize()
	-- called when SmartRes2 is loaded

	-- prepare spells
	self.resSpells = { -- getting the spell names
		PREIST = GetSpellInfo(2006), -- Resurrection
		SHAMAN = GetSpellInfo(2008), -- Ancestral Spirit
		DRUID = GetSpellInfo(50769), -- Revive
		PALADIN = GetSpellInfo(7328) -- Redemption
	}

	self.resSpellIcons = { -- need the icons too, for the res bars
		PRIEST = select(3, GetSpellInfo(2006)),
		SHAMAN = select(3, GetSpellInfo(2008)),
		DRUID = select(3, GetSpellInfo(50769)),
		PALADIN = select(3, GetSpellInfo(7328)),
	}
	self.playerClass = select (2, UnitClass("player"))  -- what class is the user?
	self.playerSpell = self.resSpells[self.playerClass] -- only has data if the player can cast a res spell

	local defaults = {
		profile = {
			scale = 1,
			horizontalOrientation = true,
			locked = false,
			resBarsTexture = "Blizzard",
			-- resBarsBorder = "Interface\\Tooltips\\UI-Tooltip-Border",
			reverseGrowth = false,
			resBarsColour = { r = 0, g = 1, b = 0, a = 1 },
			collisionBarsColour = { r = 1, g = 0, b = 0, a = 1 },
			resBarX = 470,
			resBarY = 375,
			autoResKey = "",
			manualResKey = "",
			notifySelf = true,
			notifyCollision = false,
			randMssgs = false,
			classColours = true,
			chatOutput = "none",
			resBarsIcon = true,
			randChatTbl = { -- this is here for eventual support for users to add or remove their own random messages
				[1] = L["%s is bringing %s back to life!"],
				[2] = L["Filthy peon! %s has to resurrect %s!"],
				[3] = L["%s has to wake %s from eternal slumber."],
				[4] = L["%s is ending %s's dirt nap."],
				[5] = L["No fallen heroes! %s needs %s to march forward to victory!"],
				[6] = L["%s doesn't think %s is immortal, but after this res cast, it is close enough."],
				[7] = L["Sleeping on the job? %s is disappointed in %s."],
				[8] = L["%s knew %s couldn't stay out of the fire. *Sigh*"],
				[9] = L["Once again, %s pulls %s and their bacon out of the fire."],
				[10] = L["%s thinks %s should work on their Dodge skill."],
				[11] = L["%s refuses to accept blame for %s's death, but kindly undoes the damage."],
				[12] = L["%s prods %s with a stick. A-ha! %s was only temporarily dead."],
				[13] = L["%s is ressing %s"],
				[14] = L["%s knows %s is faking. It was only a flesh wound!"],
				[15] = L["Oh. My. God. %s has to breathe life back into %s AGAIN?!?"],
				[16] = L["%s knows that %s dying was just an excuse to see another silly random res message."],
				[17] = L["Think that was bad? %s proudly shows %s the scar tissue caused by Ragnaros."],
				[18] = L["Just to be silly, %s tickles %s until they get back up."],
				[19] = L["FOR THE HORDE! FOR THE ALLIANCE! %s thinks %s should be more concerned about yelling FOR THE LICH KING! and prevents that from happening."],
				[20] = L["And you thought the Scourge looked bad. In about 10 seconds, %s knows %s will want a comb, some soap, and a mirror."],
				[21] = L["Somewhere, the Lich King is laughing at %s, because he knows %s will just die again eventually. More meat for the grinder!!"],
				[22] = L["%s doesn't want the Lich King to get another soldier, so is bringing %s back to life."],
				[23] = L["%s wonders about these stupid res messages. %s should just be happy to be alive."],
				[24] = L["%s prays over the corpse of %s, and a miracle happens!"],
				[25] = L["In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %s is making sure %s's death isn't permanent."],
				[26] = L["%s performs a series of lewd acts on %s's still warm corpse. Ew."]
			}
		}
	}

	-- register saved variables with AceDB
	self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, "Default")
	db = self.db.profile

	self.db.RegisterCallback(self, "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
	self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

	local options = {
		name = L["SmartRes2"],
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
					barsAnchor = {
						order = 2,
						type = "toggle",
						name = L["Show Anchor"],
						desc = L["Toggles the anchor for the res bars so you can move them"],
						get = function()
							return db.locked
						end,
						set = function(info, value)
							db.locked = value
							if value then
								self.res_bars:HideAnchor()
							else
								self.res_bars:ShowAnchor()
							end
						end
					},
					barsOptionsHeader2 = {
						order = 3,
						type = "description",
						name = ""
					},
					resBarsIcon = {
						order = 4,
						type = "toggle",
						name = L["Show Icon"],
						desc = L["Show or hide the icon for res spells"],
						get = function()
							return db.resBarsIcon
						end,
						set = function(info, value)
							db.resBarsIcon = value
						end
					},
					classColours = {
						order = 5,
						type = "toggle",
						name = L["Class Colours"],
						desc = L["Use class colours for the target on the res bars"],
						get = function()
							return db.classColours
						end,
						set = function(info, value)
							db.classColours = value
						end
					},
					resBarsTexture = {
						order = 6,
						type = "select",
						dialogControl = "LSM30_Statusbar",
						name = L["Texture"],
						desc = L["Select the texture for the res bars"],
						values = AceGUIWidgetLSMlists.statusbar,
						get = function()
							return db.resBarsTexture
						end,
						set = function(info, value)
							db.resBarsTexture = value
						end
					},
					--[[resBarsBGColour = {
						order = 7,
						type = "select",
						dialogControl = "LSM30_Background",
						name = L["Background Colour"],
						desc = L["Set the background colour for the res bars"],
						values = AceGUIWidgetLSMlists.background,
						get = function()
							return db.resBarsBGColour
						end,
						set = function(info, value)
							db.resBarsBGColour = value
						end
					},-- not sure if LibBars supports this
					resBarsBorder = {
						order = 8,
						type = "select",
						dialogControl = "LSM30_Border",
						name = L["Border"],
						desc = L["Set the border for the res bars"],
						values = AceGUIWidgetLSMlists.border,
						get = function()
							return db.resBarsBorder
						end,
						set = function(info, value)
							db.resbarsBorder = value
						end
					},]] -- not sure if LibBars supports this either
					resBarsColour = {
						order = 9,
						type = "color",
						name = L["Bar Colour"],
						desc = L["Pick the colour for non-collision (not a duplicate) res bar"],
						get = function()
							local t = db.resBarsColour
							return t.r, t.g, t.b, t.a
						end,
						set = function(info, r, g, b, a)
							local t = db.resBarsColour
							t.r, t.g, t.b, t.a = r, g, b, a
						end
					},
					collisionBarsColour = {
						order = 10,
						type = "color",
						name = L["Duplicate Bar Colour"],
						desc = L["Pick the colour for collision (duplicate) res bars"],
						get = function()
							local t = db.collisionBarsColour
							return t.r, t.g, t.b, t.a
						end,
						set = function(info, r, g, b, a)
							local t = db.collisionBarsColour
							t.r, t.g, t.b, t.a = r, g, b, a
						end
					},
					growDirection = {
						order = 11,
						type = "toggle",
						name = L["Grow Upwards"],
						desc = L["Make the res bars grow up instead of down"],
						get = function()
							return db.reverseGrowth
						end,
						set = function(info, value)
							db.reverseGrowth = value
							self.res_bars:ReverseGrowth(value)
						end
					},
					scale = {
						order = 12,
						type = "range",
						name = L["Scale"],
						desc = L["Set the scale for the res bars"],
						get = function()
							return db.scale
						end,
						set = function(info, value)
							db.scale = value
							self.res_bars:SetScale(value)
						end,
						min = 0.5,
						max = 2,
						step = 0.05
					},
					horizontalOrientation = {
						order = 13,
						type = "toggle",
						name = L["Horizontal Direction"],
						desc = L["Change the horizontal direction of the res bars. Default is right to left"],
						get = function()
							return db.horizontalOrientation
						end,
						set = function(info, value)
							db.horizontalOrientation = value
						end
					},
					resBarsTestBars = { -- need to fix the execute function
						order = 14,
						type = "execute",
						name = L["Test Bars"],
						desc = L["Show the test bars"],
						func = function()
							self:StartTestBars()
						end
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
					randMssgs = {
						order = 2,
						type = "toggle",
						name = L["Random Res Messages"],
						desc = L["Turn random res messages on or keep the same message.\nDefault is off"],
						get = function()
							return db.randMssgs
						end,
						set = function(info, value)
							db.randMssgs = value
						end
					},
					chatOutput = {
						order = 3,
						type = "select",
						name = L["Chat Output Type"],
						desc = L["Where to print the res message.\nRaid, Party, Say, Yell, Guild, or None.\nDefault is None"],
						values = {
							party = L["PARTY"],
							raid = L["RAID"],
							say = L["SAY"],
							yell = L["YELL"],
							guild = L["GUILD"],
							none = L["none"],
						},
						get = function()
							return db.chatOutput
						end,
						set = function(info, value)
							db.chatOutput = value
						end
					},
					notifySelf = {
						order = 4,
						type = "toggle",
						name = L["Self Notification"],
						desc = L["Prints a message to yourself whom you are ressing"],
						get = function()
							return db.notifySelf
						end,
						set = function(info, value)
							db.notifySelf = value
						end
					},
					notifyCollision = {
						order = 5,
						type = "toggle",
						name = L["Duplicate Res Targets"],
						desc = L["Toggle whether you want to whisper a resser who is ressing a\ntarget of another resser's spell.\nCould get very spammy.\nDefault off"],
						get = function()
							return db.notifyCollision
						end,
						set = function(info, value)
							db.notifyCollision = value
						end
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
						get = function()
							return db.autoResKey
						end,
						set = function(info, value)
							db.autoResKey = value
						end
					},
					manualResKey = {
						order = 2,
						type = "keybinding",
						name = L["Manual Target Key"],
						desc = L["Gives you the pointer to click on corpses"],
						get = function()
							return db.manualResKey
						end,
						set  = function(info, value)
							db.manualResKey = value
						end
					}
				}
			},
			creditsTab = {
				name = L["SmartRes2 Credits"],
				desc = L["About the author and SmartRes2"],
				type = "group",
				order = 5,
				args = {
					creditsHeader1 = {
						order = 1,
						type = "header",
						name = L["Credits"]
					},
					creditsDesc1 = {
						order = 2,
						type = "description",
						name = L["Massive kudos to Maia, Kyahx, and Poull for the original SmartRes.\nSmartRes2 was largely possible because of DathRarhek's LibResComm-1.0 so a big thanks to him."]
					},
					creditsDesc2 = {
						order = 3,
						type = "description",
						name = L["I would personally like to thank Jerry on the wowace forums for coding the new, smarter, resurrection function."]
					}
				}
			}
		}
	}

	-- add the 'Profiles' section
	options.args.profilesTab = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	options.args.profilesTab.order = 4

	-- Register your options with AceConfigRegistry
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("SmartRes2", options)

	 -- Add your options to the Blizz options window using AceConfigDialog
	self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SmartRes2", L["SmartRes2"])

	-- support for LibAboutPanel
	if LibStub:GetLibrary("LibAboutPanel", true) then
		self.optionsFrame[L["About"]] = LibStub("LibAboutPanel").new(L["SmartRes2"], "SmartRes2")
	end

	-- create chat commands
	self:RegisterChatCommand("sr", function() InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) end)
	self:RegisterChatCommand("smartres", function() InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) end)

	-- register for LibSharedMedia-3.0 updates
	Media.RegisterCallback(self, "OnValueChanged", "UpdateMedia")

	-- register a launcher
	local DataBroker = LibStub("LibDataBroker-1.1", true)
	if DataBroker then
		DataBroker:NewDataObject("SmartRes2", {
			type = "launcher",
			icon = self.resSpellIcons[self.playerClass] or self.resSpellIcons.Priest, -- "Interface\\Icons\\Spell_Holy_Resurrection", icon changes depending on class, or defaults to Resurrection, if not a resser
			OnClick = function(self, button)
				if button == "LeftButton" then
					self.res_bars:ToggleAnchor()
				elseif button == "RightButton" then
					InterfaceOptionsFrame_OpenToCategory(SmartRes2.optionsFrame)
				end
			end,
			OnTooltipShow = function(self)
				GameTooltip:AddLine(L["SmartRes2 "]..GetAddOnMetadata("SmartRes2", "version"), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
				GameTooltip:AddLine(L["Left click to lock/unlock the res bars. Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
				GameTooltip:Show()
			end
		})
	end

	-- create a secure button for ressing
	local resButton = CreateFrame("button", "SmartRes2Button", UIParent, "SecureActionButtonTemplate")
	resButton:SetAttribute("type", "spell")
	resButton:SetAttribute("PreClick", function() self:Resurrect() end)
	self.resButton = resButton

	self.Resser = {}
	self.Ressed = {}

	self.res_bars = self:NewBarGroup("SmartRes2", orientation, 300)
	self.res_bars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.resBarsX, db.resBarsY)
	self.res_bars:SetScale(db.scale)
	self.res_bars:ReverseGrowth(db.reverseGrowth)
	self.res_bars:SetTexture(Media:Fetch("statusbar", db.resBarsTexture))

	if db.locked then
		self.res_bars:ShowAnchor()
	else
		self.res_bars:HideAnchor()
	end

	-- register events so we can turn things off in combat, and back on when out of combat
	self:RegisterEvent("PLAYER_REGEN_ENABLED")
	self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function SmartRes2:OnEnable()
	-- called when SmartRes2 is enabled

	ResComm.RegisterCallback(self, "ResComm_ResStart")
	ResComm.RegisterCallback(self, "ResComm_Ressed")
	ResComm.RegisterCallback(self, "ResComm_ResEnd")

	self.res_bars.RegisterCallback(self, "AnchorMoved", "ResAnchorMoved")
end

function SmartRes2:OnDisable()
	-- called when SmartRes2 is disabled

	ResComm.UnregisterCallback(self, "ResComm_ResStart")
	ResComm.UnregisterCallback(self, "ResComm_Ressed")
	ResComm.UnregisterCallback(self, "ResComm_ResEnd")
	self:UnBindKeys()
end

--events, yay!
function SmartRes2:UpdateMedia(callback, type, handle)
	if type == "statusbar" then
		self.res_bars:SetTexture(Media:Fetch("statusbar", db.resBarsTexture))
		self.res_bars:SetColor(db.resBarsColour)
		self.res_bars:SetColor(db.collisionBarsColour)
		-- self.res_bars:SetBorder(db.resBarsBorder))
	end
end

function SmartRes2:PLAYER_REGEN_ENABLED()
	if self.playerSpell then
		self:BindKeys() -- only binds keys if the player can cast a res spell
	end

	ResComm.RegisterCallback(self, "ResComm_ResStart")
	ResComm.RegisterCallback(self, "ResComm_Ressed")
	ResComm.RegisterCallback(self, "ResComm_ResEnd")
	in_combat = false
end

function SmartRes2:PLAYER_REGEN_DISABLED()
	if not in_combat then
		if self.playerSpell then
			self:UnBindKeys()
		end
		ResComm.UnregisterCallback(self, "ResComm_ResStart")
		ResComm.UnregisterCallback(self, "ResComm_Ressed")
		ResComm.UnregisterCallback(self, "ResComm_ResEnd")
		-- Important Note: Since the release of patch 3.2, certain fights in the game fire the
		-- "PLAYER_REGEN_DISABLED" event continuously during combat causing any subsequent events
		-- we might trigger as a result to also fire continuously. It is recommended therefore to
		-- use a checking variable that is set to 'on/1/etc' when entering combat and back to
		-- 'off/0/etc' only when exiting combat and then use this as the final determinant on
		-- whether or not to action a subsequent event.
		in_combat = true
	end
end

function SmartRes2:OnProfileChanged()
	local db = self.db.profile
end

function SmartRes2:ResAnchorMoved(_, _, x, y)
	db.resBarsX, db.resBarsY = x, y
end

function SmartRes2:ResComm_ResStart(event, resser, endTime, targetName)
	if not self.Resser[resser] then return end
	self.Resser[resser] = {
		endTime = endTime,
		target = targetName
	}
	self:StartResBars(resser)
	self:UpdateResColours()

	local isSame = UnitIsUnit(resser, "player")
	if isSame == 1 then -- make sure only the player is sending messages
		if not (db.chatOutput == "none") then -- if it is "none" then don't send any chat messages
			if (db.randMssgs) then
				SendChatMessage(math.random(#db.randChatTbl), db.chatOutput, nil, nil):format(self.Resser[resser], self.Resser[target])
			else
				SendChatMessage(L["%s is ressing %s"], db.chatOutput, nil, nil):format(self.Resser[resser], self.Resser[target])
			end
		end
		if (db.notifySelf) then
			self:Print(L["You are ressing %s"]):format(self.Resser[target])
		end
	end
end

function SmartRes2:ResComm_ResEnd(event, ressed, target)
	-- did the cast fail or complete?
	if not self.Resser[resser] then return end

	self:StopResBars(resser)
	self.Resser[resser] = nil
	self:UpdateResColours()
end

function SmartRes2:ResComm_Ressed(event, ressed)
	if not self.Ressed[ressed] or ((self.Ressed[ressed] + 120) < GetTime()) then
		self.Ressed[ressed] = GetTime()
	end

	self:UpdateResColours()
end

function SmartRes2:UpdateResColours()
	local currentRes = {}
	local beingRessed = {}
	local duplicate = false
	local alreadyRessed = false

	for resserName, info in pairs(self.Resser) do
		tinsert(currentRes, info)
	end

	tsort(currentRes, function(a, b) return a.endTime < b.endTime end)

	for idx, info in pairs(currentRes) do
		duplicate = false
		alreadyRessed = false

		for i, ressed in pairs(beingRessed) do
			if (ressed == info.target) then
				r, g, b = unpack(db.collisionBarsColour) -- need to change to db.collisionBarsColour
				info.bar:SetBackgroundColor(r, g, b, 1)
				duplicate = true
				break
			end
		end

		for ressed, time in pairs(self.Ressed) do
			if (ressed == info.target) and (time + 120) > GetTime() then
				alreadyRessed = true
				break
			end
		end

		if not duplicate and not alreadyRessed then
			r,g,b = unpack(db.resBarsColour) -- need to change to db.resBarsColour
			info.bar:SetBackgroundColor(r,g,b,1)
		   tinsert(beingRessed,info.target)
		end

		if (duplicate or alreadyRessed) and (db.notifyCollision) then
			SendChatMessage(L["SmartRes2 would like you to know that %s is already being ressed by %s. "]..L["Please get SmartRes2 and use the auto res key to never see this whisper again."],
			"whisper", nil, info):format(beingRessed.info.target, info) -- are these the correct variables to be passing?
		end
	end
end

function SmartRes2:StartTestBars()
	SmartRes2:ResComm_Ressed(nil, L["Frankthetank"])
	SmartRes2:ResComm_ResStart(nil, L["Nursenancy"], GetTime() + 10, L["Frankthetank"])
	SmartRes2:ResComm_ResStart(nil, L["Dummy"], GetTime() + 3, L["Timthewizard"])
end

function SmartRes2:ClassColours(text, class)
	if class and hexcolors[class] then
		return format("|cff%s%s|r", hexcolors[class], text)
	else
		return text
	end
end

function SmartRes2:StartResBars(resser)
	local text
	local icon
	local name = resser
	local info = self.Resser[resser]
	local time = info.endTime - GetTime()
	local orientation

	if db.classColours then
		text = self:ClassColours(resser, select (2, UnitClass(resser)))..
			L["is resurrecting "]..
			self:ClassColours(info.target, select(2, UnitClass(info.target)))
	else
		text = (L["%s is resurrecting %s"]):format(resser, info.target)
	end

	if db.resBarsIcon then
		icon = self.resSpellIcons[resser]
	else
		icon = nil
	end

	if db.horizontalOrientation then
		orientation = 3 -- Bars.RIGHT_TO_LEFT
	else
		orientation = 1 -- Bars.LEFT_TO_RIGHT
		db.horizontalOrientation = false
	end

	-- args are as follows: lib:NewTimerBar(name, text, time, maxTime, icon, orientation,length, thickness)
	local bar = self.res_bars:NewTimerBar(name, text, time, nil, icon, orientation)
	r, g, b = unpack(db.resBarsColour) -- colours.green

	bar:SetBackgroundColor(r,g,b,1)
	bar:SetColorAt(0, 0, 0, 0, 1, 0)
	-- bar:SetBorder(db.resbarsBorder)

	self.Resser[resser].bar = bar
end

function SmartRes2:StopResBars(resser) -- have to test this function to see if I got it correct
	if not self.Resser[resser] then return end

	self.Resser[resser].bar:Fade(0.5) -- half second fade
end

-- set and unset keybindings
function SmartRes2:BindKeys()
	SetOverrideBindingClick(self.resButton, false, db.autoResKey, "SmartRes2Button")
	SetOverrideBindingSpell(self.resButton, false, db.manualResKey, self.playerSpell)
end

function SmartRes2:UnBindKeys()
	ClearOverrideBindings(self.ResButton)
end

local CLASS_PRIORITIES = {
	-- There might be 10 classes, but Shamans and Druids res at equal efficiency, so no preference
	-- non ressers who use Mana should be followed after ressers, as they are usually buffers
	-- or pet summoners (ie: Mana burners)
	-- res non Mana users last
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

local function getClassOrder(unit)
	local _, c = UnitClass(unit)
	return CLASS_PRIORITIES[c]
end

local unitOutOfRange, unitBeingRessed, unitDead

local function compareUnit(unitId, bestUnitId)
	-- bestUnitId is our best candidate yet (maybe nil if none was found yet).
	-- unitId is the next candidate.
	-- we return the best of the two.
	if not UnitIsDead(unitId) then return bestUnitId end
	unitDead = true
	if IsUnitBeingRessed(unitId) then unitBeingRessed = true return bestUnitId end
	if UnitIsGhost(unitId) then return bestUnitId end
	if not UnitInRange(unitId) then unitOutOfRange = true return bestUnitId end
	-- UnitIsVisable does not matter as all UnitInRange are Visable.
	-- i.e. UnitIsVisable() doesn't check LoS.
	-- here we have a valid candidate, so check first if we already saw one to compare to.
	if not bestUnitId then return unitId end
	-- we have two candidates. Only change candidate if it's better than the previous one.
	if getClassOrder(unitId) < getClassOrder(bestUnitId) then return unitId end
	if UnitLevel(unitId) > UnitLevel(bestUnitId) then return unitId end
	return bestUnitId
end

local function getBestCandidate()
	unitOutOfRange, unitBeingRessed, unitDead = nil, nil, nil
	local best = nil
	for i = 1, GetNumRaidMembers() do
		best = compareUnit("raid"..i, best)
	end
	if not best then
		for i = 1, GetNumPartyMembers() do
		  best = compareUnit("party"..i, best)
		end
	end
	return best
end

function SmartRes2:Resurrection()
	local resButton = self.resButton

	if GetNumPartyMembers() == 0 and not UnitInRaid("player") then
		self:Print(L["You are not in a group."])
		return
	end

	resButton:SetAttribute("unit", nil)
	resButton:SetAttribute("spell", nil)

	-- check if the player has enough Mana to cast a res spell. if not, no point in continuing. same if player is not a resser
	local isUsable, outOfMana = IsUsableSpell[self.PlayerSpell] -- determined during SmartRes2:OnInitialize()
	if outOfMana then
	   self:Print(L["You don't have enough Mana to cast a res spell."])
	   return
	elseif not isUsable then
		self:Print(L["You cannot cast res spells."]) -- in the final code, you should never see this message
		return
	end
	--[[ The previous will eventually be replaced with the following code. I am putting this in for clarity and bug fixing
	if not self.PlayerSpell then return end

	local _, outOfMana = IsUsableSpell[self.PlayerSpell]
	if outOfMana then
		self:Print(L["You don't have enough Mana to cast a res spell."]
	end]]--

	local unit = getBestCandidate()
	if unit then
		-- do something useful like setting the target of your button
		resButton:SetAttribute("unit", unit)
		resButton:SetAttribute("spell", self.playerSpell)
	else
		if unitOutOfRange then
			self:Print(L["There are no bodies in range to res."])
		elseif unitBeingRessed then
			self:Print(L["All dead units are being ressed."])
		elseif not unitDead then
			self:Print(L["Everybody is alive. Congratulations!"])
		end
	end
end