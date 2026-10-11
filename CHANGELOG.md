# Changelog

All notable changes to Omarchy App Picker are recorded here. Versions follow
[Semantic Versioning](https://semver.org). The version in `manifest.json`
matches the git tag (`vX.Y.Z`).

## 1.0.1 (2026-10-11)

Licensing and documentation release, with one installer fix. The picker
itself (`AppPicker.qml`, `BarWidget.qml`) is unchanged from 1.0.0.

### Added
- **MIT License** (`LICENSE`), copyright 2026 Patrick Mulcahy
  <dev@mulcahy.io>. Release downloads now include it.
- **Install Guide** (`docs/INSTALL.md`): requirements and how to check them,
  access to the private repository, the recommended install with expected
  output, every installer option, what the installer changes and where it
  backs up, installing a specific version, installing with
  `omarchy plugin add`, installing from a zip, checking the install,
  updating, changing the keybinding, uninstalling, moving favorites to
  another machine, and troubleshooting.
- **Architecture document** (`docs/ARCHITECTURE.md`): system context,
  components and dependencies, runtime object tree, shell/plugin/IPC
  contracts, data model and saved state, open/launch/search/sort/drag-and-drop
  flows (with diagrams), layout rules, installer design, design decisions,
  risks and compatibility.
- Contact details (Patrick Mulcahy · dev@mulcahy.io) in the README, the
  documents and the plugin manifest (`author`).

### Changed
- `docs/DEVELOPMENT.md` is now a development guide (checks, testing,
  releasing, test record per version); the architecture content moved to
  `docs/ARCHITECTURE.md`.
- README: install section shortened to the essentials with a link to the
  Install Guide; file table lists all documents; version 1.0.1.
- Plugin manifest version 1.0.1.

### Fixed
- `install.sh` run from a checkout of a release tag (a detached commit)
  installed the plugin detached, so `git pull` in the installed folder failed.
  The installer now always installs the exact commit it is run from on a
  named branch (`main` for a tag) that tracks the same branch on GitHub.

### Compatibility
- Omarchy 4.0.4, Hyprland 0.56.2, Quickshell 0.3.1 (as 1.0.0).
- Upgrading from 1.0.0: `omarchy plugin update mulcahyio.app-picker`, then
  `omarchy restart shell`. Favorites and settings are kept.

## 1.0.0 (2026-10-11)

First release.

### Compatibility
- Omarchy 4.0.4, Hyprland 0.56.2, Quickshell 0.3.1.

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
- Documentation: README, CHANGELOG, development notes, screenshot.

### Fixed before release
- The shell's app-library facade arrives empty for third-party plugins on
  Omarchy 4.0.4, which left the grid blank; the picker now runs its own copy
  of Omarchy's `AppLibrary` when the facade is missing.
- Hover no longer steals the keyboard selection when the grid redraws under a
  resting pointer; the selection follows an app whose rank changes.
- Changing a favorite no longer resets the grid's scroll position.
- `uninstall.sh` now finds the keybinding block (its marker starts with
  `--`, which `grep` read as an option).
- Re-running `install.sh` no longer adds blank lines to `bindings.lua`.
- The installed copy is on `main` tracking GitHub, so updates work.

### Known limitations
- Mouse drag-and-drop for favorites was not tested before release (no way to
  simulate mouse drags on the test machine). The keyboard equivalents
  (Ctrl+F, Ctrl+← / Ctrl+→) were tested and share the same ranking code.
- Changes to the plugin's QML take effect only after `omarchy restart shell`.
