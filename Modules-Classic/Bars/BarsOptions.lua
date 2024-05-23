local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Bars", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Bars:Print(...)

function module:GetOptions()
    self.db = addon.db:GetNamespace(module:GetName())
    local db = self.db.profile
    local options = {
        type = "group",
        childGroups = "tab",
        name = L["Res Bars Options"],
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
                }
            },
            barColours = {
                order = 20,
                type = "group",
                disabled = function() return not db.enabled end,
                name = COLORS,
                args = {}
            },
            barFonts = {
                order = 30,
                type = "group",
                disabled = function() return not db.enabled end,
                name = L["Fonts"],
                args = {}
            },
            barTextures = {
                order = 40,
                type = "group",
                disabled = function() return not db.enabled end,
                name = TEXTURES_SUBHEADER,
                args = {}
            }
        }
    }
    return options
end