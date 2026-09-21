# XanaBars

Shows the normal (keyboard/mouse) action bars in World of Warcraft: Forever
while the built-in Gamepad UI is turned on.

Version 1.2.0, written for the WoW Forever beta (interface 16001).
Not yet tested in game. The Gamepad UI is still marked Alpha, so a game
patch may break the addon until it is updated.

## Install

1. Copy the `XanaBars` folder into:

   ```
   World of Warcraft/<Forever client folder>/Interface/AddOns/
   ```

   You should end up with:

   ```
   Interface/AddOns/XanaBars/XanaBars.toc
   Interface/AddOns/XanaBars/XanaBars.lua
   ```

2. Restart the game.
3. On the character screen open AddOns and make sure XanaBars is ticked.
   If it is listed as out of date, tick "Load out of date AddOns".

## What it does

The Gamepad UI replaces the normal action bars with its own controller bars.
XanaBars adds its own copies of the normal bars on top of that:

| # | Bar               | Notes                                          |
|---|-------------------|------------------------------------------------|
| 1 | Main bar          | Slots 1-12, follows bar pages and stances/forms |
| 2 | Bottom left bar   |                                                |
| 3 | Bottom right bar  |                                                |
| 4 | Right bar         | Off by default                                 |
| 5 | Right bar 2       | Off by default                                 |

The buttons use the game's standard action button template, so icons,
cooldowns, range/usable colouring, tooltips and drag and drop work as usual.
Left click casts. Drag spells on and off the same way as on the default bars.

By default the bars appear only while the Gamepad UI is on and hide again
when it is turned off.

The addon does not change or re-show Blizzard's own bars.

## Commands

| Command                      | Description                                            |
|------------------------------|--------------------------------------------------------|
| `/xbars`                     | List all commands                                      |
| `/xbars unlock`              | Show blue boxes you can drag to move each bar          |
| `/xbars lock`                | Hide the boxes and fix the bars in place               |
| `/xbars mode auto`           | Show bars only while the Gamepad UI is on (default)    |
| `/xbars mode always`         | Show bars all the time                                 |
| `/xbars bar <1-5> on\|off`   | Enable or disable a bar                                |
| `/xbars cols <1-5> <1-12>`   | Buttons per row (e.g. `/xbars cols 1 6` = two rows)    |
| `/xbars scale <0.5-2>`       | Size of all bars                                       |
| `/xbars alpha <0.1-1>`       | Transparency of all bars                               |
| `/xbars empty on\|off`       | Show or hide empty slots                               |
| `/xbars hotkeys on\|off`     | Show or hide keyboard binding text on buttons          |
| `/xbars status`              | Show current settings and Gamepad UI detection         |
| `/xbars reset`               | Restore all default settings and positions             |

## Good to know

- While unlocked, a dragged bar snaps to nearby bars: edges line up, centres
  line up, and bars stack next to each other with the same gap as between
  buttons. It also snaps to the horizontal centre of the screen. Hold Shift
  while dragging to place a bar freely.
- The default positions are a guess. Use `/xbars unlock` to place the bars
  where they do not overlap the controller bars.
- Bars cannot be moved, resized, shown or hidden during combat (a game
  restriction). Changes made in combat apply when combat ends.
- Hidden empty slots still accept a dragged spell; they appear while you
  are holding one.
- The bars show your normal keyboard action slots. Beta testers report that
  the Gamepad UI keeps its controller abilities in a separate layout, so
  these bars are not a copy of the controller bars.
- The hotkey text shows your keyboard bindings for the matching default
  bar buttons (Action Button 1-12, Bottom Left Bar, and so on).
- Quick Keybind Mode works on these buttons: hover a button and press a key.
  It sets the game's normal binding for that slot (for example Action
  Button 3 or Bottom Left Bar Button 5), the same one the default bars use.
- Settings are saved per account in a general macro named "XanaBars" (its
  body is a single `/xbdata ...` line). The Forever beta doesn't load addon
  saved settings between sessions, so the macro is what carries them over.
  Don't delete or edit it; renaming it or changing its icon is fine. It needs
  one free account macro slot, and it is created the first time you change a
  setting or move a bar.

## Troubleshooting

**Bars do not appear**

- Type `/xbars status`. If Gamepad UI shows "off", turn the Gamepad UI on
  or use `/xbars mode always`.
- Check that each bar is "on" in the status list.
- Try `/xbars reset` in case a bar was dragged off screen.

**Settings are lost after logging out**

- Check that the "XanaBars" macro exists in the General tab of the macro
  window (`/macro`). If your account macro slots are full, XanaBars can't
  create it and says so in chat; free a slot and change any setting.

**"Could not create action buttons" message**

- The game's button template was not found in this client build.
  The addon needs an update.

**Lua errors**

- Turn on error display with `/console scriptErrors 1` and note the
  full error text together with the output of `/xbars status`.

## Uninstall

Delete the `Interface/AddOns/XanaBars` folder. To remove saved settings too,
delete the "XanaBars" macro, and `XanaBars.lua` and `XanaBars.lua.bak` from the
`SavedVariables` folder.
