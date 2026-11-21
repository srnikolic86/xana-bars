# XanaBars

Fixed action bars for World of Warcraft: Forever's Gamepad UI. One bar is
always on the right edge of the screen. Four more appear at the bottom centre
while you hold F1-F4.

Version 2.0.0, for WoW Forever (interface 16001).
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
| 5 | Right bar 2       | 37-48        | always, as a column on the right edge           |

- **Bar 5** is a single vertical column, centred on the right edge of the
  screen.
- **Bars 1-4** are hidden until you hold their key. The bar then appears at
  the bottom centre of the screen, on top of the Gamepad UI's own bars, in
  the gamepad layout (below) on a solid dark gray background. Let go of the
  key and it hides again. This works in combat.

The buttons use the game's standard action button template, so icons,
cooldowns, range/usable colouring, tooltips and drag and drop work as usual.

The layout is fixed: there are no settings to change.

## Edit mode

Type `/xbars edit` to put spells on bars 1-4. All four bars appear together
near the top of the screen, in a 2x2 grid:

```
 Bar 1 (F1)   Bar 2 (F2)
 Bar 3 (F3)   Bar 4 (F4)
```

Drag spells, items and macros onto them (or off them) as on the default bars.
Type `/xbars edit` again when you are done. Edit mode turns itself off when
combat starts, and can't be turned on in combat.

Bar 5 is always visible, so you can drag spells onto it at any time.

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

## Good to know

- XanaBars takes over F1-F4 while it is loaded. Whatever they were bound to
  before (by default, targeting yourself and party members) comes back if
  you disable the addon.
- The hotkey text on a button shows your keyboard binding for the matching
  default bar button (Action Button 1-12, Bottom Left Bar, and so on).
- Quick Keybind Mode works on these buttons: hover a button and press a key.
  It sets the game's normal binding for that slot, the same one the default
  bars use.
- XanaBars saves nothing. Older versions kept their settings in a character
  macro named "XanaBars"; it is no longer used and you can delete it.

## Troubleshooting

**Holding F1-F4 does nothing**

- Make sure edit mode is off (`/xbars edit off`).
- Another addon may also be overriding F1-F4.

**"Could not create action buttons" message**

- The game's button template was not found in this client build.
  The addon needs an update.

**Lua errors**

- Turn on error display with `/console scriptErrors 1` and note the
  full error text.

## Uninstall

Delete the `Interface/AddOns/XanaBars` folder. If an old "XanaBars" macro
is still on a character, delete it too.
