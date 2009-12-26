-- Author      : Myrroddin of Llane
-- Localization file for US English version of SmartRes2, which is the default
      
local debug = false
--[===[@debug@
debug = true
--@end-debug@]===]

local L = LibStub("AceLocale-3.0"):NewLocale("SmartRes2", "enUS", true, debug)

if L then
	-- additional libraries
	L["%s requires the library '%s' to be available."] = true	
	   
	-- LibDataBroker stuff
	L["Left click to lock/unlock the res bars. Right click for configuration."] = true
   
	-- Interface Options Panel
	L["Res Bars"] = true
	L["Options for the res bars"] = true
	L["Anchor"] = true
	L["Toggles the anchor for the res bars so you can move them"] = true
	L["Show Icon"] = true
	L["Show or hide the icon for res spells"] = true
	L["Class Colours"] = true
	L["Use class colours for the target on the res bars"] = true
	L["Texture"] = true
	L["Select the texture for the res bars"] = true
	L["Background Colour"] = true
	L["Set the background colour for the res bars"] = true
	L["Border"] = true
	L["Set the border for the res bars"] = true
	L["Bar Colour"] = true
	L["Pick the colour for non-collision (not a duplicate) res bar"] = true
	L["Duplicate Bar Colour"] = true
	L["Pick the colour for collision (duplicate) res bars"] = true
	L["Grow Upwards"] = true
	L["Make the res bars grow up instead of down"] = true
	L["Scale"] = true
	L["Set the scale for the res bars"] = true
	L["Horizontal Direction"] = true
	L["Change the horizontal direction of the res bars"] = true
	L["Right to Left"] = true
	L["Left to Right"] = true
	L["Test Bars"] = true
	L["Show the test bars"] = true
	L["Chat Output"] = true
	L["Chat output options"] = true
	L["Random Res Messages"] = true
	L["Turn random res messages on or keep the same message.\nDefault is off"] = true
	L["Chat Output Type"] = true
	L["Where to print the res message.\nRaid, Party, Say, Yell, Guild, or None.\nDefault is None"] = true
	L["Group"] = true
	L["Guild"] = true
	L["Party"] = true
	L["Raid"] = true
	L["Say"] = true
	L["Yell"] = true
	L["Self Notification"] = true
	L["Prints a message to yourself whom you are ressing"] = true
	L["Duplicate Res Targets"] = true
	L["Toggle whether you want to whisper a resser who is ressing a\ntarget of another resser's spell.\nCould get very spammy.\nDefault off"] = true
	L["Key Bindings"] = true
	L["Set the keybindings"] = true
	L["Auto Res Key"] = true
	L["For ressing targets who have not released their ghosts"] = true
	L["Manual Target Key"] = true
	L["Gives you the pointer to click on corpses"] = true
	L["SmartRes2 Credits"] = true
	L["About the author and SmartRes2"] = true
	L["Credits"] = true
	L["Massive kudos to Maia, Kyahx, and Poull for the original SmartRes.\nSmartRes2 was largely possible because of DathRarhek's LibResComm-1.0 so a big thanks to him."] = true
	L["I would personally like to thank Jerry on the wowace forums for coding the new, smarter, resurrection function."] = true
	L["About"] = true
	   
	-- Resurrection function localization
	L["You are not in a group."] = true
	L["%s is ressing %s"] = true
	L["You don't have enough Mana to cast a res spell."] = true
	L["You cannot cast res spells."] = true
	L["There are no bodies in range to res."] = true
	L["All dead units are being ressed."] = true
	L["Everybody is alive. Congratulations!"] = true
	L["is resurrecting "] = true
	L["Unknown"] = true
	   
	-- silly random messages!
	L["%s is bringing %s back to life!"] = true
	L["Filthy peon! %s has to resurrect %s!"] = true
	L["%s has to wake %s from eternal slumber."] = true
	L["%s is ending %s's dirt nap."] = true
	L["No fallen heroes! %s needs %s to march forward to victory!"] = true
	L["%s doesn't think %s is immortal, but after this res cast, it is close enough."] = true
	L["Sleeping on the job? %s is disappointed in %s."] = true
	L["%s knew %s couldn't stay out of the fire. *Sigh*"] = true
	L["Once again, %s pulls %s and their bacon out of the fire."] = true
	L["%s thinks %s should work on their Dodge skill."] = true
	L["%s refuses to accept blame for %s's death, but kindly undoes the damage."] = true
	L["%s grabs a stick. A-ha! %s was only temporarily dead."] = true
	L["%s knows %s is faking. It was only a flesh wound!"] = true
	L["Oh. My. God. %s has to breathe life back into %s AGAIN?!?"] = true
	L["%s knows that %s dying was just an excuse to see another silly random res message."] = true
	L["Think that was bad? %s proudly shows %s the scar tissue caused by Hogger."] = true
	L["Just to be silly, %s tickles %s until they get back up."] = true
	L["FOR THE HORDE! FOR THE ALLIANCE! %s thinks %s should be more concerned about yelling FOR THE LICH KING! and prevents that from happening."] = true
	L["And you thought the Scourge looked bad. In about 10 seconds, %s knows %s will want a comb, some soap, and a mirror."] = true
	L["Somewhere, the Lich King is laughing at %s, because he knows %s will just die again eventually. More meat for the grinder!!"] = true
	L["%s doesn't want the Lich King to get another soldier, so is bringing %s back to life."] = true
	L["%s wonders about these stupid res messages. %s should just be happy to be alive."] = true
	L["%s prays over the corpse of %s, and a miracle happens!"] = true
	L["In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %s is making sure %s's death isn't permanent."] = true
	L["%s performs a series of lewd acts on %s's still warm corpse. Ew."] = true
	L["%s prods %s with a stick. A-ha! %s was only temporarily dead."] = true
	L["Think that was bad? %s proudly shows %s the scar tissue caused by Ragnaros."] = true
	   
	-- chat output stuff
	L["You are ressing %s"] = true
	-- stupid long strings
	L["SmartRes2 would like you to know that %s is already being ressed by %s. "] = true
	L["Please get SmartRes2 and use the auto res key to never see this whisper again."] = true
end