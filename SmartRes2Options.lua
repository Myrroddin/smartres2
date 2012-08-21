﻿local _G = getfenv(0)
local LibStub = _G.LibStub
local tinsert = _G.table.insert
local tremove = _G.table.remove
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = addon.L

local AceConfigDialog = LibStub("AceConfigDialog-3.0")

function addon:OptionsTable()
	local AceConfig = LibStub("AceConfig-3.0")
	local options = {
		name = "SmartRes2",
		handler = addon,
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
						order = 10,
						type = "header",
						name = L["Res Bars"]
					},
					resBarsTestBars = {
						order = 20,
						type = "execute",
						name = L["Test Bars"],
						desc = L["Show the test bars"],
						func = function() self:StartTestBars() end
					},
					spacer1 = {
						type = "description",
						name = "",
						order = 30
					},			
					hideAnchor = {
						order = 40,
						type = "toggle",
						name = L["Hide Anchor"],
						desc = L["Toggles the anchor for the res bars so you can move them"],
						get = function() return self.db.profile.hideAnchor end,
						set = function(info, value)
							self.db.profile.hideAnchor = value
							if value then
								self.rez_bars:HideAnchor()
								self.rez_bars:Lock()
							else
								self.rez_bars:ShowAnchor()
								self.rez_bars:Unlock()
								self.rez_bars:SetClampedToScreen(true)
							end
						end
					},
					enableAddon = {
						order = 50,
						type = "toggle",
						name = L["Enable SmartRes2"],
						desc = L["Uncheck to disable Smartres2"],
						get = function() return self.db.profile.enableAddon end,
						set = function(info, value)
							self.db.profile.enableAddon = value
							if value then
								self:Enable()
							else
								self:Disable()
							end
						end
					},					
					visibleResBars = { 
						order = 60,
						type = "toggle",
						name = L["Show Bars"],
						desc = L["Show or hide the res bars. Everything else will still work"],
						get = function() return self.db.profile.visibleResBars end,
						set = function(info, value) self.db.profile.visibleResBars = value end
					},
					guessResses = {
						order = 70,
						type = "toggle",
						name = L["Non-CTRA compatible res monitoring"],
						desc = L["Picks up res casts that are not broadcast via LibResComm or CTRA. This could have erroneous results, especially with mouseover or click casting"],
						get = function() return self.db.profile.guessResses end,
						set = function(info, value) self.db.profile.guessResses = value
							if self.db.profile.guessResses then
								self:StartGuessing()
							else
								self:StopGuessing()
							end
						end
					},
					reverseGrowth = {
						order = 80,
						type = "toggle",
						name = L["Grow Upwards"],
						desc = L["Make the res bars grow up instead of down"],
						get = function() return self.db.profile.reverseGrowth end,
						set = function(info, value)
							self.db.profile.reverseGrowth = value
							self.rez_bars:ReverseGrowth(value)
						end
					},					
					resBarsIcon = {
						order = 90,
						type = "toggle",
						name = L["Show Icon"],
						desc = L["Show or hide the icon for res spells"],
						get = function() return	self.db.profile.resBarsIcon end,
						set = function(info, value)
							self.db.profile.resBarsIcon = value
							if value then
								self.rez_bars:ShowIcon()
							else
								self.rez_bars:HideIcon()
							end
						end
					},					
					showBattleRes = {
						order = 100,
						type = "toggle",
						name = L["Show Battle Resses"],
						desc = L["Show bars for Rebirth"],
						get = function() return self.db.profile.showBattleRes end,
						set = function(info, value)	self.db.profile.showBattleRes = value end
					},					
					classColours = {
						order = 110,
						type = "toggle",
						name = _G.CLASS_COLORS,
						desc = L["Use class colours for the target on the res bars"],
						get = function() return self.db.profile.classColours end,
						set = function(info, value)	self.db.profile.classColours = value end
					},
					spacer2 = {
						type = "description",
						name = "",
						order = 130
					},					
					numMaxBars = {
						order = 160,
						type = "range",
						name = L["Maximum Bars"],
						desc = L["Set the maximum of displayed bars"],
						get = function() return self.db.profile.maxBars end,
						set = function(info, value)
							self.db.profile.maxBars = value
							self.rez_bars:SetMaxBars(value)
						end,
						min = 1,
						max = 39,
						step = 1
					},
					barHeight = {
						order = 170,
						type = "range",
						name = L["Bar Height"],
						desc = L["Control the height of the res bars"],
						get = function() return self.db.profile.barHeight end,
						set = function(info, value)
							self.db.profile.barHeight = value
							self.rez_bars:SetHeight(value)
						end,
						min = 6,
						max = 64,
						step = 1
					},
					barWidth = {
						order = 180,
						type = "range",
						name = L["Bar Width"],
						desc = L["Control the width of the res bars"],
						get = function() return self.db.profile.barWidth end,
						set = function(info, value)
							self.db.profile.barWidth = value
							self.rez_bars:SetWidth(value)
						end,
						min = 24,
						max = 512,
						step = 1
					},
					scale = {
						order = 190,
						type = "range",
						name = L["Scale"],
						desc = L["Set the scale for the res bars"],
						get = function() return self.db.profile.scale end,
						set = function(info, value)
							self.db.profile.scale = value
							self.rez_bars:SetScale(value)
						end,
						min = 0.5,
						max = 2,
						step = 0.05
					},
					resBarsAlpha = {
						order = 200,
						type = "range",
						name = L["Alpha"],
						desc = L["Set the Alpha for the res bars"],
						get = function() return self.db.profile.resBarsAlpha end,
						set = function(info, value)
							self.db.profile.resBarsAlpha = value
							self.rez_bars:SetAlpha(value)
						end,
						min = 0.1,
						max = 1,
						step = 0.1
					},
					borderThickness = {
						order = 210,
						type = "range",
						name = L["Border Thickness"],
						desc = L["Set the thickness of the res bars border"],
						get = function() return self.db.profile.borderThickness end,
						set = function(info, value) self.db.profile.borderThickness = value end,
						min = 1,
						max = 10,
						step = 1
					},
					spacer3 = {
						type = "description",
						name = "",
						order = 220
					},
					resBarsTexture = {
						order = 230,
						type = "select",
						dialogControl = "LSM30_Statusbar",
						name = _G.TEXTURES_SUBHEADER,
						desc = L["Select the texture for the res bars"],
						values = AceGUIWidgetLSMlists.statusbar,
						get = function() return self.db.profile.resBarsTexture end,
						set = function(info, value)	self.db.profile.resBarsTexture = value end
					},
					resBarsBorder = {
						order = 240,
						type = "select",
						dialogControl = "LSM30_Border",
						name = L["Border"],
						desc = L["Select the border for the res bars"],
						values = AceGUIWidgetLSMlists.border,
						get = function() return self.db.profile.resBarsBorder end,
						set = function(info, value) self.db.profile.resBarsBorder = value end
					},					
					horizontalOrientation = {
						order = 250,
						type = "select",
						name = L["Horizontal Direction"],
						desc = L["Change the horizontal direction of the res bars"],
						values = {
							["LEFT"] = L["Right to Left"],
							["RIGHT"] = L["Left to Right"]
						},
						get = function() return self.db.profile.horizontalOrientation end,
						set = function(info, value) self.db.profile.horizontalOrientation = value end
					},
					spacer4 = {
						type = "description",
						name = "",
						order = 260
					},
					resBarsColour = {
						order = 270,
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
						order = 280,
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
					waitingBarsColour = {
						order = 290,
						type = "color",
						name = L["Waiting Bar Colour"],
						desc = L["Pick the colour for collision (player waiting for accept) res bars"],
						hasAlpha = true,
						get = function()
							local t = self.db.profile.waitingBarsColour
							return t.r, t.g, t.b, t.a
						end,
						set = function(info, r, g, b, a)
							local t = self.db.profile.waitingBarsColour
							t.r, t.g, t.b, t.a = r, g, b, a
						end
					}	
				}
			},
			resChatTextTab = {
				name = _G.CHAT_OPTIONS_LABEL,
				desc = L["Chat output options"],
				type = "group",
				order = 20,
				args = {
					resChatHeader = {
						order = 10,
						type = "header",
						name = _G.CHAT_OPTIONS_LABEL
					},
					randMsgs = {
						order = 20,
						type = "toggle",
						name = L["Random Res Messages"],
						desc = L["Turn random res messages on or keep the same message. Default is off"],
						get = function() return self.db.profile.randMsgs end,
						set = function(info, value)	self.db.profile.randMsgs = value end
					},
					notifySelf = {
						order = 30,
						type = "toggle",
						name = L["Self Notification"],
						desc = L["Prints a message to yourself whom you are ressing"],
						get = function() return self.db.profile.notifySelf end,
						set = function(info, value)	self.db.profile.notifySelf = value end
					},
					spacer5 = {
						type = "description",
						name = "",
						order = 40
					},
					chatOutput = {
						order = 50,
						type = "select",
						name = L["Chat Output Type"],
						desc = L["Where to print the res message. Raid, Party, Say, Yell, Guild, smart Group, or None"],
						values = {
							["0-none"] = _G.NONE,
							group = _G.GROUP,
							guild = _G.CHAT_MSG_GUILD,
							party = _G.CHAT_MSG_PARTY,
							raid = _G.CHAT_MSG_RAID,
							say = _G.CHAT_MSG_SAY,
							whisper = _G.CHAT_MSG_WHISPER_INFORM,
							yell = _G.CHAT_MSG_YELL							
						},
						get = function() return self.db.profile.chatOutput end,
						set = function(info, value)	self.db.profile.chatOutput = value end
					},					
					notifyCollision = {
						order = 60,
						type = "select",
						name = L["Duplicate Res Targets"],
						desc = L["Notify a resser they created a collision. Could get very spammy"],
						values = {
							["0-off"] = _G.OFF,
							group = _G.GROUP,
							guild = _G.CHAT_MSG_GUILD,
							party = _G.CHAT_MSG_PARTY,
							raid = _G.CHAT_MSG_RAID,
							say = _G.CHAT_MSG_SAY,
							whisper = _G.CHAT_MSG_WHISPER_INFORM,
							yell = _G.CHAT_MSG_YELL
						},
						get = function() return self.db.profile.notifyCollision end,
						set = function(info, value)	self.db.profile.notifyCollision = value	end
					},
					spacer6 = {
						type = "description",
						name = "",
						order = 70
					},
					customMessage = {
						order = 80,
						type = "input",
						name = L["Custom Message"],
						desc = L["Your message.  Use 'me' for yourself and 'you' for target"],
						get = function() return self.db.profile.customchatmsg end,
						set = function(info, value) self:AddCustomMsg(value) end,
						width = "full"
					},
					addRndMessage = {
						order = 90,
						type = "input",
						name = L["Add to Random Table"],
						desc = L["ADD_OUTPUT_KEY"],
						get = function() return "" end,
						set = function(info, value)
							-- Insert non-empty values into the table
							if value and value:trim() ~= "" then
								tinsert(self.db.profile.randChatTbl, value) 
							end
						end,
						width = "full"
					},
					spacer7 = {
						type = "description",
						name = "",
						order = 100
					},
					removeRndMessge = {
						order = 110,
						type = "multiselect",
						dialogControl = "Dropdown",
						name = L["Remove Random Messages"],
						desc = L["Remove messages from the table you no longer want"],
						width = "full",
						values = function()
							-- Return the list of values
							return self.db.profile.randChatTbl
						end,
						get = function(info, index)
							-- All values are always enabled
							return true
						end,
						set = function(info, index, value)
							-- The only possible value for "value" is false (because get always returns true), so we don't bother checking it and remove the entry from the table
							tremove(self.db.profile.randChatTbl, index)
						end
					}
				}
			},
			fontTab = {
				name = L["Fonts"],
				desc = L["Control fonts on the res bars"],
				type = "group",
				order = 30,
				args = {
					fontType = {
						order = 10,
						type = "select",
						dialogControl = "LSM30_Font",
						name = L["Font Type"],
						desc = L["Select a font for the text on the res bars"],
						values = AceGUIWidgetLSMlists.font,
						get = function() return self.db.profile.fontType end,
						set = function(info, value) self.db.profile.fontType = value end					
					},								
					fontSize = {
						order = 20,
						type = "range",
						name = _G.FONT_SIZE,
						desc = L["Resize the res bars font"],
						get = function() return self.db.profile.fontScale end,
						set = function(info, value) self.db.profile.fontScale = value end,
						min = 3,
						max = 20,
						step = 1
					},
					fontFlags = {
						order = 30,
						type = "select",
						name = L["Font Style"],
						desc = L["Nothing, outline, thick outline, or monochrome"],						
						values = {
							["0-nothing"] = L["Nothing"],
							outline = L["Outline"],
							thickOut = L["THICK_OUTLINE"],
							monoChrome = L["Monochrome"]
						},
						get = function() return self.db.profile.fontFlags end,
						set = function(info, value) self.db.profile.fontFlags = value end
					}
				}			
			},
			keyBindingsTab = {
				name = _G.KEY_BINDINGS,
				type = "group",
				order = 40,
				args = {
					autoResKey = {
						order = 10,
						type = "keybinding",
						name = L["Auto Res Key"],
						desc = L["For ressing targets who have not released their ghosts"],
						get = function() return self.db.profile.autoResKey end,
						set = function(info, value)	self.db.profile.autoResKey = value end
					},
					manualResKey = {
						order = 20,
						type = "keybinding",
						name = L["Manual Target Key"],
						desc = L["Gives you the pointer to click on corpses"],
						get = function() return self.db.profile.manualResKey end,
						set  = function(info, value) self.db.profile.manualResKey = value end
					},
					massResKey = {
						order = 25,
						type = "keybinding",
						name = L["Mass Resurrection Key"],
						desc = L["Press to start the guild perk Mass Resurrection"],
						get = function() return self.db.profile.massResKey end,
						set = function(info, value) self.db.profile.massResKey = value end
					},
					--[===[@debug@
					castCommand = {
						order = 30,
						type = "description",
						name = L["The command \"cast\" will fire the smart Resurrection function. Usage: /sr cast or /smartres cast. Not necessary if you use the auto res key"]
					}
					--@end-debug@]===]
				}
			},
			creditsTab = {
				name = L["SmartRes2 Credits"],
				desc = L["About the author and SmartRes2"],
				type = "group",
				order = 60,
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
						name = "* "..L["Thank you translators!"]
					}
				}
			}
		}
	}
	return options
end