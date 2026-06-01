-- File Date: @file-date-iso@

-- --------------------------------------------------------------------
-- SmartRes2 Chat Options
--
-- Core responsibilities:
-- - Expose Chat module enable/disable.
-- - Configure outgoing chat channels.
-- - Configure random and override resurrection messages.
-- --------------------------------------------------------------------

-- --------------------------------------------------------------------
-- Lua / Blizzard API upvalues
-- --------------------------------------------------------------------

local CHANNEL_CATEGORY_GROUP = CHANNEL_CATEGORY_GROUP
local CHAT_MSG_GUILD = CHAT_MSG_GUILD
local CHAT_MSG_INSTANCE_CHAT = CHAT_MSG_INSTANCE_CHAT
local CHAT_MSG_PARTY = CHAT_MSG_PARTY
local CHAT_MSG_RAID = CHAT_MSG_RAID
local CHAT_MSG_WHISPER_INFORM = CHAT_MSG_WHISPER_INFORM
local CHAT_OPTIONS_LABEL = CHAT_OPTIONS_LABEL
local DISABLE = DISABLE
local ENABLE = ENABLE
local MISCELLANEOUS = MISCELLANEOUS
local NONE = NONE
local LibStub = LibStub
local PlaySoundFile = PlaySoundFile
local string_format = string.format
local string_match = string.match

-- --------------------------------------------------------------------
-- Addon / module
-- --------------------------------------------------------------------

---@class SmartRes2: AceAddon
---@field db SmartRes2DB
local addon = LibStub("AceAddon-3.0"):GetAddon("SmartRes2")

---@class SmartRes2_Chat: AceAddon
---@field db SmartRes2_ChatDB
---@field randomSingleMessages string[]
---@field randomMassMessages string[]
---@field RefreshConfig fun(self: SmartRes2_Chat)
local module = addon:GetModule("Chat")

local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

-- --------------------------------------------------------------------
-- Constants
-- --------------------------------------------------------------------

local RESTORE_MESSAGES_ICON = [[Interface\AddOns\SmartRes2\Media\Icons\Undo.tga]]
local RESTORE_MESSAGES_SOUND = [[Interface\AddOns\SmartRes2\Media\Sounds\clickselect2.ogg]]

-- --------------------------------------------------------------------
-- File-scope state
-- --------------------------------------------------------------------

local options

local singleOutputValues = {
	GROUP = CHANNEL_CATEGORY_GROUP,
	INSTANCE_CHAT = CHAT_MSG_INSTANCE_CHAT,
	NONE = NONE,
	PARTY = CHAT_MSG_PARTY,
	RAID = CHAT_MSG_RAID,
	WHISPER = CHAT_MSG_WHISPER_INFORM,
}

local massOutputValues = {
	GROUP = CHANNEL_CATEGORY_GROUP,
	INSTANCE_CHAT = CHAT_MSG_INSTANCE_CHAT,
	NONE = NONE,
	PARTY = CHAT_MSG_PARTY,
	RAID = CHAT_MSG_RAID,
}

local collisionOutputValues = {
	GROUP = CHANNEL_CATEGORY_GROUP,
	NONE = NONE,
	WHISPER = CHAT_MSG_WHISPER_INFORM,
}

-- --------------------------------------------------------------------
-- Local helpers
-- --------------------------------------------------------------------

---@return SmartRes2_ChatProfileDB profile
local function GetProfileDB()
	return module.db.profile
end

---@return boolean disabled
local function IsModuleDisabled()
	return not GetProfileDB().enabled
end

---@param t table
---@return boolean empty
local function TableIsEmpty(t)
	return next(t) == nil
end

---@param value string|nil
---@return string|nil value
local function NormalizeInput(value)
	if value then
		value = value:trim()
	end

	if value and value:len() >= 1 then
		return value
	end
end

---@param value string|nil
---@return true|string result
local function ValidateSingleMessage(value)
	value = NormalizeInput(value)

	if value and not string_match(value, "%%s") then
		return L["You must include '%s' somewhere in the string for the target's name."]
	end

	if value and value:len() >= 256 then
		return string_format(L["Message must be 255 characters or less. Currently %d characters."], value:len())
	end

	return true
end

