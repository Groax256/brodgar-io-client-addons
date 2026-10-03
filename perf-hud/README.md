# Performance HUD

Displays frames per second (FPS) and JVM heap memory usage in a compact, lightweight native window.

## Usage

1. **Hotkey**: Assign a key in **Options ▸ Game ▸ Keybindings ▸ Performance HUD** (`toggle`).
2. **Console**: Type `:perf`, `:fps`, or `:ram` in the console line to toggle visibility.
3. **Repositioning**: Click and drag the panel anywhere on screen. Its position is automatically remembered across sessions.

## Notes

- Updates statistics periodically every 0.5 seconds.
- Requests no client permissions.
- State (position and visibility) is persisted through the client store.
