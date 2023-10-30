local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Chat", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Chat:Print(...)

function module:GetOptions()
    local db = addon.db.profile.modules[module:GetName()]
    local options = {
        order = 10,
        type = "group",
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
                        set = function(_, value)
                            db.notifySelf = value
                        end
                    },
                    notifyCollision = {
                        order = 30,
                        type = "toggle",
                        name = L["Inform Colliders"],
                        desc = L["Tell other players their spells will not finish first."],
                        get = function() return db.notififyCollision end,
                        set = function(_, value)
                            db.notififyCollision = value
                        end
                    }
                }
            }
        }
    }
    return options
end