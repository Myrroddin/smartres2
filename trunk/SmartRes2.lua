-- SmartRes2
-- Author:  Myrroddin of Llane

-- load libraries & other stuff
local SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2", true)
local ResComm = LibStub("LibResComm-1.0")
local Media = Libstub:GetLibrary("LibSharedMedia-3.0")
local Candy = LibStub("LibCandyBar-3.0")

local Addon = SmartRes2

-- register the res bar textures with LibSharedMedia-3.0
Media:Register("statusbar", "Blizzard", [[Interface\TargetingFrame\UI-StatusBar]])
Media:Register("statusbar", "Banto", [[Interface\AddOns\SmartRes2\Textures\banto.tga]])
Media:Register("statusbar", "Charcoal", [[Interface\AddOns\SmartRes2\Textures\Charcoal.tga]])
Media:Register("statusbar", "Cilo", [[Interface\AddOns\SmartRes2\Textures\cilo.tga]])
Media:Register("statusbar", "Glaze", [[Interface\AddOns\SmartRes2\Textures\glaze.tga]])
Media:Register("statusbar", "Perl", [[Interface\AddOns\SmartRes2\Textures\perl.tga]])
Media:Register("statusbar", "Smooth", [[Interface\AddOns\SmartRes2\Textures\smooth.tga]])

local colours = {
    green = {0, 1, 0},
    red = {1, 0, 0}
}
       
function Addon:OnInitialize()
    -- called when SmartRes2 is loaded
    
    local options = {
        name = L["SmartRes2"],
        handler = "SmartRes2",
        type = "TabGroup",
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
                            return SmartRes2.db.profile.barsAnchor
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.barsAnchor = value
                        end,
                    },
                    barsOptionsHeader2 = {
                        order = 3,
                        type = "description",
                        name = "",
                    },
                    resBarsIcon = {
                        order = 4,
                        type = "CheckBox",
                        name = L["Res Bars Icon"],
                        desc = L["Show or hide the icon for res spells"],
                        get = function()
                            return SmartRes2.db.profile.resBarsIcon
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.resBarsIcon = value
                        end,
                    },
                    classColours = {
                        order = 5,
                        type = "CheckBox",
                        name = L["Class Colours"],
                        desc = L["Use class colours for the target on the res bars"],
                        get = function()
                            return SmartRes2.db.profile.classColours
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.classColours = value
                        end,
                    },
                    resBarsTexture = {
                        order = 6,
                        type = "select",
                        dialogControl = "LSM30_StatusBar",
                        name = L["Res Bars Texture"],
                        desc = L["Select the texture for the res bars"],
                        values = LSM:HashTable(type),
                        get = function()
                            return self.db.proflile.resBarsTexture
                        end,
                        set = function(self, key)
                            self.db.profile.resBarsTexture = key
                        end,
                    },
                    resBarsBGColour = {
                        order = 7,
                        type = "select",
                        dialogControl = "LSM30_Background",
                        name = L["Res Bars Background Colour"],
                        desc = L["Set the background colour for the res bars"],
                        values = LSM:HashTable(type),
                        get = function()
                            return self.db.profile.resBarsBGColour
                        end,
                        set = function(self, key)
                            self.db.profile.resBarsBGColour = key
                        end,
                    },
                    resBarsBorder = {
                        order = 8,
                        type = select,
                        dialogControl = "LSM30_Border",
                        name = L["Res Bars Border"],
                        desc = L["Set the border for the res bars"],
                        values = LSM:HashTable(type),
                        get = function()
                            return self.db.profile.resBarsBorder
                        end,
                        set = function(self, key)
                            self.db.profile.resbarsBorder = key
                        end,
                    },
                    resBarsColour = {
                        order = 9,
                        type = "colorPicker",
                        name = L["Res Bars Colour"],
                        desc = L["Pick the colour for non-collision (not a duplicate) res bar"],
                        get = function()
                            return SmartRes2.db.profile.resBarsColour
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.resBarsColour = value
                        end,
                    },
                    collisionBarsColour = {
                        order = 10,
                        type = "colorPicker",
                        name = L["Duplicate Res Bars Colour"],
                        desc = L["Pick the colour for collision (duplicate) res bars"],
                        get = function()
                            return SmartRes2.db.profile.collisionBarsColour
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.collisionBarsColour = value
                        end,
                    },
                    resBarsTestBars = {
                        order = 11,
                        type = "toggle",
                        name = L["Test Bars"],
                        desc = L["Show the test bars"],
                        get = function()
                            return SmartRes2.db.profile.resBarsTestBars                  
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.resBarsTestBars = value
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
                        type = "CheckBox",
                        name = L["Random Res Messages"],
                        desc = L["Turn random res messages on or keep the same message.\nDefault is off"],
                        get = function()
                            return SmartRes2.db.profile.randMssgs
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.randMssgs = value
                        end,
                    },
                    chatOutput = {
                        order = 3,
                        type = "dropdown",
                        name = L["Chat Output Type"],
                        desc = L["Where to print the res message. Raid, Party, Say, Yell, Guild, or None.\nDefault is None"],
                        values = {
                            party = L["PARTY"],
                            raid = L["RAID"],
                            say = L["SAY"],
                            yell = L["YELL"],
                            guild = L["GUILD"],
                            none = L["none"],
                        },                        
                        get = function()
                            return SmartRes2.db.profile.chatOutput
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.chatOutput = value
                        end,
                    },
                    notifySelf = {
                        order = 4,
                        type = "CheckBox",
                        name = L["Self Notification"],
                        desc = L["Prints a message to yourself whom you are ressing"],
                        get = function()
                            return SmartRes2.db.profile.notifySelf
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.notifySelf = value
                        end,
                    },
                    notifyCollision = {
                        order = 5,
                        type = "CheckBox",
                        name = L["Duplicate Res Targets"],
                        desc = L["Toggle whether you want to whisper a resser who is ressing a\ntarget of another resser's spell.\nCould get very spammy.\nDefault off"],
                        get = function()
                            return SmartRes2.db.profile.notifyCollision
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.notifyCollision = value
                        end,
                    },
                },
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
                        desc = L["For ressing targets who have not released their ghosts\nDefault is *"],
                        get = function()
                            return SmartRes2.db.profile.autoResKey
                        end,
                        set = function(info, value)
                            SmartRes2.db.profile.autoResKey = value
                        end,
                    },
                    manualResKey = {
                        order = 2,
                        type = "keybinding",
                        name = L["Manual Res Key"],
                        desc = L["Gives you the pointer to click on corpses\nDefault is /"],
                        get = function()
                            return SmartRes2.db.profile.manualResKey
                        end,
                        set  = function(info, value)
                            SmartRes2.db.profile.manualResKey = value
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
                        name = L["I would personally like to thank Jerry on the wowace.com forums for coding the new, smarter, resurrection function."],
                    },
                },
            },
        },
    }
    
    local defaults = {
        profile = {
            barsAnchor = true,
            resBarsIcon = true,
            randMssgs = false,
            chatOutput = "none",
            notifySelf = false,
            notifyCollision = false,
            classColours = true,
            autoResKey = "*",
            manualResKey = "/",
            ClampToScreen = true,
        }
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
        Priest = select (3, GetSpellInfo(2008)),
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
    self.optionsFrame = LibStub("AceConfig-Dialog-3.0"):AddToBlizOptions("SmartRes2", "SmartRes2")
    
    -- create chat commands
    self:RegisterChatCommand("sr", function() InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) end)
    self:RegisterChatCommand("smartres", function() InterfaceOptionsFrame_OpenToCategory(self.optionsFrame) end)
    
    self.Resser = {}
    self.Ressed = {}    
