# XanaBars

Fixed action bars for World of Warcraft: Forever's Gamepad UI. Four action
bars appear at the bottom centre while you hold F1-F4. Below them, just above
the XP bar, a row of your own spells, items and macros is always shown,
together with a button holding the addons' minimap icons.

Version 2.4.0, for WoW Forever (interface 16001).
The Gamepad UI is still marked Alpha, so a game
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

| # | Bar               | Action slots | When it shows                                   |
|---|-------------------|--------------|-------------------------------------------------|
| 1 | Main bar          | 1-12, follows bar pages and stances/forms | while **F1** is held |
| 2 | Bottom left bar   | 61-72        | while **F2** is held                            |
| 3 | Bottom right bar  | 49-60        | while **F3** is held                            |
| 4 | Right bar         | 25-36        | while **F4** is held                            |

- **Bars 1-4** are hidden until you hold their key. The bar then appears at
  the bottom centre of the screen, on top of the Gamepad UI's own bars, in
  the gamepad layout (below). Let go of the key and it hides again. This
  works in combat.
- **The bottom row** is a list of spells, items and macros that you choose
  (see Edit mode). It isn't an action bar, so it doesn't use up one of the
  game's bars. Click an icon to cast or use it; this works in combat. Icons
  show cooldowns, and items show how many you have.
- While a held bar is up, the bottom row and the Gamepad UI's own buttons fade almost out of
  sight, and come back when you let go.
- **Minimap buttons:** the gear button at the right end of the bottom row holds the
  icons that addons put around the minimap. Click it to open them in a panel
  above it; clicking an icon, or the gear again, closes it. Those icons no longer show on the minimap.
  Blizzard's own minimap buttons (tracking, mail, clock and so on) stay where
  they are.
- Every bar, and the bottom row, sits on a solid dark gray panel inside the stone border of the
  game's classic dialog boxes.

Bars 1-4 use the game's standard action button template, so icons,
cooldowns, range/usable colouring, tooltips and drag and drop work as usual.

The layout is fixed: there are no settings to change.

The first time you log in with this version, whatever was on the old bar 5
(Right bar 2, action slots 37-48) is copied onto the bottom row.

## Edit mode

Type `/xbars edit` to put spells on bars 1-4 and on the bottom row. All four bars appear together
near the top of the screen, in a 2x2 grid:

```
 Bar 1 (F1)   Bar 2 (F2)
 Bar 3 (F3)   Bar 4 (F4)
```

Drag spells, items and macros onto them (or off them) as on the default bars.
Type `/xbars edit` again when you are done. Edit mode turns itself off when
combat starts, and can't be turned on in combat.

The bottom row also becomes editable, with an extra **+** slot at its end:

- Drop a spell (from the spellbook), an item (from your bags) or a macro
  (from the macro window) on **+** to add it, or on an icon to replace it.
  The replaced one is put on your cursor.
- Drag an icon off to move it: drop it somewhere else on the row, or on a bar.
- Right-click an icon to remove it.

## Gamepad layout

Bars 1-4 place their buttons like a controller's: a D-pad cross on the left,
a face-button cross on the right, a shoulder button above each, and buttons
11 and 12 side by side in the middle:

```
 1      11 12      10
     4         8
  3     5   7     9
     2         6
```

| Button | Position       | Button | Position        |
|--------|----------------|--------|-----------------|
| 1      | Left shoulder  | 6      | Face down       |
| 2      | D-pad down     | 7      | Face left       |
| 3      | D-pad left     | 8      | Face up         |
| 4      | D-pad up       | 9      | Face right      |
| 5      | D-pad right    | 10     | Right shoulder  |
| 11     | Middle, left   | 12     | Middle, right   |

## Commands

| Command              | Description                     |
|----------------------|---------------------------------|
| `/xbars`             | Show the usage                  |
| `/xbars edit`        | Turn edit mode on or off        |
| `/xbars edit on\|off` | Turn edit mode on, or off       |
| `/xbars frames`      | Show which Gamepad UI frame fades, and whether it was found |
| `/xbars frames all`  | List every visible frame named like a gamepad or action bar (for troubleshooting) |

## Good to know

- XanaBars takes over F1-F4 while it is loaded. Whatever they were bound to
  before (by default, targeting yourself and party members) comes back if
  you disable the addon.
- The hotkey text on a button shows your keyboard binding for the matching
  default bar button (Action Button 1-12, Bottom Left Bar, and so on).
- Quick Keybind Mode works on these buttons: hover a button and press a key.
  It sets the game's normal binding for that slot, the same one the default
  bars use.
- The bottom row is saved per character in a character macro named
  "XanaBars" (its body is a single `/xbdata ...` line). The Forever client
  doesn't load addon saved settings between sessions, so the macro is what
  carries the list over. Don't delete or edit it; renaming it or changing its
  icon is fine. It needs one free character macro slot.
- The row holds as many entries as fit in a 255-character macro: usually
  about 30 spells or items, fewer macros with long names.

## Troubleshooting

**Holding F1-F4 does nothing**

- Make sure edit mode is off (`/xbars edit off`).
- Another addon may also be overriding F1-F4.

**The Gamepad UI's buttons don't fade**

- The addon fades the frame named `GamepadMainActionBarFrame`. Type
  `/xbars frames` to check that it was found. `/xbars frames all` lists other
  frames named like gamepad or action bars, in case a game patch renames it.

**An addon's minimap icon isn't in the gear button's panel**

- Most addons' icons are found automatically. An icon the addon made without
  a name, or one smaller than a normal minimap button, is left on the minimap.
  Tell me the addon and it can be added.

**The bottom row is empty after logging in again**

- Check that the "XanaBars" macro exists in the macro window (`/macro`), on
  the tab with your character's name. If that character's macro slots are
  full, XanaBars can't create it and says so in chat; free a slot and change
  the row.

**"Could not create action buttons" message**

- The game's button template was not found in this client build.
  The addon needs an update.

**Lua errors**

- Turn on error display with `/console scriptErrors 1` and note the
  full error text.

## Uninstall

Delete the `Interface/AddOns/XanaBars` folder, and the "XanaBars" macro on
each character.
