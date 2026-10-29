# Quick Pick

Press **Q** and the character picks up the nearest critter or herb around them: no hunting for the
pixel to right-click, no radial menu to click through.

## Usage

1. Stand near a rabbit, a frog, a grub, a herb, a jellyfish.
2. Press **Q**. The character right-clicks the nearest one, and when that opens a menu with **Pick** on
   it, Pick is taken before the menu is drawn.

A critter within reach always comes first; with none in reach, the nearest herb. Nothing within reach,
and the key does nothing.

## Options ▸ AddOns ▸ Quick Pick

- **The key.** Q for as long as you have not picked one yourself; change it here or in Options ▸ Game ▸
  Keybindings, and the key you pick (or None) stays.
- **Reach**, in tiles, its value shown over the slider: 8 unless you move it.
- **Animals**, one checkbox each. Ticked is picked up. The critters, and the animals the Ring of Brodgar
  wiki says you catch by right-clicking, start ticked; the ones you fight or lead (bears, boars, deer,
  livestock, bats, ants and the like), where a right-click would only walk you up to them, start
  unticked. Hover a box for the resource name it matches. An animal the list does not name is picked up.

## Notes

- A menu without **Pick** on it is left open for you.
- It acts for the character on screen.
- `client.settings` is asked for to put the key on Q; the addon writes no other setting.
