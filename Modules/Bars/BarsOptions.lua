-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Bars Options
--
-- Current scope:
-- - Minimal Bars enable/disable option.
-- - Basic behavior/frame display settings.
-- - Container backdrop settings.
--
-- The real media, color, text, and theme options will grow after the Bars
-- runtime exists.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local BACKGROUND = BACKGROUND
local DISABLE = DISABLE
local EMBLEM_BORDER = EMBLEM_BORDER
local EMBLEM_BORDER_COLOR = EMBLEM_BORDER_COLOR
local FONT_SIZE = FONT_SIZE
local ENABLE = ENABLE
local GENERAL_LABEL = GENERAL_LABEL
local NONE = NONE
local TEXTURES_SUBHEADER = TEXTURES_SUBHEADER
local LibStub = LibStub

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

---@class SmartRes2: AceAddon
---@field LSM any
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

---@class SmartRes2_Bars: AceAddon
---@field db SmartRes2_BarsDB
---@field ClearTestBars fun(self: SmartRes2_Bars)
---@field RefreshConfig fun(self: SmartRes2_Bars)
---@field ShowTestBars fun(self: SmartRes2_Bars)
local module = addon:GetModule("Bars")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")
local LibSharedMedia = addon.LSM

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

local options

local growDirectionValues = {
	DOWN = L["Down"],
	UP = L["Up"],
}

local iconPositionValues = {
	NONE = NONE,
	LEFT = L["Left"],
	RIGHT = L["Right"],
}

local framePointValues = {
	TOPLEFT = L["Top Left"],
	TOP = L["Top"],
	TOPRIGHT = L["Top Right"],
	LEFT = L["Left"],
	CENTER = L["Center"],
	RIGHT = L["Right"],
	BOTTOMLEFT = L["Bottom Left"],
	BOTTOM = L["Bottom"],
	BOTTOMRIGHT = L["Bottom Right"],
}

local fontOutlineValues = {
	NONE = NONE,
	OUTLINE = L["Thin Outline"],
	THICKOUTLINE = L["Thick Outline"],
}

local function IsModuleDisabled()
	return not module.db.profile.enabled
end

local function IsShortTextDisabled()
	return IsModuleDisabled() or not module.db.profile.behavior.showLabel
end

local function IsFontShadowDisabled()
	return IsModuleDisabled() or not module.db.profile.text.shadow
end

-- --------------------------------------------------------------------
-- Options table
-- --------------------------------------------------------------------

