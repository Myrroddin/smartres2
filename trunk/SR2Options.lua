-- SmartRes2 Options
-- Myrroddin of Llane

-- local variables
local L = LibStub("AceLocale-3.0"):GetLocale("SmartRes2")

local Colours = nil
local Candy = LibStub("LibCandyBar-3.0")
local Media = LibStub("LibSharedMedia-3.0")
local db = nil
local Anchor = nil

-- custom bar settings borrowed from BigWigs
local Times = nil
local Messages = nil
local Timers = nil

------------------------------------
--- Options
------------------------------------
local function setDefaults()
	-- default settings
	local defaults = {
		-- bar default settings
		scale = 1.0,
		texture = "Banto",
		font = "Fritz Quadrata TT",
		growUp = false,
		time = true,
		align = "LEFT",
		icon = true,
		SmartRes2Anchor_width = 200,
	}
end

-- bar arrangement
local function barSorter(a, b)
    return a.remaining < b.remaining and true or false
end

local tmp = {}
local function rearrangeBars(anchor)
	wipe(tmp)
	for bar in pairs(anchor.bars) do
		table.insert(tmp, bar)
	end
	table.sort(tmp, barSorter)
	local lastBarUp, lastBarDown = nil, nil
	local up = nil
	if anchor == Anchor then up = db.growUp end
end

function Addon:SR2_Options()
	local bars = setDefaults()
    -- 
end