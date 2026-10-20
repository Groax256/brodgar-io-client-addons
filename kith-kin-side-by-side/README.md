# Kith & Kin Side by Side

The Kith & Kin window shows one tab at a time: Kin, or your Village, or your Realm, picked with the buttons
under them. This addon lays them all out in one row instead, Kin on the left, with a thin vertical line
between two neighbours, so your kin list and your village are on screen together.

## Usage

Open Kith & Kin as usual. Every tab you have is already showing, and the window is as wide as the row.

Click a player in any list and every other list that has them picks them too: click a kin and their row in
your village's member list opens beside them, click a village member and their kin entry opens on the left.

## Permissions

- `widget.value`: to pick the player in the other lists, the same pick a click makes.

## Notes

- The tab buttons are hidden while the addon is on: there is nothing left to switch to.
- A village or realm you join later appears at the right end of the row as soon as the server sends it.
- Players are matched through your Kin list: a member who is not your kin shows as `???` and is picked in
  no other list, and two kin you gave the same name are left alone.
- The other lists scroll to the player they picked. On an older client they pick without scrolling.
- Disable the addon and the window goes back to one tab at a time, on the tab you had before.