---@return table options
function module:GetOptions()
	if options then
		return options
	end

	options = {
		order = 40,
		type = "group",
		childGroups = "tab",
		name = L["Bars"],
		args = {
			generalOptions = {
				order = 10,
				type = "group",
				name = GENERAL_LABEL,
				args = {
					enabled = {
						order = 10,
						type = "toggle",
						name = ENABLE .. " / " .. DISABLE,
						desc = L["Toggle the Bars module on or off."],
						get = function()
							return module.db.profile.enabled
						end,
						set = function(_, value)
							module.db.profile.enabled = value

							if value then
								addon:EnableModule(module:GetName())
							else
								addon:DisableModule(module:GetName())
							end
						end,
					},
					hideWhenEmpty = {
						order = 20,
						type = "toggle",
						name = L["Hide When Empty"],
						desc = L["Hide the Bars frame when there are no bars to display."],
						disabled = IsModuleDisabled,
						get = function()
							return module.db.profile.frame.hideWhenEmpty
						end,
						set = function(_, value)
							module.db.profile.frame.hideWhenEmpty = value
							module:RefreshConfig()
						end,
					},
					fill = {
						order = 30,
						type = "toggle",
						name = L["Fill Bars"],
						desc = L["Fill bars over time instead of draining them."],
						disabled = IsModuleDisabled,
						get = function()
							return module.db.profile.behavior.fill
						end,
						set = function(_, value)
							module.db.profile.behavior.fill = value
							module:RefreshConfig()
						end,
					},
					showTime = {
						order = 40,
						type = "toggle",
						name = L["Show Time"],
						desc = L["Show remaining time on bars."],
						disabled = IsModuleDisabled,
						get = function()
							return module.db.profile.behavior.showTime
						end,
						set = function(_, value)
							module.db.profile.behavior.showTime = value
							module:RefreshConfig()
						end,
					},
					showLabel = {
						order = 50,
						type = "toggle",
						name = L["Show Text"],
						desc = L["Show text labels on bars."],
						disabled = IsModuleDisabled,
						get = function()
							return module.db.profile.behavior.showLabel
						end,
						set = function(_, value)
							module.db.profile.behavior.showLabel = value
							module:RefreshConfig()
						end,
					},
					useShortLabels = {
						order = 60,
						type = "toggle",
						name = L["Use Short Text"],
						desc = L["Show shorter bar text, such as Caster : Target."],
						disabled = IsShortTextDisabled,
						get = function()
							return module.db.profile.behavior.useShortLabels
						end,
						set = function(_, value)
							module.db.profile.behavior.useShortLabels = value
							module:RefreshConfig()
						end,
					},
					maxBars = {
						order = 80,
						type = "range",
						name = L["Maximum Bars"],
						desc = L["Maximum number of bars to display. Hidden bars are still tracked."],
						disabled = IsModuleDisabled,
						min = 1,
						max = 40,
						step = 1,
						bigStep = 5,
						get = function()
							return module.db.profile.behavior.maxBars
						end,
						set = function(_, value)
							module.db.profile.behavior.maxBars = value
							module:RefreshConfig()
						end,
					},
					transitionDuration = {
						order = 90,
						type = "range",
						name = L["Transition Duration"],
						desc = L["How long bars fade during state changes. Set to 0 for instant changes."],
						disabled = IsModuleDisabled,
						min = 0,
						max = 0.5,
						step = 0.1,
						bigStep = 0.1,
						get = function()
							return module.db.profile.behavior.transitionDuration
						end,
						set = function(_, value)
							module.db.profile.behavior.transitionDuration = value
							module:RefreshConfig()
						end,
					},
					growDirection = {
						order = 100,
						type = "select",
						style = "dropdown",
						name = L["Grow Direction"],
						desc = L["Direction new bars are added from the container frame."],
						disabled = IsModuleDisabled,
						values = growDirectionValues,
						get = function()
							return module.db.profile.frame.growDirection
						end,
						set = function(_, value)
							module.db.profile.frame.growDirection = value
							module:RefreshConfig()
						end,
					},
					iconPosition = {
						order = 110,
						type = "select",
						style = "dropdown",
						name = L["Icon Position"],
						desc = L["Where to show bar icons."],
						disabled = IsModuleDisabled,
						values = iconPositionValues,
						get = function()
							return module.db.profile.behavior.iconPosition
						end,
						set = function(_, value)
							module.db.profile.behavior.iconPosition = value
							module:RefreshConfig()
						end,
					},
				},
			},
			frameOptions = {
				order = 20,
				type = "group",
				name = L["Frame"],
				disabled = IsModuleDisabled,
				args = {
					pixelSnap = {
						order = 10,
						type = "toggle",
						name = L["Pixel Snap"],
						desc = L["Round the Bars frame size and position to whole pixels."],
						get = function()
							return module.db.profile.frame.pixelSnap
						end,
						set = function(_, value)
							module.db.profile.frame.pixelSnap = value
							module:RefreshConfig()
						end,
					},
					clampToScreen = {
						order = 20,
						type = "toggle",
						name = L["Clamp to Screen"],
						desc = L["Prevent the bar frame from moving off your screen."],
						get = function()
							return module.db.profile.frame.clampToScreen
						end,
						set = function(_, value)
							module.db.profile.frame.clampToScreen = value
							module:RefreshConfig()
						end,
					},
					frameWidth = {
						order = 30,
						type = "range",
						name = L["Frame Width"],
						get = function()
							return module.db.profile.frame.width
						end,
						set = function(_, value)
							module.db.profile.frame.width = value
							module:RefreshConfig()
						end,
						min = 100,
						max = 600,
						step = 1,
						bigStep = 10,
					},
					frameHeight = {
						order = 50,
						type = "range",
						name = L["Frame Height"],
						get = function()
							return module.db.profile.frame.height
						end,
						set = function(_, value)
							module.db.profile.frame.height = value
							module:RefreshConfig()
						end,
						min = 50,
						max = 800,
						step = 1,
						bigStep = 10,
					},
					frameScale = {
						order = 60,
						type = "range",
						name = L["Frame Scale"],
						get = function()
							return module.db.profile.frame.scale
						end,
						set = function(_, value)
							module.db.profile.frame.scale = value
							module:RefreshConfig()
						end,
						isPercent = true,
						min = 0.5,
						max = 3,
						step = 0.01,
						bigStep = 0.1,
					},
					frameX = {
						order = 70,
						type = "range",
						name = L["Horizontal Offset"],
						desc = L["The offset may change within bounds of the anchor point."],
						get = function()
							return module.db.profile.frame.x
						end,
						set = function(_, value)
							module.db.profile.frame.x = value
							module:RefreshConfig()
						end,
						min = -960,
						max = 960,
						step = 1,
						bigStep = 40,
					},
					frameY = {
						order = 80,
						type = "range",
						name = L["Vertical Offset"],
						desc = L["The offset may change within bounds of the anchor point."],
						get = function()
							return module.db.profile.frame.y
						end,
						set = function(_, value)
							module.db.profile.frame.y = value
							module:RefreshConfig()
						end,
						min = -540,
						max = 540,
						step = 1,
						bigStep = 20,
					},
					framePoint = {
						order = 90,
						type = "select",
						style = "dropdown",
						name = L["Anchor Point"],
						values = framePointValues,
						get = function()
							return module.db.profile.frame.point
						end,
						set = function(_, value)
							module.db.profile.frame.point = value
							module:RefreshConfig()
						end,
					},
				},
			},
			backdropOptions = {
				order = 30,
				type = "group",
				name = L["Frame Style"],
				disabled = IsModuleDisabled,
				args = {
					background = {
						order = 10,
						type = "select",
						dialogControl = "LSM30_Background",
						name = BACKGROUND,
						values = LibSharedMedia:HashTable(LibSharedMedia.MediaType.BACKGROUND),
						get = function()
							return module.db.profile.frame.backdrop.background
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.background = value
							module:RefreshConfig()
						end,
					},
					backgroundColor = {
						order = 20,
						type = "color",
						name = L["Background Color"],
						hasAlpha = true,
						get = function()
							local color = module.db.profile.frame.backdrop.backgroundColor
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.frame.backdrop.backgroundColor = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					border = {
						order = 30,
						type = "select",
						dialogControl = "LSM30_Border",
						name = EMBLEM_BORDER,
						values = LibSharedMedia:HashTable(LibSharedMedia.MediaType.BORDER),
						get = function()
							return module.db.profile.frame.backdrop.border
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.border = value
							module:RefreshConfig()
						end,
					},
					borderColor = {
						order = 40,
						type = "color",
						name = EMBLEM_BORDER_COLOR,
						hasAlpha = true,
						get = function()
							local color = module.db.profile.frame.backdrop.borderColor
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.frame.backdrop.borderColor = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					borderThickness = {
						order = 50,
						type = "range",
						name = L["Border Thickness"],
						get = function()
							return module.db.profile.frame.backdrop.edgeSize
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.edgeSize = value
							module:RefreshConfig()
						end,
						min = 0,
						max = 32,
						step = 1,
						bigStep = 2,
					},
					leftInset = {
						order = 60,
						type = "range",
						name = L["Left Inset"],
						desc = L["How far to the left of the frame to place the border."],
						get = function()
							return module.db.profile.frame.backdrop.insets.left
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.insets.left = value
							module:RefreshConfig()
						end,
						min = 0,
						max = 32,
						step = 1,
						bigStep = 2,
					},
					rightInset = {
						order = 70,
						type = "range",
						name = L["Right Inset"],
						desc = L["How far to the right of the frame to place the border."],
						get = function()
							return module.db.profile.frame.backdrop.insets.right
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.insets.right = value
							module:RefreshConfig()
						end,
						min = 0,
						max = 32,
						step = 1,
						bigStep = 2,
					},
					topInset = {
						order = 80,
						type = "range",
						name = L["Top Inset"],
						desc = L["How far from the top of the frame to place the border."],
						get = function()
							return module.db.profile.frame.backdrop.insets.top
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.insets.top = value
							module:RefreshConfig()
						end,
						min = 0,
						max = 32,
						step = 1,
						bigStep = 2,
					},
					bottomInset = {
						order = 90,
						type = "range",
						name = L["Bottom Inset"],
						desc = L["How far from the bottom of the frame to place the border."],
						get = function()
							return module.db.profile.frame.backdrop.insets.bottom
						end,
						set = function(_, value)
							module.db.profile.frame.backdrop.insets.bottom = value
							module:RefreshConfig()
						end,
						min = 0,
						max = 32,
						step = 1,
						bigStep = 2,
					},
				},
			},
			barOptions = {
				order = 40,
				type = "group",
				name = L["Bar Options"],
				disabled = IsModuleDisabled,
				args = {
					barColorsHeader = {
						order = 5,
						type = "header",
						name = L["Bar Colors"],
					},
					goodColor = {
						order = 10,
						type = "color",
						name = L["Good Cast Color"],
						desc = L["Color for the fastest active resurrection cast."],
						hasAlpha = true,
						get = function()
							local color = module.db.profile.colors.good
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.colors.good = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					goodMassColor = {
						order = 20,
						type = "color",
						name = L["Good Mass Cast Color"],
						desc = L["Color for the fastest active mass resurrection cast."],
						hasAlpha = true,
						get = function()
							local color = module.db.profile.colors.goodMass
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.colors.goodMass = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					collisionColor = {
						order = 30,
						type = "color",
						name = L["Collision Color"],
						desc = L["Color for active resurrection casts that are not the fastest cast for that target."],
						hasAlpha = true,
						get = function()
							local color = module.db.profile.colors.collision
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.colors.collision = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					waitingColor = {
						order = 40,
						type = "color",
						name = L["Waiting Color"],
						desc = L["Color for targets who have a resurrection offer but have not accepted it yet."],
						hasAlpha = true,
						get = function()
							local color = module.db.profile.colors.waiting
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.colors.waiting = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					fontStylesHeader = {
						order = 50,
						type = "header",
						name = L["Font Styles"],
					},
					font = {
						order = 60,
						type = "select",
						dialogControl = "LSM30_Font",
						name = L["Font"],
						values = LibSharedMedia:HashTable(LibSharedMedia.MediaType.FONT),
						get = function()
							return module.db.profile.media.font
						end,
						set = function(_, value)
							module.db.profile.media.font = value
							module:RefreshConfig()
						end,
					},
					fontSize = {
						order = 70,
						type = "range",
						name = FONT_SIZE,
						min = 6,
						max = 32,
						step = 1,
						bigStep = 2,
						get = function()
							return module.db.profile.media.fontSize
						end,
						set = function(_, value)
							module.db.profile.media.fontSize = value
							module:RefreshConfig()
						end,
					},
					fontOutline = {
						order = 80,
						type = "select",
						style = "dropdown",
						name = L["Font Outline"],
						values = fontOutlineValues,
						get = function()
							return module.db.profile.media.fontOutline
						end,
						set = function(_, value)
							module.db.profile.media.fontOutline = value
							module:RefreshConfig()
						end,
					},
					fontSlug = {
						order = 90,
						type = "toggle",
						name = L["High Quality Font Rendering"],
						desc = L["Use Blizzard's high-quality font renderer when supported by this game client."],
						get = function()
							return module.db.profile.media.fontSlug
						end,
						set = function(_, value)
							module.db.profile.media.fontSlug = value
							module:RefreshConfig()
						end,
					},
					fontMonochrome = {
						order = 100,
						type = "toggle",
						name = L["Monochrome"],
						get = function()
							return module.db.profile.media.fontMonochrome
						end,
						set = function(_, value)
							module.db.profile.media.fontMonochrome = value
							module:RefreshConfig()
						end,
					},
					fontColor = {
						order = 110,
						type = "color",
						name = L["Font Color"],
						hasAlpha = true,
						get = function()
							local color = module.db.profile.text.color
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.text.color = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					fontShadow = {
						order = 120,
						type = "toggle",
						name = L["Font Shadow"],
						get = function()
							return module.db.profile.text.shadow
						end,
						set = function(_, value)
							module.db.profile.text.shadow = value
							module:RefreshConfig()
						end,
					},
					fontShadowColor = {
						order = 130,
						type = "color",
						name = L["Font Shadow Color"],
						disabled = IsFontShadowDisabled,
						hasAlpha = true,
						get = function()
							local color = module.db.profile.text.shadowColor
							return color.r, color.g, color.b, color.a
						end,
						set = function(_, r, g, b, a)
							module.db.profile.text.shadowColor = {
								r = r,
								g = g,
								b = b,
								a = a,
							}
							module:RefreshConfig()
						end,
					},
					fontShadowOffsetX = {
						order = 140,
						type = "range",
						name = L["Font Shadow X Offset"],
						disabled = IsFontShadowDisabled,
						min = -10,
						max = 10,
						step = 1,
						bigStep = 2,
						get = function()
							return module.db.profile.text.shadowOffsetX
						end,
						set = function(_, value)
							module.db.profile.text.shadowOffsetX = value
							module:RefreshConfig()
						end,
					},
					fontShadowOffsetY = {
						order = 150,
						type = "range",
						name = L["Font Shadow Y Offset"],
						disabled = IsFontShadowDisabled,
						min = -10,
						max = 10,
						step = 1,
						bigStep = 2,
						get = function()
							return module.db.profile.text.shadowOffsetY
						end,
						set = function(_, value)
							module.db.profile.text.shadowOffsetY = value
							module:RefreshConfig()
						end,
					},
					texturesHeader = {
						order = 160,
						type = "header",
						name = TEXTURES_SUBHEADER,
					},
					barTexture = {
						order = 170,
						type = "select",
						dialogControl = "LSM30_Statusbar",
						name = L["Bar Texture"],
						values = LibSharedMedia:HashTable(LibSharedMedia.MediaType.STATUSBAR),
						get = function()
							return module.db.profile.media.statusBar
						end,
						set = function(_, value)
							module.db.profile.media.statusBar = value
							module:RefreshConfig()
						end,
					},
					barBorder = {
						order = 180,
						type = "select",
						dialogControl = "LSM30_Border",
						name = L["Bar Border"],
						values = LibSharedMedia:HashTable(LibSharedMedia.MediaType.BORDER),
						get = function()
							return module.db.profile.media.barBorder
						end,
						set = function(_, value)
							module.db.profile.media.barBorder = value
							module:RefreshConfig()
						end,
					},
					barBorderThickness = {
						order = 190,
						type = "range",
						name = L["Bar Border Thickness"],
						min = 0,
						max = 16,
						step = 1,
						bigStep = 2,
						get = function()
							return module.db.profile.media.barBorderThickness
						end,
						set = function(_, value)
							module.db.profile.media.barBorderThickness = value
							module:RefreshConfig()
						end,
					},
					barSpacing = {
						order = 200,
						type = "range",
						name = L["Bar Spacing"],
						desc = L["Extra spacing between bars. SmartRes2 also accounts for bar border thickness so borders do not overlap."],
						min = 0,
						max = 32,
						step = 1,
						bigStep = 2,
						get = function()
							return module.db.profile.behavior.barSpacing
						end,
						set = function(_, value)
							module.db.profile.behavior.barSpacing = value
							module:RefreshConfig()
						end,
					}
				},
			},
			previewOptions = {
				order = 50,
				type = "group",
				name = L["Preview"],
				disabled = IsModuleDisabled,
				args = {
					description = {
						order = 10,
						type = "description",
						name = L["Show simulated resurrection bars so you can preview your current bar settings."],
						fontSize = "medium",
					},
					showTestBars = {
						order = 20,
						type = "execute",
						name = L["Show Test Bars"],
						desc = L["Show simulated resurrection bars so you can preview your current bar settings."],
						func = function()
							module:ShowTestBars()
						end,
					},
					clearTestBars = {
						order = 30,
						type = "execute",
						name = L["Clear Test Bars"],
						desc = L["Clear simulated resurrection bars."],
						func = function()
							module:ClearTestBars()
						end,
					},
				},
			},
		},
	}

	return options
end