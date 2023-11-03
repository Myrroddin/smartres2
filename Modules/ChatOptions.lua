local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Chat", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

local isMainline = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
local function ChatTypes()
    local chatTypes = {
        ["GROUP"] = CHANNEL_CATEGORY_GROUP,
        ["GUILD"] = CHAT_MSG_GUILD,
        ["NONE"] = NONE,
        ["PARTY"] = CHAT_MSG_PARTY,
        ["RAID"] = CHAT_MSG_RAID,
        ["SAY"] = CHAT_MSG_SAY,
        ["WHISPER"] = CHAT_MSG_WHISPER_INFORM,
        ["YELL"] = CHAT_MSG_YELL,
    }
    if isMainline then
        chatTypes["INSTANCE"] = CHAT_MSG_INSTANCE_CHAT
    end
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
                                tinsert(module.randomSingleMessages, value)
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
                        dialogControl = "dropdown",
                        name = L["Random Messages"],
                        desc = L["Toggle which random messages to use."],
                        width = 2.5,
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
                        values = function() return addon:TranslateTable(db.randomSingleMessages) end
                    }
                }
            }
        }
    }
    return options
end