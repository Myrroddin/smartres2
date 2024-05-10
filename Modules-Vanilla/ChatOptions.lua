local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Chat", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

local function ChatTypes()
    local chatTypes = {
        ["GROUP"] = CHANNEL_CATEGORY_GROUP,
        ["GUILD"] = CHAT_MSG_GUILD,
        ["0-NONE"] = NONE,
        ["PARTY"] = CHAT_MSG_PARTY,
        ["RAID"] = CHAT_MSG_RAID,
        ["SAY"] = CHAT_MSG_SAY,
        ["WHISPER"] = CHAT_MSG_WHISPER_INFORM,
        ["YELL"] = CHAT_MSG_YELL,
    }
    return chatTypes
end

function module:GetOptions()
    local db = addon.db.profile.modules[module:GetName()]
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
                        desc = L["Toggle Chat module on or off."],
                        get = function() return db.enabled end,
                        set = function(_, value)
                            db.enabled = value
                            if value then
                                addon:EnableModule("Chat")
                            else
                                addon:DisableModule("Chat")
                            end
                        end
                    },
                    notifySelf = {
                        order = 20,
                        type = "toggle",
                        name = L["Notify Self"],
                        desc = L["Tell yourself who you are ressing."],
                        get = function() return db.notifySelf end,
                        set = function(_, value) db.notifySelf = value end
                    },
                    notifyCollision = {
                        order = 30,
                        type = "select",
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
                                addon:Print(L["You must include %s somewhere in the string for the target's name."])
                                return false
                            end
                            if value and value:len() >= 256 then
                                addon:Print(L["Message must be 255 characters or less. Currently %d characters."], value:len())
                                return false
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
                                module.singleRandomMessages[value] = value
                            end
                        end,
                        usage = L["Example: Hey %s, I am resurrecting you!"],
                        validate = function(_, value)
                            value = value:trim()
                            value = value:len() >= 1 and value or nil
                            if value and not strmatch(value, "%%s") then
                                addon:Print(L["You must include %s somewhere in the string for the target's name."])
                                return false
                            end
                            if value and value:len() >= 256 then
                                addon:Print(L["Message must be 255 characters or less. Currently %d characters."], value:len())
                                return false
                            end
                            return true
                        end
                    },
                    chatChannel = {
                        order = 30,
                        type = "select",
                        style = "dropdown",
                        name = L["Chat Channel"],
                        desc = L["Output channel for res messages."],
                        width = "half",
                        get = function() return db.singleResOutput end,
                        set = function(_, value) db.singleResOutput = value end,
                        values = function() return ChatTypes() end
                    },
                    enabledRandomSingleResMessages = {
                        order = 40,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Random Messages"],
                        desc = L["Toggle which random messages to use."],
                        width = 3,
                        get = function(_, key)
                            local strName = db.randomSingleMessages[key]
                            if db.randomSingleMessages[key] then
                                module.singleRandomMessages[strName] = strName
                            else
                                module.singleRandomMessages[strName] = nil
                            end
                            return db.randomSingleMessages[key]
                        end,
                        set = function(_, key, value)
                            local strName = db.randomSingleMessages[key]
                            db.randomSingleMessages[key] = value
                            if db.randomSingleMessages[key] then
                                module.singleRandomMessages[strName] = strName
                            else
                                module.singleRandomMessages[strName] = nil
                            end
                        end,
                        confirm = function()
                            if #module.singleRandomMessages == 1 then
                                return L["You are about to disable the last random message. Changing Chat Channel to None is a better solution. Confirm?"]
                            end
                            return false
                        end,
                        values = function() return addon:TranslateTable(db.randomSingleMessages) end
                    },
                    deleteRandomSingleResMessages = {
                        order = 50,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Delete Random Res Messages"],
                        desc = L["Delete messages from the DB. Reset the profile to undo."],
                        width = "full",
                        get = function(_, key) return #db.randomSingleMessages >= 1 and db.randomSingleMessages[key] or nil end,
                        set = function(_, key)
                            local strName = db.randomSingleMessages[key]
                            db.randomSingleMessages[key] = nil
                            module.singleRandomMessages[strName] = nil
                        end,
                        confirm = function()
                            if #db.randomSingleMessages == 1 then
                                return L["You are about to delete the last random message. Confirm?"]
                            end
                            return false
                        end,
                        values = function() return addon:TranslateTable(db.randomSingleMessages) end
                    }
                }
            }
        }
    }
    return options
end