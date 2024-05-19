local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Chat", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

local function ChatTypes()
    local chatTypes = {
        ["group"] = CHANNEL_CATEGORY_GROUP,
        ["guild"] = CHAT_MSG_GUILD,
        ["none"] = NONE,
        ["party"] = CHAT_MSG_PARTY,
        ["raid"] = CHAT_MSG_RAID,
        ["say"] = CHAT_MSG_SAY,
        ["whisper"] = CHAT_MSG_WHISPER_INFORM,
        ["yell"] = CHAT_MSG_YELL,
    }
    return chatTypes
end

function module:GetOptions()
    self.db = addon.db:GetNamespace(module:GetName())
    local db = self.db.profile
    local options = {
        type = "group",
        childGroups = "tab",
        name = CHAT_OPTIONS_LABEL,
        args = {
            miscellaneous = {
                order = 10,
                type = "group",
                name = MISCELLANEOUS,
                args = {
                    enabled = {
                        order = 10,
                        type = "toggle",
                        name = ENABLE .. " " .. JUST_OR .. " " .. DISABLE,
                        desc = L["Toggle module on/off."],
                        get = function() return db.enabled end,
                        set = function(_, value)
                            db.enabled = value
                            if value then
                                addon:EnableModule(module:GetName())
                            else
                                addon:DisableModule(module:GetName())
                            end
                        end
                    },
                    notifySelf = {
                        order = 20,
                        type = "toggle",
                        disabled = function() return not db.enabled end,
                        name = L["Notify Self"],
                        desc = L["Tell yourself who you are ressing."],
                        get = function() return db.notifySelf end,
                        set = function(_, value) db.notifySelf = value end
                    },
                    notifyCollision = {
                        order = 30,
                        type = "select",
                        disabled = function() return not db.enabled end,
                        style = "dropdown",
                        name = L["Inform Colliders"],
                        desc = L["Tell other players their spells will not finish first."],
                        get = function() return db.notifyCollision end,
                        set = function(_, value) db.notifyCollision = value end,
                        values = function() return ChatTypes() end
                    }
                }
            },
            singleRes = {
                order = 20,
                type = "group",
                disabled = function() return not db.enabled end,
                name = L["Single Res Options"],
                args = {
                    overrideSingleResMessage = {
                        order = 10,
                        type = "input",
                        name = L["Override Message"],
                        desc = L["Overrides random single res messages."],
                        width = "full",
                        get = function() return db.overrideSingleResMessage end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            db.overrideSingleResMessage = value
                        end,
                        usage = L["Example: Hey %s, I am resurrecting you!"],
                        validate = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            if value and not strmatch(value, "%%s") then
                                return (L["You must include %s somewhere in the string for the target's name."])
                            end
                            if value and value:len() >= 256 then
                                return (L["Message must be 255 characters or less. Currently %d characters."]):format(value:len())
                            end
                            return true
                        end
                    },
                    addSingleResMessageToRandomTable = {
                        order = 20,
                        type = "input",
                        name = L["Add To Random Messages"],
                        width = "full",
                        get = function() return nil end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            if value then
                                db.randomSingleMessages[value] = true
                                self.randomSingleMessages[value] = value
                            end
                        end,
                        usage = L["Example: Hey %s, I am resurrecting you!"],
                        validate = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            if value and not strmatch(value, "%%s") then
                                return (L["You must include %s somewhere in the string for the target's name."])
                            end
                            if value and value:len() >= 256 then
                                return (L["Message must be 255 characters or less. Currently %d characters."]):format(value:len())
                            end
                            if value and db.randomSingleMessages[value] ~= nil then
                                return (L["The string %s already exists and cannot be added again."]):format(value)
                            end
                            return true
                        end
                    },
                    enabledRandomSingleResMessages = {
                        order = 30,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Random Messages"],
                        desc = L["Toggle which random messages to use."],
                        width = "full",
                        get = function(_, key) return db.randomSingleMessages[key] end,
                        set = function(_, key, value)
                            db.randomSingleMessages[key] = value
                            if db.randomSingleMessages[key] then
                                self.randomSingleMessages[key] = key
                            else
                                self.randomSingleMessages[key] = nil
                            end
                        end,
                        values = function() return addon:TranslateTable(db.randomSingleMessages) end
                    },
                    deleteRandomSingleResMessages = {
                        order = 40,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Delete Random Res Messages"],
                        desc = L["Delete messages from the DB. Reset the profile to undo."],
                        width = "full",
                        get = function() return true end,
                        set = function(_, key)
							-- the only possible value (not used) for "value" is false (because get always returns true), so we don't bother checking it and remove the entry from the table
                            db.randomSingleMessages[key] = nil
                            self.randomSingleMessages[key] = nil
                        end,
                        values = function() return addon:TranslateTable(db.randomSingleMessages) end
                    },
                    chatChannel = {
                        order = 50,
                        type = "select",
                        style = "dropdown",
                        name = L["Chat Channel"],
                        desc = L["Output channel for single res messages."],
                        get = function() return db.singleResOutput end,
                        set = function(_, value) db.singleResOutput = value end,
                        values = function() return ChatTypes() end
                    }
                }
            },
            massRes = {
                order = 30,
                type = "group",
                disabled = function() return not db.enabled end,
                name = L["Mass Res Options"],
                args = {
                    overrideMassResMessage = {
                        order = 10,
                        type = "input",
                        name = L["Override Message"],
                        desc = L["Overrides random mass res messages."],
                        width = "full",
                        get = function() return db.overrideMassResMessage end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            db.overrideMassResMessage = value
                        end,
                        usage = L["Example: I am resurrecting everybody!"],
                        validate = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            if value and strmatch(value, "%%s") then
                                return (L["Do not include %s as there are no target names."])
                            end
                            if value and value:len() >= 256 then
                                return (L["Message must be 255 characters or less. Currently %d characters."]):format(value:len())
                            end
                            return true
                        end
                    },
                    addMassResMessageToTable = {
                        order = 20,
                        type = "input",
                        name = L["Add To Random Messages"],
                        width = "full",
                        get = function() return nil end,
                        set = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            if value then
                                db.randomMassMessages[value] = true
                                self.randomMassMessages[value] = value
                            end
                        end,
                        usage = L["Example: I am resurrecting everybody!"],
                        validate = function(_, value)
                            value =value:trim()
                            value = value:len() >= 1 and value or nil
                            if value and strmatch(value, "%%s") then
                                return (L["Do not include %s as there are no target names."])
                            end
                            if value and value:len() >= 256 then
                                return (L["Message must be 255 characters or less. Currently %d characters."]):format(value:len())
                            end
                            if value and db.randomMassMessages[value] ~= nil then
                                return (L["The string %s already exists and cannot be added again."]):format(value)
                            end
                            return true
                        end
                    },
                    enabledRandomMassResMessages = {
                        order = 30,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Random Messages"],
                        desc = L["Toggle which random messages to use."],
                        width = "full",
                        get = function(_, key) return db.randomMassMessages[key] end,
                        set = function(_, key, value)
                            db.randomMassMessages[key] = value
                            if db.randomMassMessages[key] then
                                self.randomMassMessages[key] = key
                            else
                                self.randomMassMessages[key] = nil
                            end
                        end,
                        values = function() return addon:TranslateTable(db.randomMassMessages) end
                    },
                    deleteRandomMassResMessages = {
                        order = 40,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Delete Random Res Messages"],
                        desc = L["Delete messages from the DB. Reset the profile to undo."],
                        width = "full",
                        get = function() return true end,
                        set = function(_, key)
							-- the only possible value (not used) for "value" is false (because get always returns true), so we don't bother checking it and remove the entry from the table
                            db.randomMassMessages[key] = nil
                            self.randomMassMessages[key] = nil
                        end,
                        values = function() return addon:TranslateTable(db.randomMassMessages) end
                    },
                    chatChannel = {
                        order = 50,
                        type = "select",
                        style = "dropdown",
                        name = L["Chat Channel"],
                        desc = L["Output channel for mass res messages."],
                        get = function() return db.massResOutput end,
                        set = function(_, value) db.massResOutput = value end,
                        values = function() return ChatTypes() end
                    }
                }
            }
        }
    }
    return options
end