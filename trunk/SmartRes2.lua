-- SmartRes2
-- Author:  Myrroddin of Llane

-- load libraries & other stuff
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)
local ResComm = LibStub("LibResComm-1.0")
local Media = LibStub:GetLibrary("LibSharedMedia-3.0")
local Candy = LibStub("LibCandyBar-3.0")
local Bars = LibStub("LibBars-1.0")
local DataBroker = LibStub:GetLibrary("LibDataBroker-1.1", true)

local Addon = SmartRes2

-- register the res bar textures with LibSharedMedia-3.0
Media:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])
--[[Media:Register("statusbar", "Banto", [[Interface\AddOns\SmartRes2\Textures\banto.tga]])
Media:Register("statusbar", "Charcoal", [[Interface\AddOns\SmartRes2\Textures\Charcoal.tga]])
Media:Register("statusbar", "Cilo", [[Interface\AddOns\SmartRes2\Textures\cilo.tga]])
Media:Register("statusbar", "Glaze", [[Interface\AddOns\SmartRes2\Textures\glaze.tga]])
Media:Register("statusbar", "Perl", [[Interface\AddOns\SmartRes2\Textures\perl.tga]])
Media:Register("statusbar", "Smooth", [[Interface\AddOns\SmartRes2\Textures\smooth.tga]])
]]-- keep it simple, if users want more, they can use SharedMedia, as it comes with these anyway

local colours = {
    green = {0, 1, 0},
    red = {1, 0, 0}
}

