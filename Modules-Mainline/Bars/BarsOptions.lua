local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")
local module = addon:GetModule("Bars", false)
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local AceGUIWidgetLSMlists = LibStub("AceGUISharedMediaWidgets-1.0") and AceGUIWidgetLSMlists

-- we must remember to call addon:Print(..) to get SmartRes2:Print(...)
-- if we call self:Print(...) we would get Bars:Print(...)

function module:GetOptions()
    self.db = addon.db:GetNamespace(module:GetName())
    local db = self.db.profile
    local options = {
        order = 60,
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
                    }
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
                    },
                    goodMassRes = {
                        order = 30,
                        type = "color",
                        hasAlpha = true,
                        width = 1.25,
                        name = L["Non-Collision Mass Res"],
                        get = function()
                            local c = db.goodMassRes
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local c = db.goodMassRes
                            c.r, c.g, c.b, c.a = r, g, b, a
                        end
                    },
                    collisionMassRes = {
                        order = 40,
                        type = "color",
                        hasAlpha = true,
                        width = 1.25,
                        name = L["Collision Mass Res"],
                        get = function()
                            local c = db.collisionMassRes
                            return c.r, c.g, c.b, c.a
                        end,
                        set = function(_, r, g, b, a)
                            local c = db.collisionMassRes
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
                        bigStep = 3
                    },
                    fontFlags = {
                        order = 30,
                        type = "select",
                        style = "dropdown",
                        name = ANTIALIASING .. " " .. QUEST_LOGIC_AND .. " " .. EMBLEM_BORDER,
                        width = 1.25,
                        get = function() return db.fontFlags end,
                        set = function(_, value) db.fontFlags = value end,
                        values = {
                            [""] = NONE,
                            ["MONOCHROME"] = ANTIALIASING,
                            ["OUTLINE"] = L["Black Outline"],
                            ["THICK"] = L["Thick Black Outline"],
                            ["MONOCHROME, OUTLINE"] = ANTIALIASING .. " " .. L["and a Black Outline"],
                            ["MONOCHROME, THICK"] = ANTIALIASING .. " " .. L["and a Thick Black Outline"],
                        }
                    }
                }
            },
            barTextures = {
                order = 40,
                type = "group",
                disabled = function() return not db.enabled end,
                name = TEXTURES_SUBHEADER,
                args = {
                    border = {
                        order = 10,
                        type = "select",
                        dialogControl = "LSM30_Border",
                        name = EMBLEM_BORDER,
                        get = function() return db.border end,
                        set = function(_, value) db.border = value end,
                        values = AceGUIWidgetLSMlists.border
                    },
                    borderThickness = {
                        order = 20,
                        type = "range",
                        name = L["Border Thickness"],
                        get = function() return db.borderThickness end,
                        set = function(_, value) db.borderThickness = value end,
                        min = 1,
                        max = 15,
                        step = 1,
                        bigStep = 5
                    },
                    borderLeftInset = {
                        order = 30,
                        type = "range",
                        name = L["Left Inset"],
                        desc = L["How far to the left of the frame to place the border."],
                        get = function() return db.leftInset end,
                        set = function(_, value) db.leftInset = value end,
                        min = -5,
                        max = 5,
                        step = 1,
                        bigStep = 5
                    },
                    borderRightInset = {
                        order = 40,
                        type = "range",
                        name = L["Right Inset"],
                        desc = L["How far to the right of the frame to place the border."],
                        get = function() return db.rightInset end,
                        set = function(_, value) db.rightInset = value end,
                        min = -5,
                        max = 5,
                        step = 1,
                        bigStep = 5
                    },
                    borderTopInset = {
                        order = 50,
                        type = "range",
                        name = L["Top Inset"],
                        desc = L["How far from the top of the frame to place the border."],
                        get = function() return db.topInset end,
                        set = function(_, value) db.topInset = value end,
                        min = -5,
                        max = 5,
                        step = 1,
                        bigStep = 5
                    },
                    borderBottomInset = {
                        order = 60,
                        type = "range",
                        name = L["Bottom Inset"],
                        desc = L["How far from the bottom of the frame to place the border."],
                        get = function() return db.bottomInset end,
                        set = function(_, value) db.bottomInset = value end,
                        min = -5,
                        max = 5,
                        step = 1,
                        bigStep = 5
                    },
                    background = {
                        order = 70,
                        type = "select",
                        dialogControl = "LSM30_Background",
                        name = EMBLEM_BACKGROUND,
                        get = function() return db.background end,
                        set = function(_, value) db.background = value end,
                        values = AceGUIWidgetLSMlists.background
                    },
                    statusBar = {
                        order = 80,
                        type = "select",
                        dialogControl = "LSM30_Statusbar",
                        name = L["Bar Texture"],
                        get = function() return db.statusBar end,
                        set = function(_, value) db.statusBar = value end,
                        values = AceGUIWidgetLSMlists.statusbar
                    }
                }
            }
        }
    }
    return options
end