---@param value string|nil
---@return true|string result
local function ValidateMassMessage(value)
	value = NormalizeInput(value)

	if value and string_match(value, "%%s") then
		return L["Do not include '%s' as there are no target names."]
	end

	if value and value:len() >= 256 then
		return string_format(L["Message must be 255 characters or less. Currently %d characters."], value:len())
	end

	return true
end

---@param messageTable table<string, boolean>
---@return table<string, string> values
local function BuildMessageValues(messageTable)
	local values = {}

	for message in next, messageTable do
		values[message] = message
	end

	return values
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
		order = 50,
		type = "group",
		childGroups = "tab",
		name = CHAT_OPTIONS_LABEL,
		args = {
			generalOptions = {
				order = 10,
				type = "group",
				name = MISCELLANEOUS,
				args = {
					enabled = {
						order = 10,
						type = "toggle",
						name = ENABLE .. " / " .. DISABLE,
						desc = L["Toggle the Chat module on or off."],
						get = function()
							return GetProfileDB().enabled
						end,
						set = function(_, value)
							GetProfileDB().enabled = value

							if value then
								addon:EnableModule(module:GetName())
							else
								addon:DisableModule(module:GetName())
							end
						end,
					},
					notifyCollision = {
						order = 20,
						type = "select",
						style = "dropdown",
						name = L["Inform Colliders"],
						desc = L["Tell other players their spells will not finish first."],
						disabled = IsModuleDisabled,
						values = collisionOutputValues,
						get = function()
							return GetProfileDB().notifyCollision
						end,
						set = function(_, value)
							GetProfileDB().notifyCollision = value
						end,
					},
				},
			},
			singleRes = {
				order = 20,
				type = "group",
				name = L["Single Res Options"],
				disabled = IsModuleDisabled,
				args = {
					chatChannel = {
						order = 10,
						type = "select",
						style = "dropdown",
						name = L["Chat Channel"],
						desc = L["Output channel for single res messages."],
						values = singleOutputValues,
						get = function()
							return GetProfileDB().singleResOutput
						end,
						set = function(_, value)
							GetProfileDB().singleResOutput = value
						end,
					},
					overrideSingleResMessage = {
						order = 20,
						type = "input",
						name = L["Override Message"],
						desc = L["Overrides random single res messages."],
						width = "full",
						usage = L["Example: Hey %s, I am resurrecting you!"],
						get = function()
							return GetProfileDB().overrideSingleResMessage
						end,
						set = function(_, value)
							GetProfileDB().overrideSingleResMessage = NormalizeInput(value)
						end,
						validate = function(_, value)
							return ValidateSingleMessage(value)
						end,
					},
					addSingleResMessage = {
						order = 30,
						type = "input",
						name = L["Add To Random Messages"],
						width = "full",
						usage = L["Example: Hey %s, I am resurrecting you!"],
						get = function()
							return nil
						end,
						set = function(_, value)
							value = NormalizeInput(value)

							if value then
								GetProfileDB().randomSingleMessages[value] = true
								module:RefreshConfig()
							end
						end,
						validate = function(_, value)
							local result = ValidateSingleMessage(value)
							if result ~= true then
								return result
							end

							value = NormalizeInput(value)

							if value and GetProfileDB().randomSingleMessages[value] ~= nil then
								return string_format(L["The string %s already exists and cannot be added again."], value)
							end

							return true
						end,
					},
					enabledRandomSingleResMessages = {
						order = 40,
						type = "multiselect",
						dialogControl = "Dropdown",
						name = L["Random Messages"],
						desc = L["Toggle which random messages to use."],
						width = "full",
						values = function()
							return BuildMessageValues(GetProfileDB().randomSingleMessages)
						end,
						get = function(_, key)
							return GetProfileDB().randomSingleMessages[key]
						end,
						set = function(_, key, value)
							GetProfileDB().randomSingleMessages[key] = value
							module:RefreshConfig()
						end,
					},
					deleteRandomSingleResMessages = {
						order = 50,
						type = "multiselect",
						dialogControl = "Dropdown",
						name = L["Delete Random Res Messages"],
						desc = L["Delete messages from the DB. Click the Recycle Bin to undo."],
						width = "full",
						values = function()
							return BuildMessageValues(GetProfileDB().randomSingleMessages)
						end,
						get = function()
							return not TableIsEmpty(GetProfileDB().randomSingleMessages)
						end,
						set = function(_, key)
							GetProfileDB().deletedSingleMessages[key] = key
							GetProfileDB().randomSingleMessages[key] = nil
							module:RefreshConfig()
						end,
					},
					restoreRandomSingleResMessages = {
						order = 60,
						type = "execute",
						name = L["Restore Deleted Messages"],
						image = RESTORE_MESSAGES_ICON,
						imageWidth = 32,
						imageHeight = 32,
						disabled = function()
							return TableIsEmpty(GetProfileDB().deletedSingleMessages)
						end,
						func = function()
							for key in next, GetProfileDB().deletedSingleMessages do
								GetProfileDB().randomSingleMessages[key] = true
								GetProfileDB().deletedSingleMessages[key] = nil
							end

							module:RefreshConfig()
							PlaySoundFile(RESTORE_MESSAGES_SOUND, "Master")
						end,
					},
				},
			},
			massRes = {
				order = 30,
				type = "group",
				name = L["Mass Res Options"],
				disabled = IsModuleDisabled,
				args = {
					chatChannel = {
						order = 10,
						type = "select",
						style = "dropdown",
						name = L["Chat Channel"],
						desc = L["Output channel for mass res messages."],
						values = massOutputValues,
						get = function()
							return GetProfileDB().massResOutput
						end,
						set = function(_, value)
							GetProfileDB().massResOutput = value
						end,
					},
					overrideMassResMessage = {
						order = 20,
						type = "input",
						name = L["Override Message"],
						desc = L["Overrides random mass res messages."],
						width = "full",
						usage = L["Example: I am resurrecting everybody!"],
						get = function()
							return GetProfileDB().overrideMassResMessage
						end,
						set = function(_, value)
							GetProfileDB().overrideMassResMessage = NormalizeInput(value)
						end,
						validate = function(_, value)
							return ValidateMassMessage(value)
						end,
					},
					addMassResMessage = {
						order = 30,
						type = "input",
						name = L["Add To Random Messages"],
						width = "full",
						usage = L["Example: I am resurrecting everybody!"],
						get = function()
							return nil
						end,
						set = function(_, value)
							value = NormalizeInput(value)

							if value then
								GetProfileDB().randomMassMessages[value] = true
								module:RefreshConfig()
							end
						end,
						validate = function(_, value)
							local result = ValidateMassMessage(value)
							if result ~= true then
								return result
							end

							value = NormalizeInput(value)

							if value and GetProfileDB().randomMassMessages[value] ~= nil then
								return string_format(L["The string %s already exists and cannot be added again."], value)
							end

							return true
						end,
					},
					enabledRandomMassResMessages = {
						order = 40,
						type = "multiselect",
						dialogControl = "Dropdown",
						name = L["Random Messages"],
						desc = L["Toggle which random messages to use."],
						width = "full",
						values = function()
							return BuildMessageValues(GetProfileDB().randomMassMessages)
						end,
						get = function(_, key)
							return GetProfileDB().randomMassMessages[key]
						end,
						set = function(_, key, value)
							GetProfileDB().randomMassMessages[key] = value
							module:RefreshConfig()
						end,
					},
					deleteRandomMassResMessages = {
						order = 50,
						type = "multiselect",
						dialogControl = "Dropdown",
						name = L["Delete Random Res Messages"],
						desc = L["Delete messages from the DB. Click the Recycle Bin to undo."],
						width = "full",
						values = function()
							return BuildMessageValues(GetProfileDB().randomMassMessages)
						end,
						get = function()
							return not TableIsEmpty(GetProfileDB().randomMassMessages)
						end,
						set = function(_, key)
							GetProfileDB().deletedMassMessages[key] = key
							GetProfileDB().randomMassMessages[key] = nil
							module:RefreshConfig()
						end,
					},
					restoreRandomMassResMessages = {
						order = 60,
						type = "execute",
						name = L["Restore Deleted Messages"],
						image = RESTORE_MESSAGES_ICON,
						imageWidth = 32,
						imageHeight = 32,
						disabled = function()
							return TableIsEmpty(GetProfileDB().deletedMassMessages)
						end,
						func = function()
							for key in next, GetProfileDB().deletedMassMessages do
								GetProfileDB().randomMassMessages[key] = true
								GetProfileDB().deletedMassMessages[key] = nil
							end

							module:RefreshConfig()
							PlaySoundFile(RESTORE_MESSAGES_SOUND, "Master")
						end,
					},
				},
			},
		},
	}

	return options
end