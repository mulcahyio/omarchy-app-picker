# Changelog

All notable changes to Omarchy App Picker are recorded here. Versions follow
[Semantic Versioning](https://semver.org). The version in `manifest.json`
matches the git tag (`vX.Y.Z`).

## 1.0.0 (2026-10-11)

First release.

### Added
- Full-screen app grid, with a windowed mode (Ctrl+M or the Window button).
  Fits the size, orientation and scale of the screen it opens on.
- Symmetrical grid: column count from the screen width, columns divide it
  evenly.
- App icons and names from the same app list as the Omarchy Apps menu,
  including its hidden-app rules and launch behaviour.
- Sort A → Z / Z → A.
- Type-to-search using the Apps menu's matching.
- Ranked favorites: drag apps into the Favorites box at a chosen rank, drag to
  reorder, drag out or ✕ to remove; keyboard equivalents (Ctrl+F,
  Ctrl+← / Ctrl+→). Favorites view shows favorites only, in rank order.
- Bar icon placed after the Omarchy icon.
- `install.sh`: checks requirements, installs as a git checkout, enables the
  plugin and bar icon, adds a keybinding (Super + A by default) without
  overwriting an existing one, reloads Hyprland and restarts the shell.
  Supports `bindings.lua` and the older `bindings.conf`.
- `uninstall.sh`: removes the plugin, bar icon and keybinding block; keeps
  favorites unless `--purge`.
- Settings saved in `~/.local/state/omarchy-app-picker.json`.

### Known limitations
- Mouse drag-and-drop for favorites was not tested before release (no way to
  simulate mouse drags on the test machine). The keyboard equivalents
  (Ctrl+F, Ctrl+← / Ctrl+→) were tested and share the same ranking code.
- Changes to the plugin's QML take effect only after `omarchy restart shell`.
