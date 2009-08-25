-- Author      : Myrroddin of Llane
-- Localization file for US English version of SmartRes2, which is the default

--[[ other locales need a seperate file. for deDE (German) the new file would be saved in the Locales folder and called \Locales\Localization.deDE.lua
    copy/paste the code in this file, and change it according to the following example:
    
    -- Author   : Myrroddin of Llane
    -- Localization file for German version of SmartRes2
    -- deDE Localization: Your name here
    
    local L = LibStub("AceLocale-3.0"):NewLocale("SmartRes2", "deDE", false) -- false because deDE (German) is not the default localization
    
    if L then
        -- options localization for the UInterface Panels. You can translate these comments if you so wish.
        L["Resurrection Message"] = "whatever this translates to in German"
        -- Note for translators: if any line has %s you must keep that variable. it will automatically be replaced by the appropriate data, but you will have to translate the whole line, variable included
        etc
    end
]]--
        
local L = LibStub("AceLocale-3.0"):NewLocale("SmartRes2", "enUS", true)

if L then
   -- chat commands
   L["sr"] = true
   L["sr2"] = true
   L["smartres"] = true
   L["smartres2"] = true
   
   L["%s is resurrecting %s"] = true -- default res message on bars. vars = resser, targetName
   
   -- options localization for the UInterface Panels
   L["Message Config"] = true
   L["Bar Config"] = true
   L["Key Bindings"] = true
   L["Resurrection Message"] = true
   L["Change the Resurrection message."] = true
   L["<Your message> Example: Hey %s, GET UP!!! **NOTE: %s will be replaced by the target's name."] = true   
   L["Random Messages"] = true
   L["Turn random res messages on or off."] = true
   L["Chat Output Channel"] = true
   L["Where to announce your res spell casts."] = true
   L["Target Whispering"] = true
   L["Whisper the target that you are casting a res on them."] = true
   L["Bar Textures"] = true
   L["Select an optional texture for the bars."] = true
   L["Auto Res Key"] = true
   L["Used for ressing players who have not released their ghost."] = true
   L["Pick any key or combination of keys. **NOTE: This will rebind key(s) if applicable."] = true
   L["Manual Res Key"] = true
   L["Used for ressing with the pointer cursor on ghost players."] = true
   L["Random Bar Textures"] = true
   L["Randomly uses different textures on the res bars."] = true
   
   L[targetName.." has been ressed by "..resser..". You may want to change targets."] = true   
   L[targetName.." is already being ressed by "..resser..". You can prevent this whisper by using SmartRes2's auto res key."] = true
   L["Nobody is dead! Congratulations!!"] = true
   
   L["%s would have ressed you, but you were AFK."] = true -- player whispering to a dead but AFK target
end