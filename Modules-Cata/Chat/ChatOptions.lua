local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Chat", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

-- WoW has cool table functions, upvalue them: https://github.com/Gethe/wow-ui-source/blob/87c526a3ae979a7f5244d635bd8ae952b4313bd8/Interface/SharedXML/TableUtil.lua
local GetOrCreateTableEntry, TableIsEmpty, tContains = GetOrCreateTableEntry, TableIsEmpty, tContains

local function GetChatTypes()
    local types = {
        ["GROUP"] = CHANNEL_CATEGORY_GROUP,
        ["GUILD"] = CHAT_MSG_GUILD,
        ["NONE"] = NONE,
        ["PARTY"] = CHAT_MSG_PARTY,
        ["RAID"] = CHAT_MSG_RAID,
        ["SAY"] = CHAT_MSG_SAY,
        ["WHISPER"] = CHAT_MSG_WHISPER_INFORM,
        ["YELL"] = CHAT_MSG_YELL,
    }
    return types
end

function module:GetOptions()
    self.db = addon.db:GetNamespace(module:GetName())
    local db = self.db.profile
    local options = {
        order = 60,
        type = "group",
        childGroups = "tab",
        disabled = function() return not addon.db.profile.enabled end,
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
                                if not module:IsEnabled() then
                                    addon:EnableModule(module:GetName())
                                end
                            else
                                if module:IsEnabled() then
                                    addon:DisableModule(module:GetName())
                                end
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
                        values = function() return GetChatTypes() end
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
                                GetOrCreateTableEntry(db.randomSingleMessages, value, true)
                                GetOrCreateTableEntry(self.randomSingleMessages, value, value)
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
                            if value and tContains(db.randomSingleMessages, value) then
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
                                GetOrCreateTableEntry(self.randomSingleMessages, key, key)
                            else
                                self.randomSingleMessages[key] = nil
                            end
                        end,
                        values = function() return addon:LocalizeTableKeys(db.randomSingleMessages) end
                    },
                    deleteRandomSingleResMessages = {
                        order = 40,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Delete Random Res Messages"],
                        desc = L["Delete messages from the DB. Click the Recycle Bin to undo."],
                        width = "full",
                        get = function() return TableIsEmpty(db.randomSingleMessages) and nil or true end,
                        set = function(_, key)
							-- the only possible value (not used) for "value" is false (because get always returns true), so we don't bother checking it and remove the entry from the table
                            GetOrCreateTableEntry(db.deletedSingleMessages, key, key)
                            db.randomSingleMessages[key] = nil
                            self.randomSingleMessages[key] = nil
                        end,
                        values = function() return addon:LocalizeTableKeys(db.randomSingleMessages) end
                    },
                    chatChannel = {
                        order = 50,
                        type = "select",
                        style = "dropdown",
                        name = L["Chat Channel"],
                        desc = L["Output channel for single res messages."],
                        get = function() return db.singleResOutput end,
                        set = function(_, value) db.singleResOutput = value end,
                        values = function() return GetChatTypes() end
                    },
                    restoreRandomSingleResMessages = {
                        order = 60,
                        type = "execute",
                        disabled = function() return TableIsEmpty(db.deletedSingleMessages) end,
                        image = "Interface\\AddOns\\SmartRes2\\Media\\Icons\\Undo.tga",
                        name = L["Restore Deleted Messages"],
                        imageHeight = 32,
                        imageWidth = 32,
                        func = function()
                            for key in pairs(db.deletedSingleMessages) do
                                GetOrCreateTableEntry(db.randomSingleMessages, key, true)
                                GetOrCreateTableEntry(self.randomSingleMessages, key, key)
                                db.deletedSingleMessages[key] = nil
                                PlaySoundFile("Interface\\AddOns\\SmartRes2\\Media\\Sounds\\clickselect2.ogg", "Master")
                            end
                        end
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
                                GetOrCreateTableEntry(db.randomMassMessages, value, true)
                                GetOrCreateTableEntry(self.randomMassMessages, value, value)
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
                            if value and tContains(db.randomMassMessages, value) then
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
                        values = function() return addon:LocalizeTableKeys(db.randomMassMessages) end
                    },
                    deleteRandomMassResMessages = {
                        order = 40,
                        type = "multiselect",
                        dialogControl = "Dropdown",
                        name = L["Delete Random Res Messages"],
                        desc = L["Delete messages from the DB. Click the Recycle Bin to undo."],
                        width = "full",
                        get = function() return TableIsEmpty(db.randomMassMessages) and nil or true end,
                        set = function(_, key)
							-- the only possible value (not used) for "value" is false (because get always returns true), so we don't bother checking it and remove the entry from the table
                            GetOrCreateTableEntry(db.deletedMassMessages, key, key)
                            db.randomMassMessages[key] = nil
                            self.randomMassMessages[key] = nil
                        end,
                        values = function() return addon:LocalizeTableKeys(db.randomMassMessages) end
                    },
                    chatChannel = {
                        order = 50,
                        type = "select",
                        style = "dropdown",
                        name = L["Chat Channel"],
                        desc = L["Output channel for mass res messages."],
                        get = function() return db.massResOutput end,
                        set = function(_, value) db.massResOutput = value end,
                        values = function() return GetChatTypes() end
                    },
                    restoreRandomSingleResMessages = {
                        order = 60,
                        type = "execute",
                        disabled = function() return TableIsEmpty(db.deletedMassMessages) end,
                        image = "Interface\\AddOns\\SmartRes2\\Media\\Icons\\Undo.tga",
                        name = L["Restore Deleted Messages"],
                        imageHeight = 32,
                        imageWidth = 32,
                        func = function()
                            for key in pairs(db.deletedMassMessages) do
                                GetOrCreateTableEntry(db.randomMassMessages, key, true)
                                GetOrCreateTableEntry(self.randomMassMessages, key, key)
                                db.deletedMassMessages[key] = nil
                                PlaySoundFile("Interface\\AddOns\\SmartRes2\\Media\\Sounds\\clickselect2.ogg", "Master")
                            end
                        end
                    }
                }
            }
        }
    }
    return options
end