# Closest Door

Press **Shift+A** and the character goes through the nearest way in or out: no hunting for the door on
the side of a house, no finding the ladder in the dark.

## Usage

Stand within forty tiles of one and press **Shift+A**. The character right-clicks the nearest of:

- a building's front door: log cabin, timber house, stonestead, stone mansion, stone tower, windmill,
  and each of the great hall's three doors, outside and in;
- a door inside a building, a ladder, a staircase up or down, a cellar's stairs, a mine's way in or out.

Nothing within forty tiles, and the key does nothing.

## Options ▸ AddOns ▸ Closest Door

- **The key.** Shift+A for as long as you have not picked one yourself; change it here or in Options ▸
  Game ▸ Keybindings, and the key you pick (or None) stays.

## Notes

- It acts for the character on screen.
- `widget.send` is asked for because a building's door is one part of the building, and only the map's
  own click message can name that part.
- `client.settings` is asked for to put the key on Shift+A; the addon writes no other setting.
