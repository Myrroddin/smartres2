local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Bars", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Bars:Print(...)

function module:GetOptions()
    self.db = addon.db:GetNamespace(module:GetName())
    local db = self.db.profile
    local options = {
        order = 70,
        type = "group",
        childGroups = "tab",
        disabled = function() return not addon.db.profile.enabled end,
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
                args = {
                    goodSingleRes = {
                        order = 10,
                        type = "color",
                        hasAlpha = true,
                        width = 1.25,
                        name = L["Non-Collision Single Res"],
                        get = function()
                            local c = db.goodSingleRes
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local c = db.goodSingleRes
                            c.r, c.g, c.b, c.a = r, g, b, a
                        end
                    },
                    collisionSingleRes = {
                        order = 20,
                        type = "color",
                        hasAlpha = true,
                        width = 1.25,
                        name = L["Collision Single Res"],
                        get = function()
                            local c = db.collisionSingleRes
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local c = db.collisionSingleRes
                            c.r, c.g, c.b, c.a = r, g, b, a
                        end
                    }
                }
            },
            barFonts = {
                order = 30,
                type = "group",
                disabled = function() return not db.enabled end,
                name = L["Fonts"],
                args = {
                    fontType = {
                        order = 10,
                        type = "select",
						dialogControl = "LSM30_Font",
                        name = L["Font"],
                        width = 1.75,
                        get = function() return db.fontType end,
                        set = function(_, value) db.fontType = value end,
                        values = AceGUIWidgetLSMlists.font
                    },
                    fontSize = {
                        order = 20,
                        type = "range",
                        name = FONT_SIZE,
                        get = function() return db.fontSize end,
                        set = function(_, value) db.fontSize = value end,
                        min = 6,
                        max = 18,
                        step = 1,
                        bigStep = 2
                    }
                }
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