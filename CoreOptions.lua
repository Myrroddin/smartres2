-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- get addon reference and localization
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- additonal library
local DBI = LibStub("LibDBIcon-1.0")

-- variables that are file scope
local _, db, player_class, default_icon, isMainline
player_class = UnitClassBase("player")
default_icon = "Interface\\Icons\\Spell_holy_resurrection"
isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

function addon:GetOptions()
    db = self.db.profile
    -- create the user options
    local options = {
        order = 10,
        type = "group",
        name = "",
        handler = addon,
        childGroups = "tab",
        args = {
            title = {
                order = 10,
                type = "header",
                name = "SmartRes2 " .. addon.version
            },
            addonDescription = {
                order = 20,
                type = "description",
                name = L["Notes"],
                fontSize = "large",
                image = default_icon,
                imageWidth = 32,
                imageHeight = 32
            },
            breakLine = {
                order = 30,
                type = "header",
                name = ""
            },
            generalOptions = {
                order = 40,
                type = "group",
                name = COMPACT_UNIT_FRAME_PROFILE_SUBTYPE_ALL,
                args = {
                    enabled = {
                        order = 10,
                        type = "toggle",
                        name = ENABLE .. " " .. JUST_OR .. " " .. DISABLE,
                        desc = L["Toggle SmartRes2 and all modules on/off."],
                        get = function() return db.enabled end,
                        set = function(_, value)
                            db.enabled = value
                            if value then
                                addon:Enable()
                            else
                                addon:Disable()
                            end
                        end
                    },
                    feebackMessages = {
                        order = 20,
                        type = "toggle",
                        name = L["Status Messages"],
                        desc = L["Toggle feedback for keybinding changes."],
                        get = function() return db.enableFeedback end,
                        set = function(_, value)
                            db.enableFeedback = value
                        end
                    },
                    singleKey = {
                        order = 30,
                        type = "keybinding",
                        name = L["Single Target Res Key"],
                        desc = L["Intelligently casts your single target res spell."],
                        get = function() return db.char.resKey end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            db.char.resKey = value
                            self:BindResKeys()
                        end
                    },
                    manualResKey = {
                        order = 40,
                        type = "keybinding",
                        name = L["Manual Target Res"],
                        desc = L["Cast on corpses or unit frames."],
                        get = function() return db.char.manualResKey end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            db.char.manualResKey = value
                            self:BindResKeys()
                        end
                    },
                    massKey = {
                        order = 50,
                        type = "keybinding",
                        disabled = function() return not isMainline end,
                        hidden = function() return not isMainline end,
                        name = L["Mass Res Key"],
                        desc = L["Intelligently casts your mass res spell."],
                        get = function() return db.char.massResKey end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            db.char.massResKey = value
                            self:BindMassResKey()
                        end
                    }
                }
            },
            minimap = {
                order = 50,
                type = "group",
                name = MINIMAP_LABEL,
                args = {
                    hide = {
                        order = 10,
                        type = "toggle",
                        name = L["Minimap Button"],
                        desc = L["Hide the minimap icon."],
                        get = function() return db.minimap.hide end,
                        set = function(_, value)
                            db.minimap.hide = value
                            if value then
                                DBI:Hide("SmartRes2")
                            else
                                DBI:Show("SmartRes2")
                            end
                        end
                    },
                    addonCompartment = {
                        order = 20,
                        type = "toggle",
                        disabled = function() return not isMainline end,
                        hidden = function() return not isMainline end,
                        name = L["AddOn Compartment"],
                        desc = L["Toggle showing the minimap icon in the addon compartment."],
                        get = function() return db.minimap.showInCompartment end,
                        set = function(_, value)
                            db.minimap.showInCompartment = value
                            local icon = db.useClassIconForBroker and self:GetIconForBrokerDisplay() or default_icon
                            if value then
                                DBI:AddButtonToCompartment("SmartRes2", icon)
                            else
                                DBI:RemoveButtonFromCompartment("SmartRes2")
                            end
                        end
                    },
                    lock = {
                        order = 30,
                        type = "toggle",
                        name = L["Lock Button"],
                        desc = L["Lock minimap button and prevent moving."],
                        get = function() return db.minimap.lock end,
                        set = function(_, value)
                            db.minimap.lock = value
                            if value then
                                DBI:Lock("SmartRes2")
                            else
                                DBI:Unlock("SmartRes2")
                            end
                        end
                    },
                    useClassIconForBroker = {
                        order = 40,
                        type = "toggle",
                        name = L["Class Button"],
                        desc = L["Use your class spell icon for the Broker display (defaults to Priest's Resurrection)."],
                        get = function() return db.useClassIconForBroker end,
                        set = function(_, value)
                            db.useClassIconForBroker = value
                            DBI:IconCallback(_, "SmartRes2", "icon", (value and self:GetIconForBrokerDisplay(player_class)) or default_icon)
                        end
                    }
                }
            }
        }
    }
    -- send the options table back to SmartRes2.lua
    return options
end