-- really often used globals
local tinsert = table.insert
local tsort = table.sort
local pairs = pairs
local unpack = unpack

       
function Addon:OnInitialize()
    -- called when SmartRes2 is loaded
    --@alpha@
    self:Print("This is the OnInitialization of SmartRes2")
    --@end-alpha@
    
    local options = {
        name = L["SmartRes2"],
        handler = "SmartRes2",
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
                        name = L["Res Bars"],
                    },
                    barsAnchor = {
                        order = 2,
                        type = "toggle",
                        name = L["Res Bars Anchor"],
                        desc = L["Toggles the anchor for the res bars so you can move them"],
                        get = function()
                            return self.db.profile.barsAnchor
                        end,
                        set = function(info, value)
                            if value then
                                self.res_bars:HideAnchor();
                                self.db.profile.locked = true
                            else
                                self.res_bars:ShowAnchor();
                                self.db.profile.barsAnchor = false
                            end
                        end,
                    },
                    barsOptionsHeader2 = {
                        order = 3,
                        type = "description",
                        name = "",
                    },
                    resBarsIcon = {
                        order = 4,
                        type = "toggle",
                        name = L["Res Bars Icon"],
                        desc = L["Show or hide the icon for res spells"],
                        get = function()
                            return self.db.profile.resBarsIcon
                        end,
                        set = function(info, value)
                            self.db.profile.resBarsIcon = value
                        end,
                    },
                    classColours = {
                        order = 5,
                        type = "toggle",
                        name = L["Class Colours"],
                        desc = L["Use class colours for the target on the res bars"],
                        get = function()
                            return self.db.profile.classColours
                        end,
                        set = function(info, value)
                            self.db.profile.classColours = value
                        end,
                    },
                    resBarsTexture = {
                        order = 6,
                        type = "select",
                        dialogControl = "LSM30_StatusBar",
                        name = L["Res Bars Texture"],
                        desc = L["Select the texture for the res bars"],
                        values = Media:HashTable(type),
                        get = function()
                            return self.db.proflile.resBarsTexture
                        end,
                        set = function(self, value)
                            self.db.profile.resBarsTexture = value
                        end,
                    },
                    resBarsBGColour = {
                        order = 7,
                        type = "select",
                        dialogControl = "LSM30_Background",
                        name = L["Res Bars Background Colour"],
                        desc = L["Set the background colour for the res bars"],
                        values = Media:HashTable(type),
                        get = function()
                            return self.db.profile.resBarsBGColour
                        end,
                        set = function(self, value)
                            self.db.profile.resBarsBGColour = value
                        end,
                    },
                    resBarsBorder = {
                        order = 8,
                        type = select,
                        dialogControl = "LSM30_Border",
                        name = L["Res Bars Border"],
                        desc = L["Set the border for the res bars"],
                        values = Media:HashTable(type),
                        get = function()
                            return self.db.profile.resBarsBorder
                        end,
                        set = function(self, value)
                            self.db.profile.resbarsBorder = value
                        end,
                    },
                    resBarsColour = {
                        order = 9,
                        type = "color",
                        name = L["Res Bars Colour"],
                        desc = L["Pick the colour for non-collision (not a duplicate) res bar"],
                        get = function()
                            return self.db.profile.resBarsColour
                        end,
                        set = function(info, value)
                            self.db.profile.resBarsColour = value
                        end,
                    },
                    collisionBarsColour = {
                        order = 10,
                        type = "color",
                        name = L["Duplicate Res Bars Colour"],
                        desc = L["Pick the colour for collision (duplicate) res bars"],
                        get = function()
                            return self.db.profile.collisionBarsColour
                        end,
                        set = function(info, value)
                            self.db.profile.collisionBarsColour = value
                        end,
                    },
                    growDirection = {
                        order = 11,
                        type = "toggle",
                        name = L["Grow Upwards"],
                        desc = L["Make the res bars grow up instead of down"],
                        get = function()
                            return self.db.profile.reverseGrowth
                        end,
                        set = function(info, value)
                            self.db.profile.reverseGrowth = value
                            self.res_bars:ReverseGrowth(value)
                        end,
                    },
                    scale = {
                        order = 12,
                        type = "range",
                        name = L["Res Bars Scale"],
                        desc = L["Set the scale for the res bars"],
                        get = function()
                            return self.db.profile.scale
                        end,
                        set = function(info, value)
                            self.db.profile.scale = value
                            self.res_bars:SetScale(value)
                        end,
                        min = 0.5,
                        max = 2,
                        step = 0.05,
                    },
                    resBarsTestBars = { -- need to fix the execute function
                        order = 13,
                        type = "execute",
                        name = L["Test Bars"],
                        desc = L["Show the test bars"],
                        func = function() self.StartTestBars()
                    end,
                    },               
                },
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
                        name = L["Chat Output"],
                    },
                    randMssgs = {
                        order = 2,
                        type = "toggle",
                        name = L["Random Res Messages"],
                        desc = L["Turn random res messages on or keep the same message.\nDefault is off"],
                        get = function()
                            return self.db.profile.randMssgs
                        end,
                        set = function(info, value)
                            self.db.profile.randMssgs = value
                        end,
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
                            return self.db.profile.chatOutput
                        end,
                        set = function(info, value)
                            self.db.profile.chatOutput = value
                        end,
                    },
                    notifySelf = {
                        order = 4,
                        type = "toggle",
                        name = L["Self Notification"],
                        desc = L["Prints a message to yourself whom you are ressing"],
                        get = function()
                            return self.db.profile.notifySelf
                        end,
                        set = function(info, value)
                            self.db.profile.notifySelf = value
                        end,
                    },
                    notifyCollision = {
                        order = 5,
                        type = "toggle",
                        name = L["Duplicate Res Targets"],
                        desc = L["Toggle whether you want to whisper a resser who is ressing a\ntarget of another resser's spell.\nCould get very spammy.\nDefault off"],
                        get = function()
                            return self.db.profile.notifyCollision
                        end,
                        set = function(info, value)
                            self.db.profile.notifyCollision = value
                        end,
                    },
                },
            },
            keyBindingsTab = {
                name = L["key Bindings"],
                desc = L["Set the keybindings"],
                type = "group",
                order = 3,
                args = {
                    autoResKey = {
                        order = 1,
                        type = "keybinding",
                        name = L["Auto Res Key"],
                        desc = L["For ressing targets who have not released their ghosts\nDefault is *"],
                        get = function()
                            return self.db.profile.autoResKey
                        end,
                        set = function(info, value)
                            self.db.profile.autoResKey = value
                        end,
                    },
                    manualResKey = {
                        order = 2,
                        type = "keybinding",
                        name = L["Manual Target Key"],
                        desc = L["Gives you the pointer to click on corpses\nDefault is /"],
                        get = function()
                            return self.db.profile.manualResKey
                        end,
                        set  = function(info, value)
                            self.db.profile.manualResKey = value
                        end,
                    },
                },
            },
            creditsTab = {
                name = L["SmartRes2 Credits"],
                desc = L["About the author and SmartRes2"],
                type = "group",
                order = 4,
                args = {
                    creditsHeader1 = {
                        order = 1,
                        type = "header",
                        name = L["Credits"],
                    },
                    creditsDesc1 = {
                        order = 2,
                        type = "description",
                        name = L["Massive kudos to Maia, Kyahx, and Poull for the original SmartRes.\nSmartRes2 was largely possible because of\nDathRarhek's LibResComm-1.0 so a big thanks to him."],
                    },
                    creditsDesc2 = {
                        order = 3,
                        type = "description",
                        name = L["I would personally like to thank Jerry on the wowace forums for coding the new, smarter, resurrection function."],
                    },
                },
            },
        },
    }
    LibStub("LibAboutPanel").new("SmartRes2", "SmartRes2")
    
    local defaults = {
        profile = {
            scale = 1,
            locked = false,
            texture = "Blizzard",
            reverseGrowth = false,
            resBarX = 470,
            resBarY = 375,
            autoResKey = "*",
            manResKey = "/",
            notifySelf = true,
            notifyCollision = false,
            randMssgs = false,
            classColours = true,
            chatOutput = "none",
            resBarsIcon = true,
            randChatTbl = { -- this is here for eventual support for users to add or remove their own random messages
                [1] = L["% is bringing % back to life!"],
                [2] = L["Filthy peon! %s has to resurrect %s!"],
                [3] = L["% has to wake % from eternal slumber."],
                [4] = L["% is ending the dirt nap of %s."],
                [5] = L["No fallen heroes! %s needs %s to march forward to victory!"],
                [6] = L["% doesn't think %s is immortal, but after this res cast, it is close enough."],
                [7] = L["Sleeping on the job? % is disappointed in %."],
                [8] = L["%s knew %s couldn\'t stay out of the fire. *Sigh*"],
                [9] = L["Once again, %s pulls %s and their bacon out of the fire."],
                [10] = L["% thinks %s should work on their Dodge skill."],
                [11] = L["% refuses to accept blame for %s\'s death, but kindly undoes the damage."],
                [12] = L["%s prods %s with a stick. A-ha! % was only temporarily dead."],
                [13] = L["% is ressing %"],
                [14] = L["%s knows % is faking. It was only a flesh wound!"],
                [15] = L["Oh. My. God. %s has to breathe life back into %s AGAIN?!?"],
                [16] = L["%s knows that %s dying was just an excuse to see another silly random res message."],
                [17] = L["Think that was bad? % proudly shows %s the scar tissue caused by Ragnaros."],
                [18] = L["Just to be silly, % tickles %s until they get back up."],
                [19] = L["FOR THE HORDE! FOR THE ALLIANCE! %s thinks %s should be more concerned about yelling FOR THE LICH KING! and prevents that from happening."],
                [20] = L["And you thought the Forsaken looked bad. In about 10 seconds, %s knows %s will want a comb, some soap, and a mirror."],
                [21] = L["Somewhere, the Lich King is laughing at %s, because he knows %s will just die again eventually. More meat for the grinder!!"],
                [22] = L["% doesn't want the Lich King to get another soldier, so is bringing %s back to life."],
                [23] = L["%s wonders about these stupid res messages. %s should just be happy to be alive."],
                [24] = L["%s prays over the corpse of %s, and a miracle happens!"],
                [25] = L["In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %s is making sure %s\'s death isn\'t permanent."],
                [26] = L["% performs a series of lewd acts on %\'s still warm corpse. Ew."],
            },
        },
    }

    -- the following borrowed from the original SmartRes by Maia, Kyahx, Poull, and Myrroddin (/w Zidomo)    
    -- prepare spells
    self.resSpells = { -- getting the spell names
        Priest = GetSpellInfo(2006), -- Resurrection
        Shaman = GetSpellInfo(2008), -- Ancestral Spirit
        Druid = GetSpellInfo(50769), -- Revive
        Paladin = GetSpellInfo(7328) -- Redemption
    }    
    
    self.resSpellIcons = { -- need the icons too, for the res bars
        Priest = select (3, GetSpellInfo(2006)),
        Shaman = select (3, GetSpellInfo(2008)),
        Druid = select (3, GetSpellInfo(50769)),
        Paladin = select (3, GetSpellInfo(7328))
    }  
    self.playerClass = select (2, UnitClass("player"))  -- what class is the user?
    self.playerSpell = self.resSpells[self.playerClass] -- only has data if the player can cast a res spell
    
    -- create a secure button for ressing
    local resButton = CreateFrame("button", "SmartRes2Button", UIParent, "SecureActionButtonTemplate")
	resButton:SetAttribute("type", "spell");
	resButton:SetAttribute("PreClick", function() self:Resurrect() end);
	resButton:SetAttribute("unit", bestUnitId);
    self.resButton = resButton
    -- end of borrowed code
    
    -- register saved variables with AceDB
    self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, "Default")
    local db = self.db.profile
    
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileDeleted", "OnProfileChanged")
    
    -- Register your options with AceConfigRegistry
    LibStub("AceConfig-Registry-3.0"):RegisterOptionsTable("SmartRes2", options)
    
     -- Add your options to the Blizz options window using AceConfigDialog
    self.optionsFrame = LibStub("AceConfig-Dialog-3.0"):AddToBlizOptions("SmartRes2", (L["SmartRes2"]))
    
    -- create chat commands
    self:RegisterChatCommand("sr", function() InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) end)
    self:RegisterChatCommand("smartres", function() InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) end)
    
    self.Resser = {}
    self.Ressed = {}
    
    self.res_bars = self:NewBarGroup("SmartRes2", Bars.RIGHT_TO_LEFT)
    self.res_bars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.resBarsX, db.resBarsY)
    self.res_bars:SetScale(db.scale)
    self.res_bars:ReverseGrowth(db.reverseGrowth)
    if db.locked then
        self.res_bars:HideAnchor()
    else
        self.res_bars:ShowAnchor()
    end
    
    if DataBroker then
        local launcher = DataBroker:NewDataObject("SmartRes2", {
        type = "launcher",
        icon = icon = self.resSpellIcons[self.playerClass] or self.resSpellIcons.Priest, -- "Interface\\Icons\\Spell_Holy_Resurrection", icon changes depending on class, or defaults to Resurrection, if not a resser
        OnClick = function(clickedframe, button)
            if button == "LeftButton" then
                self.res_bars:ToggleAnchor()
            elseif button == "RightButton" then
                InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
            end
        end,
        OnTooltipShow = function(self)
            GameTooltip:AddLine(L["SmartRes2 "]..GetAddOnMetadata("SmartRes2", "version"), HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
            GameTooltip:AddLine(L["Left click to lock/unlock the res bars. Right click for configuration."], NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
            GameTooltip:Show()
        end,
        })
    end
end

function Addon:OnEnable()
    -- called when SmartRes2 is enabled
    --@alpha@
    self:Print("This is the OnEnable of SmartRes2")
    --@end-alpha@
    
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    if (event == "PLAYER_REGEN_ENABLED") and not (UnitAffectingCombat("player")) then
        ResComm.RegisterCallback(self, "ResComm_ResStart");
        ResComm.RegisterCallback(self, "ResComm_Ressed");
        ResComm.RegisterCallback(self, "ResComm_ResEnd");
        if self.playerSpell then
            self:Bindvalues()
        end
        self.res_bars.RegisterCallback(self, "AnchorMoved", "ResAnchorMoved")
    end
end

function Addon:OnDisable()
    -- called when SmartRes2 is disabled
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    if (event == "PLAYER_REGEN_DISABLED") then
        ResComm.UnRegisterCallback(self, "ResComm_ResStart");
        ResComm.UnRegisterCallback(self, "ResComm_Ressed");
        ResComm.UnRegisterCallback(self, "ResComm_ResEnd");
        if self.playerSpell then
            self:UnBindvalues()
        end
    end
end

--[[ we are opening straight to the Blizzard Interface Options Panel, so no need to have slash handlers
function Addon:ChatCommand(input)
    if not input or input:trim() == "" then -- might eventually just open to the Interface Options Frame no matter what input the user types
        LibStub("AceConfigDialog-3.0"):Open("options")
    else
        LibStub("AceConfigCmd-3.0").HandleCommand(SmartRes2, "sr", "smartres", input) -- but for now, have the command line processor commands as well
    end
end
]]--

-- events, yay!
function Addon:ResAnchorMoved(_, _, x, y)
    db.resBarsX, db.resBarsY = x, y
end

function Addon:ResComm_ResStart(event, resser, endTime, targetName)
    if self.Resser[resser] then return end;    
    self.Resser[resser] = {
                            endTime = endTime,
                            target = targetName
                        }    
    self:StartBars(resser);
    self:UpdateResColours();
    
    local isSame = UnitIsUnit(self.Resser[resser], "player")
    if isSame == 1 then -- make sure only the player is sending messages
        if not (db.chatOutput == "none") then -- if it is "none" then don't send any chat messages
            if (db.randMssgs) then
                SendChatMessage(math.random(#defaults.randChatTbl), db.chatOutput, nil, nil):format(self.Resser[resser], self.Resser[target])
            else
                SendChatMessage(L["% is ressing %"], db.chatOutput, nil, nil):format(self.Resser[resser], self.Resser[target])
            end            
        end        
        if (db.notifySelf) then
            self:Print(L["You are ressing %s"]):format(self.Resser[target])
        end
    end    
end

function Addon:ResComm_ResEnd(event, ressed)
    -- did the cast fail or complete?
    if not self.Resser[resser] then return end;
    
    self:StopBars(resser)
    self.Resser[resser] = nil;
    self:UpdateResColours();
end

function Addon:ResComm_Ressed(event, targetName)
    if not self.Ressed[ressed] or ((self.Ressed[ressed] + 120) < GetTime()) then
        self.Ressed[ressed] = GetTime();
    end
    
    self:UpdateResColours();
end

function Addon:UpdateResColours()
    local currentRes = {}
    local beingRessed = {}
    local duplicate = false;
    local alreadyRessed = false;
    
    for resserName, info in pairs(self.Resser) do
        tinsert(currentRes, info);
    end
    
    tsort(currentRes, function(a, b) return a.endTime < b.endTime end);
    
    for idx, info in pairs(currentRes) do
        duplicate = false;
        alreadyRessed = false;
        
        for i, ressed in pairs(beingRessed) do
            if (ressed = info.target) then
                r, g, b = unpack(colours.red)
                info.bar:SetBackgroundColor(r, g, b, 1)
                duplicate = true;
                break;
            end
        end
        
        for ressed, time in pairs(self.Ressed) do
            if (ressed == info.target) and (time + 120) > GetTime() then
                alreadyRessed = true;
                break;
            end
        end
        
        if not duplicate and not alreadyRessed then
            r,g,b = unpack(colours.green)
            info.bar:SetBackgroundColor(r,g,b,1)
           tinsert(beingRessed,info.target);
        end
        
        if duplicate and not alreadyRessed then
            if db.notifyCollision then
                SendChatMessage(L["SmartRes2 would like you to know that %s is already being ressed by %s. Please get SmartRes2 and use the auto res key to never see this whisper again."],..
                "whisper", nil, info):format(beingRessed.info.target, info)
            end
        end
    end
end

function Addon:StartTestBars()
    Addon:ResComm_Ressed(nil, L["Frankthetank"])
    Addon:ResComm_ResStart(nil, L["Nursenancy"], GetTime() + 10, L["Frankthetank"])
    Addon:ResComm_ResStart(nil, L["Dummy"], GetTime() + 3, L["Timthewizard"])
end

function Addon:ClassColours(text, class)
    if class and hexcolors[class] then
		return format("|cff%s%s|r", hexcolors[class], text)
	else
		return text
	end
end

function Addon:StartBars(resser)
    local barMssg
    local icon
    
    if db.classColours then
        barMssg = self:ClassColours(resser, select (2, UnitClass(resser)))..
            L["is resurrecting "]..
            self:ClassColors(info.target, select(2, UnitClass(info.target)))
    else
        barMssg = (L["%s is resurrecting %s"]):format(resser, info.target)
    end
    
    if db.resBarsIcon then
        icon = self.resSpellIcons[resser]
    else
        icon = nil
    end
    
    local id = "SmartRes2"..resser;
    local info = self.Resser[resser];
    local time = info.endTime - GetTime();
    
    local bar = self.res_bars:NewTimerBar(id, barMssg, time, nil, icon, 0)
    r, g, b = unpack(colours.green)
    
    bar:SetColorAt(0, 0, 0, 0, 1, 0)
    
    self.Resser[resser].bar = bar;
end

function Addon:StopBars(resser) -- have to test this function to see if I got it correct
    if not self.Resser[resser] then return end;
    
    self.Resser[resser].bar:Fade(0.5) -- half second fade
end

-- set and unset keybindings
function Addon:BindKeys()
    if self.playerSpell then -- only bind values if the player can cast a res spell
        SetOverrideBindingClick(self.resButton, false, db.autoResKey "SmartRes2Button")
        SetOverrideBindingSpell(self.resButton, false, db.manResKey, self.playerSpell)
    end
end

function Addon:UnBindKeys()
    if self.playerSpell then -- again, unbind values only if the player can cast a res spell
        ClearOverrideBindings(self.ResButton)
    end
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
	WARRIOR = 5,
}

-- The following compliments and kudos to Jerry on the wowace forums
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
	-- if UnitIsVisable(unitId) then return bestUnitId end
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

function Addon:Resurrection()
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
-- The previous compliments and kudos to Jerry on the wowace forums