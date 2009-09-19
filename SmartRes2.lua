-- SmartRes2
-- Author:  Myrroddin of Llane

-- load libraries & other stuff
SmartRes2 = LibStub("AceAddon-3.0"):NewAddon("SmartRes2", "AceConsole-3.0", "AceEvent-3.0")

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
    
function Addon:OnInitialize()
    -- called when SmartRes2 is loaded
    -- the following borrowed from the original SmartRes by Maia, Kyahx, Poull, and Myrroddin (/w Zidomo)
    self.Ressing = {} -- who is being ressed
    self.Ressed = {} -- who has already been ressed
    self.Resser = {} -- who is casting res spells
    
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
    self.playerClass = select(2, UnitClass("player"))  -- what class is the user?
    self.playerSpell = self.resSpells[self.playerClass] -- only has data if the player can cast a res spell
    
    -- create a secure button for ressing
    local resButton = CreateFrame("button", "SmartRes2Button", UIParent, "SecureActionButtonTemplate")
    resButton:SetAttribute("type", "spell");
    resButton:SetAttribute("PreClick", function() self:Resurrect() end);
    resButton:SetAttribute("unit", bestUnitId);
    self.resButton = resButton
    -- end of borrowed code
    
    self.db = LibStub("AceDB-3.0"):New("SmartRes2DB", defaults, "Default")
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    db = self.db.profile
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("SmartRes2", options)
    self.OptionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SmartRes2", "SmartRes2")
    self.RegisterChatCommand("sr", "ChatCommand")
    self.RegisterChatCommand("sr2", "ChatCommand")
    self.RegisterChatCommand("smartres", "ChatCommand")
    self.RegisterChatCommand("smartres2", "ChatCommand")
    self:SR2_Options() -- see SR2Options.lua
    
    function Addon:SR2_Enabled(event, ...)
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

    function Addon:SR2_Disabled(event, ...)
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
end

function Addon:OnEnable()
    -- called when SmartRes2 is enabled
    self:SR2_Enabled()
end

function Addon:OnDisable()
    -- called when SmartRes2 is disabled
    self:SR2_Disabled()
end

function Addon:ChatCommand(input)
    if not input or input:trim() == "" then -- might eventually just open to the Interface Options Frame no matter what input the user types
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
    else
        LibStub("AceConfigCmd-3.0").HandleCommand(SmartRes2, "sr", "sr2", "smartres", "smartres2", input) -- but for now, have the command line processor commands as well
    end
end

function Addon:ResComm_ResStart(event, resser, endTime, targetName)
    if self.Resser[resser] then return end;
    
    self.Resser[resser] = {
                            endTime = endTime,
                            targetName = targetName
                        }
    
    self:StartBars(resser)        
end

function Addon:ResComm_ResEnd(event, resser, targetName)
    -- did the cast fail or complete?
    if not self.Resser[resser] then return end;
    
    self:StopBars(resser)
    self.Resser[resser] = nil;
end

function Addon:ResComm_Ressed(event, targetName)
    if not self.Resser[resser] then return end;
    
    self:StopBars(resser)
    self.Resser[resser] = nil;
end

function Addon:StartBars(resser, targetName)
    local resserClass = select (2, UnitClass(self.Resser[resser]))
    local targetClass = select (2, UnitClass(self.Resser[targetName]))
    local resserColor = RAID_CLASS_COLORS[resserClass]
    local targetColor = RAID_CLASS_COLORS[targetClass]
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