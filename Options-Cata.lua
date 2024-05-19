-- File revision: @file-revision@
-- Project date: @project-date-iso@

-- get addon reference and localization
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- additonal library
local DBI = LibStub("LibDBIcon-1.0")

-- variables that are file scope
local db, player_class, default_icon
player_class = UnitClassBase("player")
local player_name = UnitName("player") .. " - " .. GetRealmName()
default_icon = "Interface\\Icons\\Spell_holy_resurrection"

function addon:GetOptions()
    -- we need character-baased key binds
	self.db.profile[player_name] = self.db.profile[player_name] or {}
    -- shortcut
    db = self.db.profile
    -- create the user options
    local options = {
        order = 10,
        type = "group",
        childGroups = "tab",
        name = "",
        handler = addon,
        args = {
            addonTitle = {
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
                    feedbackMessages = {
                        order = 20,
                        type = "toggle",
                        disabled = function() return not db.enabled end,
                        name = L["Status Messages"],
                        desc = L["Toggle feedback for keybinding changes."],
                        get = function() return db.enableFeedback end,
                        set = function(_, value) db.enableFeedback = value end
                    },
                    singleKey = {
                        order = 30,
                        type = "keybinding",
                        disabled = function() return not db.enabled end,
                        name = L["Single Target Res Key"],
                        desc = L["Intelligently casts your single target res spell."],
                        get = function() return db[player_name].resKey end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or ""
                            db[player_name].resKey = value
                            self:BindResKeys()
                        end
                    },
                    manualResKey = {
                        order = 40,
                        type = "keybinding",
                        disabled = function() return not db.enabled end,
                        name = L["Manual Target Res"],
                        desc = L["Cast on corpses or unit frames."],
                        get = function() return db[player_name].manualResKey end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or ""
                            db[player_name].manualResKey = value
                            self:BindResKeys()
                        end
                    },
                    massKey = {
                        order = 50,
                        type = "keybinding",
                        disabled = function() return not db.enabled end,
                        name = L["Mass Res Key"],
                        desc = L["Intelligently casts your mass res spell."],
                        get = function() return db[player_name].massResKey end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or ""
                           db[player_name].massResKey = value
                            self:BindMassResKey()
                        end
                    }
                }
            },
            minimap = {
                order = 50,
                type = "group",
                disabled = function() return not db.enabled end,
                name = MINIMAP_LABEL,
                args = {
                    hide = {
                        order = 10,
                        type = "toggle",
                        name = L["Hide the Minimap Button"],
                        get = function() return db.minimap.hide end,
                        set = function(_, value)
                            db.minimap.hide = value
                            if value then
                                DBI:Hide("SmartRes2")
                            else
                                DBI:Show("SmartRes2")
                            end
                            DBI:Refresh("SmartRes2", db.minimap)
                        end
                    },
                    lock = {
                        order = 20,
                        type = "toggle",
                        name = L["Lock Button"],
                        desc = L["Lock minimap button and prevent dragging."],
                        get = function() return db.minimap.lock end,
                        set = function(_, value)
                            db.minimap.lock = value
                            if value then
                                DBI:Lock("SmartRes2")
                            else
                                DBI:Unlock("SmartRes2")
                            end
                            if db.minimap.lockOnDegree then
                                db.minimap.minimapPos = addon:Round(db.minimap.minimapPos, 0)
                            end
                            -- constrain the button to 360° (0-359)
                            if db.minimap.minimapPos <= 0 then value = 0 end
                            if db.minimap.minimapPos >= 359 then value = 359 end
                            DBI:SetButtonToPosition("SmartRes2", db.minimap.minimapPos)
                            DBI:Refresh("SmartRes2", db.minimap)
                        end
                    },
                    lockOnDegree = {
                        order = 30,
                        type = "toggle",
                        name = L["Precise Lock"],
                        desc = L["When locked, the button will adjust to an exact degree between 0-359°."],
                        get = function() return db.minimap.lockOnDegree end,
                        set = function(_, value)
                            db.minimap.lockOnDegree = value
                            if value then
                                db.minimap.minimapPos = addon:Round(db.minimap.minimapPos, 0)
                            end
                            -- constrain the button to 360° (0-359)
                            if db.minimap.minimapPos <= 0 then db.minimap.minimapPos =  0 end
                            if db.minimap.minimapPos >= 359 then db.minimap.minimapPos = 359 end
                            DBI:SetButtonToPosition("SmartRes2", db.minimap.minimapPos)
                            DBI:Refresh("SmartRes2", db.minimap)
                        end
                    },
                    useClassIconForBroker = {
                        order = 40,
                        type = "toggle",
                        name = L["Class Button"],
                        desc = L["Use your class spell icon (defaults to Priest's Resurrection)."],
                        get = function() return db.minimap.useClassIconForBroker end,
                        set = function(_, value)
                            db.minimap.useClassIconForBroker = value
                            local button = DBI:GetMinimapButton("SmartRes2")
                            local iconTexture = (value and self:GetIconForBrokerDisplay(player_class)) or default_icon
                            button.icon:SetTexture(iconTexture)
                        end
                    },
                    minimapPos = {
                        order = 50,
                        type = "range",
                        name = L["Rotate Button"],
                        desc = L["Rotate the icon around the minimap."],
                        get = function() return db.minimap.minimapPos end,
                        set = function(_, value)
                            if db.minimap.lockOnDegree then
                                value = addon:Round(value, 0)
                            end
                            -- constrain the button to 360° (0-359)
                            if value <= 0 then value =  0 end
                            if value >= 359 then value = 359 end
                            db.minimap.minimapPos = value
                            DBI:SetButtonToPosition("SmartRes2", db.minimap.minimapPos)
                            DBI:Refresh("SmartRes2", db.minimap)
                        end,
                        min = 0,
                        max = 359,
                        step = 1,
                        bigStep = 15
                    }
                }
            }
        }
    }
    -- send the options table back to SmartRes2.lua
    return options
end