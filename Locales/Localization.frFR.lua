-- Authors: ckeurk and Xilbar
-- Localization file for French version of SmartRes2

local debug = false
--[===[@debug@
debug = true
--@end-debug@]===]

local L = LibStub("AceLocale-3.0"):NewLocale("SmartRes2", "frFR", false, debug) -- this is not the default language

--[===[@non-debug@
@localization(locale="frFR", format="lua_additive_table", same-key-is-true=true, handle-unlocalized="english")@
--@end-non-debug@]===]

if L then
	L["About"] = "About" -- Requires localization
	L["About the author and SmartRes2"] = "A propos de l'auteur et de SmartRes2"
	L["All dead units are being ressed."] = "Tous les personnages morts ont \195\169t\195\169 ressuscit\195\169s."
	L["Anchor"] = "Anchor" -- Requires localization
	L["And you thought the Scourge looked bad. In about 10 seconds, %s knows %s will want a comb, some soap, and a mirror."] = "Et vous pensiez que le Fl\195\169au \195\169tait vilain. Dans environ 10 secondes,%s conna\195\174trons%s et voudrons un peigne, du savon, et un miroir."
	L["Auto Res Key"] = "Touche d'auto Res"
	L["Background Colour"] = "Background Colour" -- Requires localization
	L["Bar Colour"] = "Bar Colour" -- Requires localization
	L["Border"] = "Border" -- Requires localization
	L["Change the horizontal direction of the res bars"] = "Change the horizontal direction of the res bars" -- Requires localization
	L["Chat Output"] = "Chat sortie"
	L["Chat output options"] = "Sortie des options de chat"
	L["Chat Output Type"] = "Chat type de sortie"
	L["Class Colours"] = "Coleurs des classes"
	L["Credits"] = "Cr\195\169dits"
	L["Duplicate Bar Colour"] = "Duplicate Bar Colour" -- Requires localization
	L["Duplicate Res Targets"] = "Dupliquer la cible de Res"
	L["Everybody is alive. Congratulations!"] = "Tout le monde est en vie. F\195\169licitation !"
	L["Filthy peon! %s has to resurrect %s!"] = "Filthy peon! %s has to resurrect %s!" -- Requires localization
	L["For ressing targets who have not released their ghosts"] = "For ressing targets who have not released their ghosts" -- Requires localization
	L["FOR THE HORDE! FOR THE ALLIANCE! %s thinks %s should be more concerned about yelling FOR THE LICH KING! and prevents that from happening."] = "FOR THE HORDE! FOR THE ALLIANCE! %s thinks %s should be more concerned about yelling FOR THE LICH KING! and prevents that from happening." -- Requires localization
	L["Gives you the pointer to click on corpses"] = "Gives you the pointer to click on corpses" -- Requires localization
	L["Group"] = "Group" -- Requires localization
	L["Grow Upwards"] = "Grow Upwards" -- Requires localization
	L["Guild"] = "Guild" -- Requires localization
	L["Horizontal Direction"] = "Horizontal Direction" -- Requires localization
	L["In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %s is making sure %s's death isn't permanent."] = "In a world of resurrection spells, why are NPC deaths permanent? It doesn't matter, since %s is making sure %s's death isn't permanent." -- Requires localization
	L["is resurrecting "] = "is resurrecting " -- Requires localization
	L["I would personally like to thank Jerry on the wowace forums for coding the new, smarter, resurrection function."] = "Je tiens personnellement \195\160 remercier Jerry sur les forums de WowAce et du nouveau codage, plus intelligente, et la fonction de r\195\169surrection"
	L["Just to be silly, %s tickles %s until they get back up."] = "Just to be silly, %s tickles %s until they get back up." -- Requires localization
	L["Key Bindings"] = "Raccourcis clavier"
	L["Left click to lock/unlock the res bars. Right click for configuration."] = "Left click to lock/unlock the res bars. Right click for configuration." -- Requires localization
	L["Left to Right"] = "Left to Right" -- Requires localization
	L["Make the res bars grow up instead of down"] = "Make the res bars grow up instead of down" -- Requires localization
	L["Manual Target Key"] = "Touche manuel de la cible"
	L["Massive kudos to Maia, Kyahx, and Poull for the original SmartRes.\
	SmartRes2 was largely possible because of DathRarhek's LibResComm-1.0 so a big thanks to him."] = "Massive kudos to Maia, Kyahx, and Poull for the original SmartRes.\
	SmartRes2 was largely possible because of DathRarhek's LibResComm-1.0 so a big thanks to him." -- Requires localization
	L["No fallen heroes! %s needs %s to march forward to victory!"] = "No fallen heroes! %s needs %s to march forward to victory!" -- Requires localization
	L["Oh. My. God. %s has to breathe life back into %s AGAIN?!?"] = "Oh. My. God. %s has to breathe life back into %s AGAIN?!?" -- Requires localization
	L["Once again, %s pulls %s and their bacon out of the fire."] = "Once again, %s pulls %s and their bacon out of the fire." -- Requires localization
	L["Options for the res bars"] = "Options pour les bars de Res"
	L["Party"] = "Party" -- Requires localization
	L["Pick the colour for collision (duplicate) res bars"] = "Pick the colour for collision (duplicate) res bars" -- Requires localization
	L["Pick the colour for non-collision (not a duplicate) res bar"] = "Pick the colour for non-collision (not a duplicate) res bar" -- Requires localization
	L["Please get SmartRes2 and use the auto res key to never see this whisper again."] = "Please get SmartRes2 and use the auto res key to never see this whisper again." -- Requires localization
	L["Prints a message to yourself whom you are ressing"] = "Prints a message to yourself whom you are ressing" -- Requires localization
	L["Raid"] = "Raid" -- Requires localization
	L["Random Res Messages"] = "Random Res Messages" -- Requires localization
	L["Res Bars"] = "Barres de Res"
	L["Right to Left"] = "Right to Left" -- Requires localization
	L["Say"] = "Say" -- Requires localization
	L["Scale"] = "Scale" -- Requires localization
	L["%s doesn't think %s is immortal, but after this res cast, it is close enough."] = "%s doesn't think %s is immortal, but after this res cast, it is close enough." -- Requires localization
	L["%s doesn't want the Lich King to get another soldier, so is bringing %s back to life."] = "%s doesn't want the Lich King to get another soldier, so is bringing %s back to life." -- Requires localization
	L["Select the texture for the res bars"] = "S\195\169lectionnez la texture pour les barres de Res"
	L["Self Notification"] = "Self Notification" -- Requires localization
	L["Set the background colour for the res bars"] = "Set the background colour for the res bars" -- Requires localization
	L["Set the border for the res bars"] = "D\195\169finissez la fronti\195\168re pour les barres de Res "
	L["Set the keybindings"] = "Ensemble pour les raccourcis claviers"
	L["Set the scale for the res bars"] = "Set the scale for the res bars" -- Requires localization
	L["%s grabs a stick. A-ha! %s was only temporarily dead."] = "%s grabs a stick. A-ha! %s was only temporarily dead." -- Requires localization
	L["%s has to wake %s from eternal slumber."] = "%s has to wake %s from eternal slumber." -- Requires localization
	L["Show Icon"] = "Show Icon" -- Requires localization
	L["Show or hide the icon for res spells"] = "Show or hide the icon for res spells" -- Requires localization
	L["Show the test bars"] = "Show the test bars" -- Requires localization
	L["%s is bringing %s back to life!"] = "%s is bringing %s back to life!" -- Requires localization
	L["%s is ending %s's dirt nap."] = "%s is ending %s's dirt nap." -- Requires localization
	L["%s is ressing %s"] = "%s is ressing %s" -- Requires localization
	L["%s knew %s couldn't stay out of the fire. *Sigh*"] = "%s knew %s couldn't stay out of the fire. *Sigh*" -- Requires localization
	L["%s knows %s is faking. It was only a flesh wound!"] = "%s knows %s is faking. It was only a flesh wound!" -- Requires localization
	L["%s knows that %s dying was just an excuse to see another silly random res message."] = "%s knows that %s dying was just an excuse to see another silly random res message." -- Requires localization
	L["Sleeping on the job? %s is disappointed in %s."] = "Sleeping on the job? %s is disappointed in %s." -- Requires localization
	L["SmartRes2 Credits"] = "SmartRes2 Cr\195\169dits"
	L["SmartRes2 would like you to know that %s is already being ressed by %s. "] = "SmartRes2 would like you to know that %s is already being ressed by %s. " -- Requires localization
	L["Somewhere, the Lich King is laughing at %s, because he knows %s will just die again eventually. More meat for the grinder!!"] = "Quelque part, le roi-liche se moque de %s, parce qu'il sait que %s va juste mourir \195\160 nouveau. Plus de viande pour le moulin!"
	L["%s performs a series of lewd acts on %s's still warm corpse. Ew."] = "%s performs a series of lewd acts on %s's still warm corpse. Ew." -- Requires localization
	L["%s prays over the corpse of %s, and a miracle happens!"] = "%s prays over the corpse of %s, and a miracle happens!" -- Requires localization
	L["%s prods %s with a stick. A-ha! %s was only temporarily dead."] = "%s prods %s with a stick. A-ha! %s was only temporarily dead." -- Requires localization
	L["%s refuses to accept blame for %s's death, but kindly undoes the damage."] = "%s refuses to accept blame for %s's death, but kindly undoes the damage." -- Requires localization
	L["%s requires the library '%s' to be available."] = "%s requires the library '%s' to be available." -- Requires localization
	L["%s thinks %s should work on their Dodge skill."] = "%s thinks %s should work on their Dodge skill." -- Requires localization
	L["%s wonders about these stupid res messages. %s should just be happy to be alive."] = "%s wonders about these stupid res messages. %s should just be happy to be alive." -- Requires localization
	L["Test Bars"] = "Test Barres"
	L["Texture"] = "Texture" -- Requires localization
	L["There are no bodies in range to res."] = "Il n'y a pas de corps \195\160 res."
	L["Think that was bad? %s proudly shows %s the scar tissue caused by Hogger."] = "Think that was bad? %s proudly shows %s the scar tissue caused by Hogger." -- Requires localization
	L["Think that was bad? %s proudly shows %s the scar tissue caused by Ragnaros."] = "Think that was bad? %s proudly shows %s the scar tissue caused by Ragnaros." -- Requires localization
	L["Toggles the anchor for the res bars so you can move them"] = "Toggles the anchor for the res bars so you can move them" -- Requires localization
	L["Toggle whether you want to whisper a resser who is ressing a\
	target of another resser's spell.\
	Could get very spammy.\
	Default off"] = "Toggle whether you want to whisper a resser who is ressing a\
	target of another resser's spell.\
	Could get very spammy.\
	Default off" -- Requires localization
	L["Turn random res messages on or keep the same message.\
	Default is off"] = "Turn random res messages on or keep the same message.\
	Default is off" -- Requires localization
	L["Unknown"] = "Unknown" -- Requires localization
	L["Use class colours for the target on the res bars"] = "Use class colours for the target on the res bars" -- Requires localization
	L["Where to print the res message.\
	Raid, Party, Say, Yell, Guild, or None.\
	Default is None"] = "Where to print the res message.\
	Raid, Party, Say, Yell, Guild, or None.\
	Default is None" -- Requires localization
	L["Yell"] = "Yell" -- Requires localization
	L["You are not in a group."] = "You are not in a group." -- Requires localization
	L["You are ressing %s"] = "You are ressing %s" -- Requires localization
	L["You cannot cast res spells."] = "Vous ne pouvez pas lancer des sorts pour Res."
	L["You don't have enough Mana to cast a res spell."] = "Vous n'avez pas assez de mana pour lancer un sort de Res."
end