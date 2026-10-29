# Inspect Info

Adds to what the game's own **Inspect** tells you. While the magnifying glass is up, a tooltip beside the
pointer names the resource of whatever it is on — any object, whether the game lets you inspect it or not,
and over bare ground the tile. Inspecting an object adds its resource name to the answer —
*Quality: 23  (gfx/terobjs/barrel)* — and the quality it reveals is written over the object as *q23*, where
it stays.

## Usage

Pick **Inspect** the way you always do and move the pointer over the world: the tooltip follows it, with the
quality underneath for an object you have already inspected. Left-click an object to inspect it. The answer
appears where the game always puts it, on screen and in the System log, with the resource name at its end.
If it carries a quality, the object is labelled with it.

Everything is in **Options ▸ AddOns ▸ Inspect Info**:

| Setting | Default |
|---|---|
| Name what the pointer is on while inspecting | on |
| Add the resource name to the Inspect answer | on |
| Show the inspected quality over the object | on |
| Text colour: white, yellow, orange, green, cyan or pink | white |
| Text size | 11 |
| Dark background behind the text, and how opaque it is | on, 60% |
| Height of the label above the object | 15 |
| Forget every quality | — |

## Notes

- **The tooltip needs to see the glass once per login.** The client is never told the cursor is the
  magnifying glass, only a number for it that changes with every login. Picking Inspect from the action menu
  teaches it at once. Picked from somewhere else, it is learned the first time an inspection is answered,
  and the tooltip appears from then on.
- A quality is filed under the object's resource name and the place it stands, so the label comes back when
  you walk away and return, after a relog, and on another character. Inspect the object again to update it.
  Something that moves (an animal, a cart) keeps its label while you see it, and is not recognised again
  once it has moved.
- The game's answer is a single line of text, so the resource name goes at its end rather than on a line
  of its own. An answer the client words from a resource of the server's carries no text to add to; the
  tooltip names those objects.
- `:inspectinfo` in the console writes, for a minute, every message an inspection moves: the click, the
  cursor, the answer and the System log line.
- The server never says which object an answer is about, so the object is taken from your click: the
  first quality that comes back after it is that object's, however long the walk over takes and wherever
  the pointer is by then. Your next click on the map replaces it, and a click with no answer for a minute
  is dropped.
