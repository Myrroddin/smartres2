-- Author      : Myrroddin of Llane
-- Localization file for US English version of SmartRes2, which is the default

local debug = false
--@debug@
debug = true
--@end-debug@
        
local L = LibStub("AceLocale-3.0"):NewLocale("SmartRes2", "enUS", true, debug)
--@localization(locale="enUS", format="lua_additive_table", same-key-is-true=true, escape-non-ascii=true, handle-subnamespaces="concat")@

if L then
   L["sr"] = true
   L["smartres"] = true   
   L["SmartRes2"] = true
   
   -- Interface Options Panel
   L["Res Bars"] = true
   L["Options for the res bars"] = true
   L["Res Bars Anchor"] = true
   L["Toggles the anchor for the res bars so you can move them"] = true
   L["Res Bars Icon"] = true
   L["Show or hide the icon for res spells"] = true
   L["Class Colours"] = true
   L["Use class colours for the target on the res bars"] = true
   L["Res Bars Texture"] = true
   L["Select the texture for the res bars"] = true
   L["Res Bars Background Colour"] = true
   L["Set the background colour for the res bars"] = true
   L["Res Bars Border"] = true
   L["Set the border for the res bars"] = true
   L["Res Bars Colour"] = true
   L["Pick the colour for non-collision (not a duplicate) res bar"] = true
   L["Duplicate Res Bars Colour"] = true
   L["Pick the colour for collision (duplicate) res bars"] = true
   L["Test Bars"] = true
   L["Show the test bars"] = true
   L["Chat Output"] = true
   L["Chat output options"] = true
   L["Random Res Messages"] = true
   L["Turn random res messages on or keep the same message.\nDefault is off"] = true
   L["Chat Output Type"] = true
   L["Where to print the res message.\nRaid, Party, Say, Yell, Guild, or None.\nDefault is None"] = true
   L["PARTY"] = true
   L["RAID"] = true
   L["SAY"] = true
   L["YELL"] = true
   L["GUILD"] = true
   L["none"] = true
   L["Self Notification"] = true
   L["Prints a message to yourself whom you are ressing"] = true
   L["Duplicate Res Targets"] = true
   L["Toggle whether you want to whisper a resser who is ressing a\ntarget of another resser's spell.\nCould get very spammy.\nDefault off"] = true
   L["Key Bindings"] = true
   L["Set the keybindings"] = true
   L["Auto Res Key"] = true
   L["For ressing targets who have not released their ghosts\nDefault is *"] = true
   L["Manual Target Key"] = true
   L["Gives you the pointer to click on corpses\nDefault is /"] = true
   L["SmartRes2 Credits"] = true
   L["About the author and SmartRes2"] = true
   L["Credits"] = true
   L["Massive kudos to Maia, Kyahx, and Poull for the original SmartRes.\nSmartRes2 was largely possible because of\nDathRarhek's LibResComm-1.0 so a big thanks to him."] = true
   L["I would personally like to thank Jerry on the wowace forums for coding the new, smarter, resurrection function."] = true
   
   L["% is ressing %"] = true
   L["You don't have enough Mana to cast a res spell."] = true
   L["You cannot cast res spells."] = true
   L["There are no bodies in range to res."] = true
   L["All dead units are being ressed."] = true
   L["Everybody is alive. Congratulations!"] = true
end