end

function Addon:OnEnable()
    -- called when SmartRes2 is enabled
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
        if event == "PLAYER_REGEN_ENABLED" then
            ResComm.RegisterCallback(self, "ResComm_ResStart");
            ResComm.RegisterCallback(self, "ResComm_Ressed");
            ResComm.RegisterCallback(self, "ResComm_ResEnd");
            if self.playerSpell then
                self:BindKeys()
            end
        end
end

function Addon:OnDisable()
    -- called when SmartRes2 is disabled
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
        if event == "PLAYER_REGEN_DISABLED" then
            ResComm.UnRegisterCallback(self, "ResComm_ResStart");
            ResComm.UnRegisterCallback(self, "ResComm_Ressed");
            ResComm.UnRegisterCallback(self, "ResComm_ResEnd");
            if self.playerSpell then
                self:UnBindKeys()
            end
        end
end

function Addon:ChatCommand(input)
    if not input or input:trim() == "" then -- might eventually just open to the Interface Options Frame no matter what input the user types
        LibStub("AceConfigDialog-3.0"):Open("options")
    else
        LibStub("AceConfigCmd-3.0").HandleCommand(SmartRes2, "sr", "smartres", input) -- but for now, have the command line processor commands as well
    end
end

function Addon:ResComm_ResStart(event, resser, endTime, targetName)
    if self.Resser[resser] then return end;
    
    self.Resser[resser] = {
                            endTime = endTime,
                            target = targetName
                        }
    
    self:StartBars(resser)
    self:UpdateResColours();
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

-- functions from events
function Addon:StartBars(resser)
    if not self.db.profile.SmartRes2 then return end
    if self.db.classColours then
        local rColour = RAID_CLASS_COLORS(self.Resser[resser])
        local tColour = RAID_CLASS_COLORS(self.Resser[targetName])
    end
    
    local info = self.Resser[resser];
    local barMssg = string.format(L["% is ressing %"], resser, targetName);
    local time = info.endTime - GetTime();
end

function Addon:StopBars(resser) -- have to test this function to see if I got it correct
    if not self.Resser[resser] then return end;
end

-- set and unset keybindings
function Addon:BindKeys()
    if self.playerSpell then -- only bind keys if the player can cast a res spell
        SetOverrideBindingClick(self.resButton, false, self.db.profile.autoResKey "SmartRes2Button")
        SetOverrideBindingSpell(self.resButton, false, self.db.profile.manResKey, self.playerSpell)
    end
end

function Addon:UnBindKeys()
    if self.playerSpell then -- again, unbind keys only if the player can cast a res spell
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