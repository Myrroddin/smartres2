-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- get addon reference and localization
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- additonal library
local DBI = LibStub("LibDBIcon-1.0")

-- variables that are file scope
local _, db, player_class, default_icon
player_class = UnitClassBase("player")
default_icon = "Interface\\Icons\\Spell_holy_resurrection"

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
                image = function() return (db.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon end,
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
                                addon:OnEnable()
                            else
                                addon:OnDisable()
                            end
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
                    lock = {
                        order = 20,
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
                        order = 30,
                        type = "toggle",
                        name = L["Class Button"],
                        desc = L["Use your class spell icon for the Broker display (defaults to Priest's Resurrection)."],
                        get = function() return db.useClassIconForBroker end,
                        set = function(_, value)
                            db.useClassIconForBroker = value
                            DBI:IconCallback(_, "SmartRes2", "icon", (value and self:GetIconForBrokerDisplay(player_class)) or default_icon)
                        end
                    },
                    resetButton = {
                        order = 60,
                        type = "execute",
                        name = L["Reset Button"],
                        desc = L["Reset the minimap button to defaults (position, visible, locked)."],
                        func = function()
                            local temp = self.db.profile
                            DBI:Refresh("SmartRes2", temp.minimap)
                            DBI:IconCallback(_, "SmartRes2", "icon", (temp.useClassIconForBroker and self:GetIconForBrokerDisplay(player_class)) or default_icon)
                        end
                    }
                }
            }
        }
    }
    -- send the options table back to SmartRes2.lua
    return options
end