# SmartRes2

SmartRes2 coordinates party and raid recovery after a partial or total wipe. It tracks resurrection activity, helps resurrection-capable players choose useful targets, reduces duplicate casts, and provides optional visual and chat feedback while the group recovers.

## Highlights

- **Smart resurrection targeting:** the single-target keybind chooses an eligible dead group member, avoids targets already being resurrected or with a useful resurrection offer, and prioritizes role and level before randomly choosing between equal candidates.
- **Secure resurrection keybinds:** SmartRes2 provides single-target, manual-target, combat resurrection, and—where supported—mass resurrection bindings without requiring visible action-bar buttons.
- **Resurrection bars:** colour-coded bars distinguish the fastest casts, competing casts, mass resurrection, and players waiting to accept a resurrection. The Bars module is highly configurable and includes simulated bars for previewing changes.
- **Configurable chat:** resurrection announcements and collision warnings can use appropriate group channels, whispers, or no output at all. Built-in random messages can be enabled, disabled, replaced, or supplemented with custom messages.

## Keybindings

SmartRes2 keybindings are configured through Blizzard's **Key Bindings** interface under the SmartRes2 category.

- Resurrection-capable classes can bind **Single Target Res Key** for SmartRes2's automatic target selection.
- Hunters should bind **Single Target Res Key**; SmartRes2 uses it for **Revive Pet**.
- Warlocks and other classes with a combat resurrection can bind **Combat Res Key**.
- **Manual Target Res** keeps conventional manual resurrection targeting available.
- **Mass Res Key** is available on game versions that support mass resurrection.

Once the SmartRes2 bindings you use are configured, the corresponding resurrection spells do not need to remain on your action bars. Removing them is optional, but can free action-bar slots.

SmartRes2 can also track non-class resurrection sources, such as items. Tracked casts can appear on the Bars display and can use the normal Chat announcements, but SmartRes2 deliberately does not provide smart keybindings for profession or item-based resurrection effects. Those should be activated normally.

## Bars and Chat

The Bars module shows resurrection casts and waiting resurrection offers in one configurable display. Frame size, scale, position, textures, borders, fonts, icons, colours, text, and other presentation options can be adjusted without changing SmartRes2's recovery logic. [Masque](https://www.curseforge.com/wow/addons/masque) can skin bar icons when it is installed.

The Chat module can announce single-target and mass resurrection casts and warn other resurrection casters when their cast will not finish first. The **Group** output follows the current group context, while explicit channel choices and **None** are available when more control is preferred.

## Supported World of Warcraft Versions

SmartRes2 supports:

- Retail
- Mists of Pandaria Classic
- Wrath Classic / Titan Reforged
- The Burning Crusade Classic
- Classic Era

Feature availability follows the capabilities of each game version. Mass resurrection bindings and options are shown only on versions where mass resurrection spells can exist. For game versions where spell ranks exist, SmartRes2 _automatically_ updates itself after the player trains new spells to **always** use the player's highest spell rank.

## Configuration

Open SmartRes2 through Blizzard's AddOns settings, right-click its Broker or minimap launcher, or use one of these slash commands:

```text
/smartres2
/smartres
/sr
```

The Broker/minimap launcher also provides quick Bars controls: left-click toggles the Bars frame lock, and middle-click shows or clears simulated test bars.

## Translating

SmartRes2 can be localized through the [WowAce localization portal](https://www.wowace.com/projects/smartres2/localization).
