-- get the vaargs passed to the whole addon
local _, namespace = ...

-- Localization shim: returns the key itself if no translation exists.
-- This allows the library to function even if translations are missing.
local L = setmetatable({}, { __index = function(t, k)
	local v = tostring(k)
	rawset(t, k, v)
	return v
end })

namespace.L = L