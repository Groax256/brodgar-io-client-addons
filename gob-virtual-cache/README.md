# Gob Virtual Cache

Caches configured game objects to a persistent store and renders them as virtual ghosts in the 3D world when they leave view.

## Features

- **Resource Filtering**: Configure resource path patterns or exact names in `TARGET_RESOURCE_PATTERNS` inside `main.lua`.
- **Persistent Storage**: Saves discovered game objects, coordinates, facing, scale and state bytes (a crop's stage, a tree's growth) to the local SQLite store (`cached_virtual_gobs`). Only new or changed objects are written, batched into one transaction every couple of seconds.
- **Seamless Virtual Rendering**: Places a virtual ghost (`hafen.virtual():ghost()`) drawn with the object's own state when a tracked object leaves view (`GobRemoved`).
- **Automatic Cleanup**: Removes the virtual ghost when the real game object re-enters view (`GobAdded`), and forgets a cached object the player stands close to that the server no longer shows (chopped, picked, destroyed).
- **Exclusions**: `EXCLUDED_RESOURCE_PATTERNS` names what is never cached, even under a target pattern: vehicles and items, which move.

## Configuration

Edit `main.lua` to define which game objects are cached:

```lua
local TARGET_RESOURCE_PATTERNS = {
    "gfx/terobjs/trees/",
    "gfx/terobjs/bumlings/",
}
```
