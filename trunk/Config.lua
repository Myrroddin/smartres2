-- borrowed from Mapster, written by Hendrik "Nevcairiel" Leppkes < h.leppkes@gmail.com >

-- upvalue globals ------------------------------------------------------------
local _G = getfenv(0)
local LibStub = _G.LibStub
local COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL = _G.COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL
local ENABLE = _G.ENABLE
local MINIMAP_LABEL = _G.MINIMAP_LABEL
local pairs = _G.pairs
local type = _G.type

local SmartRes2 = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local DBI = LibStub("LibDBIcon-1.0")
local LDS = LibStub("LibDualSpec-1.0")
local Dialog = LibStub("AceConfigDialog-3.0")
local Registry = LibStub("AceConfigRegistry-3.0")
local DBOptions = LibStub("AceDBOptions-3.0")
SmartRes2.L = L

-- get and set options --------------------------------------------------------
local optGetter, optSetter
do
    function optGetter(info)
        local key = info[#info]
        return SmartRes2.db.profile[key]
    end

    function optSetter(info, value)
	    local key = info[#info]
	    SmartRes2.db.profile[key] = value
	    SmartRes2:Refresh()
    end
end

-- fill in options data for core and modules ----------------------------------
local options, moduleOptions = nil, {}
local function getOptions()
    if not options then
        options = {
            type = "group",
            childGroups = "tab",
            name = "SmartRes2 ".. SmartRes2.version,
            arg = "SmartRes2",
            args = {
                general = {
                    order = 1,
                    type = "group",
                    childGroups = "tab",
                    name = COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL,
                    get = optGetter,
                    set = optSetter,
                    args = {
                        enableAddOn = {
                            order = 1,
                            type = "toggle",
                            name = ENABLE,
                            desc = L["Toggle SmartRes2 and all modules on/off."],
                            descStyle = "inline",
                            get = function() return SmartRes2.db.profile.enableAddOn end,
                            set = function(info, value)
                                SmartRes2.db.profile.enableAddOn = value
                                if value then
                                    SmartRes2:Enable()
                                else
                                    SmartRes2:Disable()
                                end
                            end
                        },
                        minimapStuff = {
                            type = "group", 
                            name = MINIMAP_LABEL,
                            order = 2,
                            args = {
                                button = {
                                    type = "toggle",
                                    order = 10,
                                    name = L["Minimap Button"],
                                    desc = L["Show or hide the minimap icon."],
                                    descStyle = "inline",
                                    get = function() return not SmartRes2.db.global.minimap.hide end,
                                    set = function(_, value)
                                        SmartRes2.db.global.minimap.hide = not value
                                        if value then
                                            DBI:Show("SmartRes2")
                                        else
                                            DBI:Hide("SmartRes2")
                                        end
                                    end
                                },
                                buttonLock = {
                                    type = "toggle",
                                    order = 20,
                                    name = L["Lock Button"],
                                    desc = L["Lock minimap button and prevent moving."],
                                    descStyle = "inline",
                                    get = function() return SmartRes2.db.global.minimap.lock end,
                                    set = function(_, value)
                                        SmartRes2.db.global.minimap.lock = value
                                        if value then
                                            DBI:Lock("SmartRes2")
                                        else
                                            DBI:Unlock("SmartRes2")
                                        end
                                    end
                                },
                                resetButton = {
                                    type = "execute",
                                    order = 30,
                                    name = L["Reset Button"],
                                    desc = L["Reset the minimap button to defaults (position, visible, locked)."],
                                    func = function()
                                        SmartRes2.db.global.minimap.hide = false
                                        SmartRes2.db.global.minimap.lock = true
                                        SmartRes2.db.global.minimap.minimapPos = 190
                                        SmartRes2.db.global.minimap.radius = 80
                                        DBI:Show("SmartRes2")
                                        DBI:Lock("SmartRes2")
                                    end
                                }
                            }
                        }    
                    }
                }
            }
        }
        -- module options
        for k, v in pairs(moduleOptions) do
			options.args[k] = (type(v) == "function") and v() or v
		end
    end
    return options
end

-- called from SmartRes2:OnInitialize() ---------------------------------------
function SmartRes2:SetupOptions()
    self.optionsFrames = {}

    -- setup options table
	Registry:RegisterOptionsTable("SmartRes2", getOptions)
	self.optionsFrames.SmartRes2 = Dialog:AddToBlizOptions("SmartRes2", nil, nil, "general")

    -- profiles
    self.optionsFrames.profiles = DBOptions:GetOptionsTable(self.db)
    self:RegisterModuleOptions("Profiles", self.optionsFrames.profiles, "Profiles")
    -- multi spec the options
	LDS:EnhanceDatabase(self.db, "SmartRes2")
    LDS:EnhanceOptions(self.optionsFrames.profiles, self.db)
end

-- modules call this to add their options to core options ---------------------
function SmartRes2:RegisterModuleOptions(name, optionTbl, displayName)
	moduleOptions[name] = optionTbl
	self.optionsFrames[name] = Dialog:AddToBlizOptions("SmartRes2", displayName, "SmartRes2", name)
end