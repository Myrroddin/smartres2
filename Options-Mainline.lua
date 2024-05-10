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

function addon:GetOptions()
    db = self.db
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
                        get = function() return db.profile.enabled end,
                        set = function(_, value)
                            db.profile.enabled = value
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
                        name = L["Status Messages"],
                        desc = L["Toggle feedback for keybinding changes."],
                        get = function() return db.profile.enableFeedback end,
                        set = function(_, value) db.profile.enableFeedback = value end
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
                        get = function() return db.profile.minimap.hide end,
                        set = function(_, value)
                            db.profile.minimap.hide = value
                            if value then
                                DBI:Hide("SmartRes2")
                            else
                                DBI:Show("SmartRes2")
                            end
                            DBI:Refresh("SmartRes2", db.profile.minimap)
                        end
                    },
                    addonCompartment = {
                        order = 20,
                        type = "toggle",
                        disabled = function() return not DBI:IsButtonCompartmentAvailable() end,
                        hidden = function() return not DBI:IsButtonCompartmentAvailable() end,
                        name = L["AddOn Compartment"],
                        desc = L["Toggle showing the minimap icon in the addon compartment."],
                        get = function() return db.profile.minimap.showInCompartment end,
                        set = function(_, value)
                            db.profile.minimap.showInCompartment = value
                            local icon = db.profile.useClassIconForBroker and self:GetIconForBrokerDisplay() or default_icon
                            if DBI:IsButtonCompartmentAvailable() then
                                if value then
                                    DBI:AddButtonToCompartment("SmartRes2", icon)
                                else
                                    DBI:RemoveButtonFromCompartment("SmartRes2")
                                end
                            end
                            DBI:Refresh("SmartRes2", db.profile.minimap)
                        end
                    },
                    lock = {
                        order = 30,
                        type = "toggle",
                        name = L["Lock Button"],
                        desc = L["Lock minimap button and prevent dragging."],
                        get = function() return db.profile.minimap.lock end,
                        set = function(_, value)
                            db.profile.minimap.lock = value
                            if value then
                                DBI:Lock("SmartRes2")
                            else
                                DBI:Unlock("SmartRes2")
                            end
                            if db.profile.lockOnDegree then
                                db.profile.minimap.minimapPos = addon:Round(db.profile.minimap.minimapPos, 0)
                            end
                            -- constrain the button to 360° (0-359)
                            if db.profile.minimap.minimapPos <= 0 then value = 0 end
                            if db.profile.minimap.minimapPos >= 359 then value = 359 end
                            DBI:SetButtonToPosition("SmartRes2", db.profile.minimap.minimapPos)
                            DBI:Refresh("SmartRes2", db.profile.minimap)
                        end
                    },
                    lockOnDegree = {
                        order = 40,
                        type = "toggle",
                        name = L["Precise Lock"],
                        desc = L["When locked, the button will adjust to an exact degree between 0-359°."],
                        get = function() return db.profile.lockOnDegree end,
                        set = function(_, value)
                            db.profile.lockOnDegree = value
                            if value then
                                db.profile.minimap.minimapPos = addon:Round(db.profile.minimap.minimapPos, 0)
                            end
                            -- constrain the button to 360° (0-359)
                            if db.profile.minimap.minimapPos <= 0 then db.profile.minimap.minimapPos =  0 end
                            if db.profile.minimap.minimapPos >= 359 then db.profile.minimap.minimapPos = 359 end
                            DBI:SetButtonToPosition("SmartRes2", db.profile.minimap.minimapPos)
                            DBI:Refresh("SmartRes2", db.profile.minimap)
                        end
                    },
                    useClassIconForBroker = {
                        order = 50,
                        type = "toggle",
                        name = L["Class Button"],
                        desc = L["Use your class spell icon (defaults to Priest's Resurrection)."],
                        get = function() return db.profile.useClassIconForBroker end,
                        set = function(_, value)
                            db.profile.useClassIconForBroker = value
                            local button = DBI:GetMinimapButton("SmartRes2")
                            local iconTexture = (value and self:GetIconForBrokerDisplay(player_class)) or default_icon
                            button.icon:SetTexture(iconTexture)
                        end
                    },
                    minimapPos = {
                        order = 60,
                        type = "range",
                        name = L["Rotate Button"],
                        desc = L["Rotate the icon around the minimap."],
                        get = function() return db.profile.minimap.minimapPos end,
                        set = function(_, value)
                            if db.profile.lockOnDegree then
                                value = addon:Round(value, 0)
                            end
                            -- constrain the button to 360° (0-359)
                            if value <= 0 then value =  0 end
                            if value >= 359 then value = 359 end
                            db.profile.minimap.minimapPos = value
                            DBI:SetButtonToPosition("SmartRes2", db.profile.minimap.minimapPos)
                            DBI:Refresh("SmartRes2", db.profile.minimap)
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